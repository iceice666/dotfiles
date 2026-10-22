#!/usr/bin/env python3
"""Non-destructive tests for Alpine's embedded trust activation.

Extract the actual activation shell, replacing system paths with temporary
fixtures and package/update commands with stubs. No host trust is changed.
Run: python3 scripts/tests/test-alpine-trust.py
Or test the evaluated activation: pass --script /path/to/rendered-activation.sh.
Requires GNU sed (gsed or a local Nix store installation also works).
"""

import argparse
import glob
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


MODULE = Path(__file__).resolve().parents[2] / "common/home-alpine/default.nix"
RENDERED_SCRIPT = None
ROOTS = (
    "mozilla/emSign_ECC_Root_CA_-_G3.crt",
    "mozilla/emSign_ECC_Root_CA_-_C3.crt",
    "mozilla/emSign_Root_CA_-_C1.crt",
    "mozilla/Comodo_AAA_Services_root.crt",
)


def find_gnu_sed():
    candidates = [shutil.which("gsed"), shutil.which("sed")]
    candidates.extend(glob.glob("/nix/store/*-gnused-*/bin/sed"))
    for candidate in filter(None, candidates):
        result = subprocess.run([candidate, "--version"], capture_output=True, text=True)
        if result.returncode == 0 and "GNU sed" in result.stdout:
            return candidate
    raise unittest.SkipTest("GNU sed is required")


def extract_activation():
    match = re.search(
        r"home\.activation\.configureAlpineTrust\s*=\s*"
        r"lib\.hm\.dag\.entryBetween\s*\[.*?\]\s*\[.*?\]\s*''\n(.*?)\n\s*'';",
        MODULE.read_text(),
        re.DOTALL,
    )
    if match is None:
        raise AssertionError("Could not locate configureAlpineTrust activation shell")
    return match.group(1)


class AlpineTrustTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.activation = (
            RENDERED_SCRIPT.read_text() if RENDERED_SCRIPT else extract_activation()
        )
        cls.sed = find_gnu_sed()
        cls.grep = shutil.which("grep")
        if cls.grep is None:
            raise unittest.SkipTest("grep is required")

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="alpine-trust-test-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.config = self.directory / "ca-certificates.conf"
        self.installed = self.directory / "installed"
        self.calls = self.directory / "calls"
        self.apk = self.directory / "apk"
        self.updater = self.directory / "update-ca-certificates"
        self.apk.write_text(
            '#!/bin/sh\n'
            f'printf "apk %s\\n" "$*" >> "{self.calls}"\n'
            'case "$1" in\n'
            f'  info) test -e "{self.installed}";;\n'
            f'  add) touch "{self.installed}";;\n'
            '  *) exit 2;;\n'
            'esac\n'
        )
        self.updater.write_text(
            f'#!/bin/sh\nprintf "update\\n" >> "{self.calls}"\n'
        )
        self.apk.chmod(0o755)
        self.updater.chmod(0o755)
        self.script = self.activation
        for package, binary, replacement in (
            ("gnused", "sed", self.sed),
            ("gnugrep", "grep", self.grep),
        ):
            pattern = (
                r"(?:\$\{pkgs\." + package + r"\}|/nix/store/[^/\s]+-"
                + package + r"-[^/\s]+)/bin/" + binary
            )
            self.script, count = re.subn(pattern, lambda _: replacement, self.script)
            self.assertGreater(count, 0, "Missing expected executable " + package)
        for original, replacement in (
            ("/sbin/apk", self.apk),
            ("/usr/sbin/update-ca-certificates", self.updater),
            ("/etc/ca-certificates.conf", self.config),
        ):
            self.assertIn(original, self.script)
            self.script = self.script.replace(original, str(replacement))
        self.assertNotIn("${", self.script, "Unresolved Nix interpolation")
        self.assertNotRegex(self.script, r"(?<!\S)/(?:etc|sbin|usr)/")
        self.config.write_text("# retain comments\nlocal/operator.crt\n")

    def activate(self):
        return subprocess.run(
            ["bash", "-euc", self.script], capture_output=True, text=True
        )

    def assert_success(self):
        result = self.activate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def assert_disabled(self):
        lines = self.config.read_text().splitlines()
        for root in ROOTS:
            self.assertNotIn(root, lines)
            self.assertEqual(lines.count("!" + root), 1)

    def test_shell_syntax(self):
        subprocess.run(["bash", "-n"], input=self.script, text=True, check=True)

    def test_exact_roots_disabled_and_other_entries_preserved(self):
        original = (
            "# retain comments\nlocal/operator.crt\nmozilla/Unrelated_Root.crt\n"
            "mozilla/emSign_Root_CA_-_G1.crt\n"
        )
        self.config.write_text(original + "\n".join(ROOTS) + "\n")
        self.assert_success()
        self.assertTrue(self.config.read_text().startswith(original))
        self.assert_disabled()

    def test_missing_package_installed_once(self):
        self.assert_success()
        self.assertIn("apk add --no-cache ca-certificates\n", self.calls.read_text())
        self.calls.write_text("")
        self.assert_success()
        self.assertNotIn("apk add", self.calls.read_text())
        self.assertIn("update\n", self.calls.read_text())

    def test_already_disabled_roots_are_idempotent(self):
        original = "# retain comments\n" + "\n".join("!" + root for root in ROOTS) + "\n"
        self.config.write_text(original)
        self.assert_success()
        self.assert_success()
        self.assertEqual(self.config.read_text(), original)
        self.assert_disabled()

    def test_upstream_absent_roots_get_persistent_disabled_entries(self):
        self.assert_success()
        self.assert_disabled()
        original = self.config.read_text()
        self.assert_success()
        self.assertEqual(self.config.read_text(), original)

    def test_unterminated_last_line_preserved(self):
        self.config.write_text("local/operator.crt")
        self.assert_success()
        self.assertTrue(self.config.read_text().startswith("local/operator.crt\n"))
        self.assert_disabled()

    def test_missing_configuration_fails_before_update(self):
        self.config.unlink()
        result = self.activate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("configuration or update tool is missing", result.stderr)
        self.assertNotIn("update\n", self.calls.read_text())

    def test_missing_updater_fails_without_modifying_configuration(self):
        self.updater.unlink()
        original = self.config.read_text()
        result = self.activate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("configuration or update tool is missing", result.stderr)
        self.assertEqual(self.config.read_text(), original)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--script", type=Path, help="Evaluated configureAlpineTrust shell body")
    arguments, unittest_arguments = parser.parse_known_args()
    RENDERED_SCRIPT = arguments.script
    unittest.main(argv=[__file__, *unittest_arguments])
