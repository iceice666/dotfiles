#!/usr/bin/env python3
"""Non-destructive macOS trust regression tests using temporary PEM fixtures.

All security commands are replaced by a local stub. No native bundle or
keychain is written. Run: python3 scripts/tests/test-tls-trust-macos.py
"""

import base64
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "tls-trust-macos.py"
SPEC = importlib.util.spec_from_file_location("tls_trust_macos", SCRIPT)
TRUST = importlib.util.module_from_spec(SPEC)
with patch.object(sys, "dont_write_bytecode", True):
    SPEC.loader.exec_module(TRUST)


def pem(content):
    return (b"-----BEGIN CERTIFICATE-----\n" + base64.b64encode(content)
            + b"\n-----END CERTIFICATE-----")


class MacOSTrustTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="macos-trust-test-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.bundle = self.directory / "cert.pem"
        self.backup = self.bundle.with_name(self.bundle.name + TRUST.BACKUP_SUFFIX)
        self.calls = self.directory / "security-calls.jsonl"
        self.failure = self.directory / "fail-security"
        self.security = self.directory / "security"
        self.security.write_text(
            f"#!{sys.executable}\n"
            "import hashlib, json, pathlib, ssl, sys\n"
            f"if pathlib.Path({str(self.failure)!r}).exists(): sys.exit(7)\n"
            "certificate = pathlib.Path(sys.argv[-1]).read_text()\n"
            "fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(certificate)).hexdigest()\n"
            f"with open({str(self.calls)!r}, 'a') as log:\n"
            "    log.write(json.dumps([sys.argv[1:-1], fingerprint]) + '\\n')\n"
        )
        self.security.chmod(0o755)
        self.roots = [pem(f"blocked-fixture-{index}".encode()) for index in range(4)]
        self.root_source = self.directory / "distrust-roots.pem"
        self.root_source.write_bytes(b"\n".join(self.roots))
        self.allowed = pem(b"trusted-fixture")
        fingerprints = {
            hashlib.sha256(f"blocked-fixture-{index}".encode()).hexdigest(): name
            for index, name in enumerate(TRUST.BLOCKED.values())
        }
        blocked = patch.object(TRUST, "BLOCKED", fingerprints)
        blocked.start()
        self.addCleanup(blocked.stop)
        self.original = b"# operator comment\n" + b"\n".join(self.roots) + b"\n" + self.allowed + b"\n# end\n"
        self.bundle.write_bytes(self.original)
        self.bundle.chmod(0o640)

    def apply(self, **arguments):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return TRUST.apply(self.bundle, str(self.security), roots=self.root_source, **arguments)

    def logged_calls(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_filters_only_blocked_pems_and_preserves_text(self):
        self.assertEqual(self.apply(), 0)
        expected = self.original
        for certificate in self.roots:
            expected = expected.replace(certificate, b"")
        self.assertEqual(self.bundle.read_bytes(), expected)
        self.assertEqual(self.backup.read_bytes(), self.original)

    def test_system_keychain_explicit_denies(self):
        self.apply()
        calls = self.logged_calls()
        self.assertEqual(len(calls), 4)
        self.assertEqual({fingerprint for _, fingerprint in calls}, set(TRUST.BLOCKED))
        for arguments, _ in calls:
            self.assertEqual(arguments, ["add-trusted-cert", "-d", "-r", "deny", "-k", TRUST.KEYCHAIN])

    def test_packaged_roots_apply_denies_when_native_bundle_has_none(self):
        self.bundle.write_bytes(self.allowed + b"\n")
        self.assertEqual(self.apply(), 0)
        self.assertEqual(len(self.logged_calls()), 4)
        self.assertEqual(self.bundle.read_bytes(), self.allowed + b"\n")

    def test_missing_root_source_fails_before_backup_or_security(self):
        self.root_source.unlink()
        with self.assertRaises(OSError):
            self.apply()
        self.assertFalse(self.backup.exists())
        self.assertFalse(self.calls.exists())

    def test_incomplete_root_source_fails_before_backup_or_security(self):
        self.root_source.write_bytes(self.roots[0])
        with self.assertRaisesRegex(ValueError, "all four authenticated"):
            self.apply()
        self.assertFalse(self.backup.exists())
        self.assertFalse(self.calls.exists())

    def test_unexpected_root_source_fails_before_backup_or_security(self):
        self.root_source.write_bytes(b"\n".join(self.roots) + b"\n" + self.allowed)
        with self.assertRaisesRegex(ValueError, "unexpected or duplicate"):
            self.apply()
        self.assertFalse(self.backup.exists())
        self.assertFalse(self.calls.exists())

    def test_repeat_preserves_backup_and_reapplies_denies(self):
        self.apply()
        backup_inode = self.backup.stat().st_ino
        bundle_inode = self.bundle.stat().st_ino
        filtered = self.bundle.read_bytes()
        self.apply()
        self.assertEqual(self.bundle.read_bytes(), filtered)
        self.assertEqual(self.bundle.stat().st_ino, bundle_inode)
        self.assertEqual(self.backup.read_bytes(), self.original)
        self.assertEqual(self.backup.stat().st_ino, backup_inode)
        self.assertEqual(len(self.logged_calls()), 8)

    def test_preserves_bundle_and_backup_metadata(self):
        previous = self.bundle.stat()
        self.apply()
        for path in (self.bundle, self.backup):
            metadata = path.stat()
            self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o640)
            self.assertEqual((metadata.st_uid, metadata.st_gid), (previous.st_uid, previous.st_gid))

    def test_security_failure_does_not_filter_bundle(self):
        self.failure.touch()
        with self.assertRaises(subprocess.CalledProcessError):
            self.apply()
        self.assertEqual(self.bundle.read_bytes(), self.original)
        self.assertEqual(self.backup.read_bytes(), self.original)
        self.failure.unlink()
        self.assertEqual(self.apply(), 0)

    def test_security_timeout_does_not_filter_bundle(self):
        with patch.object(TRUST.subprocess, "run", side_effect=subprocess.TimeoutExpired("security", 120)) as run:
            with self.assertRaises(subprocess.TimeoutExpired):
                self.apply()
        self.assertEqual(run.call_args.kwargs["timeout"], 120)
        self.assertEqual(self.bundle.read_bytes(), self.original)
        self.assertEqual(self.backup.read_bytes(), self.original)

    def test_check_is_read_only_and_reports_blocked_roots(self):
        self.assertEqual(self.apply(check=True), 1)
        self.assertFalse(self.backup.exists())
        self.assertFalse(self.calls.exists())
        self.assertEqual(self.bundle.read_bytes(), self.original)
        self.apply()
        self.assertEqual(self.apply(check=True), 0)

    def test_bundle_symlink_rejected_without_touching_target(self):
        target = self.directory / "target"
        self.bundle.rename(target)
        self.bundle.symlink_to(target)
        with self.assertRaises(OSError):
            self.apply()
        self.assertEqual(target.read_bytes(), self.original)
        self.assertFalse(self.backup.exists())

    def test_backup_symlink_rejected(self):
        target = self.directory / "target"
        target.write_bytes(b"do not modify")
        self.backup.symlink_to(target)
        with self.assertRaises(OSError):
            self.apply()
        self.assertEqual(target.read_bytes(), b"do not modify")
        self.assertEqual(self.bundle.read_bytes(), self.original)
        self.assertFalse(self.calls.exists())

    def test_malformed_bundle_rejected_before_backup(self):
        self.bundle.write_bytes(self.original + b"-----BEGIN CERTIFICATE-----\ntruncated")
        with self.assertRaises(ValueError):
            self.apply()
        self.assertFalse(self.backup.exists())
        self.assertFalse(self.calls.exists())

    def test_empty_bundle_rejected(self):
        self.bundle.write_bytes(b"# no certificates\n")
        with self.assertRaises(ValueError):
            self.apply()
        self.assertFalse(self.backup.exists())

    def test_nonregular_bundle_rejected(self):
        self.bundle.unlink()
        self.bundle.mkdir()
        with self.assertRaises((OSError, ValueError)):
            self.apply()

    def test_production_action_requires_root(self):
        with patch.object(TRUST.os, "geteuid", return_value=501):
            with self.assertRaises(PermissionError):
                TRUST.apply(self.bundle, TRUST.DEFAULT_SECURITY)
        self.assertFalse(self.backup.exists())

    def test_alternate_bundle_requires_security_stub_even_as_root(self):
        with patch.object(TRUST.os, "geteuid", return_value=0):
            with self.assertRaises(ValueError):
                TRUST.apply(self.bundle, TRUST.DEFAULT_SECURITY)
        self.assertFalse(self.backup.exists())

    def test_concurrent_bundle_change_not_overwritten(self):
        original_run = subprocess.run

        def mutate(*arguments, **keywords):
            result = original_run(*arguments, **keywords)
            self.bundle.write_bytes(self.allowed + b"\n# concurrent update\n")
            return result

        with patch.object(TRUST.subprocess, "run", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "changed during distrust activation"):
                self.apply()
        self.assertIn(b"# concurrent update", self.bundle.read_bytes())
        self.assertFalse(list(self.directory.glob(".cert.pem-*")))


class FingerprintConsistencyTests(unittest.TestCase):
    def test_packaged_public_roots_match_exact_policy(self):
        parsed = TRUST.certificates(TRUST.DEFAULT_ROOTS.read_bytes())
        self.assertEqual(len(parsed), 4)
        self.assertEqual({fingerprint for _, fingerprint in parsed}, set(TRUST.BLOCKED))

    def test_matches_pi_trust_policy(self):
        policy = (SCRIPT.parents[1] / "pkgs/pi-bin/trust.test.cjs").read_text()
        self.assertEqual(set(re.findall(r"'[0-9a-f]{64}'", policy)),
                         {repr(fingerprint) for fingerprint in TRUST.BLOCKED})


if __name__ == "__main__":
    unittest.main()
