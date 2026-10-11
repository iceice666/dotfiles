#!/usr/bin/env python3
"""Isolated contract tests for media-key.sh; no real desktop/device access."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


class MediaKeyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="media-key-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.log = self.root / "calls.jsonl"
        self.snapshot = json.dumps({"audio_speaker_value": "42", "audio_speaker_text": 'Output "quoted" - device name 路', "brightness_value": "57"})
        mock = self.root / "mock.py"
        mock.write_text('''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
name = Path(sys.argv[0]).name
with open(os.environ["TEST_LOG"], "a") as log:
    log.write(json.dumps([name, *sys.argv[1:]]) + "\\n")
if name == os.environ.get("FAIL_TOOL"):
    sys.exit(7)
if name == "ags":
    time.sleep(float(os.environ.get("AGS_SLEEP", "0")))
if name == "shell-state":
    print(os.environ["TEST_SNAPSHOT"])
''')
        mock.chmod(0o755)
        for name in ("shell-state", "brightnessctl", "ags"):
            (self.root / name).symlink_to(mock)
        source = Path(__file__).with_name("media-key.sh").read_text()
        replacements = {
            "@shellState@": self.root / "shell-state",
            "@shellStateConfig@": self.root / "config.json",
            "@brightnessctl@": self.root / "brightnessctl",
            "@timeout@": shutil.which("timeout"),
            "@ags@": self.root / "ags",
        }
        self.assertIsNotNone(replacements["@timeout@"], "GNU timeout required")
        for token, path in replacements.items():
            source = source.replace(token, str(path))
        self.wrapper = self.root / "wrapper.sh"
        self.wrapper.write_text(source)
        self.env = {**os.environ, "TEST_LOG": str(self.log), "TEST_SNAPSHOT": self.snapshot}

    def run_key(self, *args, **env):
        return subprocess.run(["bash", str(self.wrapper), *args], env={**self.env, **env}, capture_output=True, text=True, timeout=5)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def clear_calls(self):
        self.log.unlink(missing_ok=True)

    def test_audio_actions_and_snapshot_argument(self):
        for kind, action in (("speaker", "up"), ("speaker", "down"), ("speaker", "toggle"), ("mic", "toggle")):
            with self.subTest(kind=kind, action=action):
                self.clear_calls()
                self.assertEqual(self.run_key(kind, action).returncode, 0)
                expected = ["audio", "toggle", kind] if action == "toggle" else ["audio", "volume", kind, action, "--step", "0.05"]
                self.assertEqual(self.calls(), [
                    ["shell-state", "--config-file", str(self.root / "config.json"), *expected],
                    ["ags", "request", "osd", kind, self.snapshot],
                ])

    def test_relative_brightness_and_post_action_refresh(self):
        for action, amount in (("up", "+10%"), ("down", "10%-")):
            with self.subTest(action=action):
                self.clear_calls()
                self.assertEqual(self.run_key("brightness", action).returncode, 0)
                self.assertEqual(self.calls(), [
                    ["brightnessctl", "--class=backlight", "set", amount],
                    ["shell-state", "--config-file", str(self.root / "config.json"), "refresh", "brightness"],
                    ["ags", "request", "osd", "brightness", self.snapshot],
                ])

    def test_action_or_snapshot_failures_do_not_notify(self):
        for kind, failure in (("speaker", "shell-state"), ("brightness", "brightnessctl"), ("brightness", "shell-state")):
            with self.subTest(kind=kind, failure=failure):
                self.clear_calls()
                self.assertNotEqual(self.run_key(kind, "up", FAIL_TOOL=failure).returncode, 0)
                self.assertFalse(any(call[0] == "ags" for call in self.calls()))

    def test_absent_or_failed_ags_does_not_fail_action(self):
        self.assertEqual(self.run_key("speaker", "toggle", FAIL_TOOL="ags").returncode, 0)
        (self.root / "ags").unlink()
        self.clear_calls()
        self.assertEqual(self.run_key("brightness", "down").returncode, 0)
        self.assertEqual([call[0] for call in self.calls()], ["brightnessctl", "shell-state"])

    def test_invalid_arguments_never_run_tools(self):
        for args in ((), ("unknown",), ("speaker",), ("mic", "up"), ("mic", "down"), ("speaker", "set"), ("brightness", "toggle"), ("brightness", "up", "extra"), ("speaker", "toggle", "extra")):
            with self.subTest(args=args):
                self.clear_calls()
                self.assertNotEqual(self.run_key(*args).returncode, 0)
                self.assertEqual(self.calls(), [])

    def test_notification_timeout_is_bounded(self):
        start = time.monotonic()
        result = self.run_key("speaker", "up", AGS_SLEEP="30")
        elapsed = time.monotonic() - start
        self.assertEqual(result.returncode, 0)
        self.assertLess(elapsed, 4)
        self.assertTrue(any(call[0] == "ags" for call in self.calls()))


if __name__ == "__main__":
    unittest.main()
