"""Non-destructive fixtures for audit allowlists and bounded log summaries."""

import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest import mock

PATH = pathlib.Path(__file__).resolve().parents[2] / "hosts/lumo/home/services/audit-evidence.py"
SPEC = importlib.util.spec_from_file_location("audit_evidence", PATH)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class EvidenceTests(unittest.TestCase):
    def test_proxy_allowlist(self):
        static = {"secret": "SENTINEL", "entryPoints": {"web": {"address": ":80"}}}
        dynamic = {"http": {"routers": {"app": {
            "rule": "Host(`example.org`) && Path(`/secret-SENTINEL`)",
            "middlewares": ["auth"], "tls": {},
        }}, "middlewares": {"auth": {"forwardAuth": {
            "address": "http://auth/?token=SENTINEL", "trustForwardHeader": True,
        }, "headers": {"secret": "SENTINEL"}}}}}
        result = audit.traefik_summary(static, dynamic)
        self.assertNotIn("SENTINEL", json.dumps(result))
        self.assertEqual(result["routers"]["app"]["hosts"], ["example.org"])
        self.assertTrue(result["middlewares"]["auth"]["trust_forward_header"])

    def test_scalar_types_and_inherited_tls(self):
        summary = audit.traefik_summary({"entryPoints": {"websecure": {
            "http": {"tls": {}}, "forwardedHeaders": {"insecure": {"SENTINEL": True}},
        }}}, {"http": {"routers": {"app": {"entryPoints": ["websecure"]}},
                      "middlewares": {"auth": {"forwardAuth": {"trustForwardHeader": "SENTINEL"}}}}})
        self.assertTrue(summary["entrypoints"]["websecure"]["entrypoint_tls_declared"])
        self.assertFalse(summary["routers"]["app"]["router_tls_declared"])
        self.assertNotIn("SENTINEL", json.dumps(summary))
        self.assertIsNone(audit.integer(True))
        self.assertIsNone(audit.boolean("SENTINEL"))
        self.assertIsNone(audit.digest("SENTINEL"))

    def test_active_config_discovery(self):
        proc = mock.MagicMock()
        proc.stat.return_value.st_uid = 0
        def child(name):
            value = mock.MagicMock()
            if name == "exe":
                value.resolve.return_value = pathlib.Path("/nix/store/test/bin/.traefik-wrapped")
            if name == "cmdline":
                value.read_bytes.return_value = b"traefik\0--configFile=/nix/store/config.yml\0"
            return value
        proc.__truediv__.side_effect = child
        with mock.patch.object(audit.pathlib.Path, "glob", return_value=[proc]):
            self.assertEqual(audit.active_config("traefik", "--configFile"), "/nix/store/config.yml")
        proc.stat.return_value.st_uid = 1000
        with mock.patch.object(audit.pathlib.Path, "glob", return_value=[proc]):
            with self.assertRaises(ValueError):
                audit.active_config("traefik", "--configFile")

    def test_authelia_allowlist_and_order(self):
        result = audit.authelia_summary({"session": {"secret": "SENTINEL"}, "access_control": {
            "default_policy": "deny", "rules": [
                {"domain": "public.example", "policy": "bypass"},
                {"domain": "private.example", "policy": "two_factor", "subject": "SENTINEL"},
            ],
        }})
        self.assertNotIn("SENTINEL", json.dumps(result))
        self.assertEqual([r["policy"] for r in result["rules"]], ["bypass", "two_factor"])
        self.assertTrue(result["rules"][1]["has_subject_constraint"])

    def test_bounded_logs_no_raw_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "traefik.log"
            path.write_text("x" * 70000 + "\n" + '\n'.join(
                json.dumps({"time": "2026-10-26T04:00:00Z", "level": "error", "DownstreamStatus": 401,
                            "msg": "unauthorized SENTINEL", "Cookie": "SENTINEL"}) for _ in range(600)))
            result = audit.log_evidence(path)
            self.assertTrue(result["truncated_bytes"])
            self.assertLessEqual(result["bytes_read"], audit.MAX_BYTES)
            self.assertLessEqual(result["records_sampled"], audit.MAX_LINES)
            self.assertNotIn("SENTINEL", json.dumps(result))
            self.assertGreater(result["http_status_counts"]["401"], 0)
            self.assertEqual(audit.log_evidence(path.parent / "missing")["status"], "gap")

    def test_missing_current_logs_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            output, failed = audit.application_logs(pathlib.Path(directory))
            self.assertTrue(failed)
            self.assertEqual(len(output["files"]), len(audit.SERVICES))

    def test_errors_never_echo_input(self):
        with mock.patch.object(audit, "active_config", side_effect=ValueError("SENTINEL")):
            output, failed = audit.proxy_evidence()
        self.assertTrue(failed)
        self.assertNotIn("SENTINEL", json.dumps(output))

    def test_container_allowlist(self):
        inspect = [{"Id": "abc", "Name": "app", "ImageDigest": "sha256:123", "Config": {
            "Env": ["TOKEN=SENTINEL"]}, "HostConfig": {"Privileged": False, "Memory": 100,
            "Binds": ["SENTINEL"], "NetworkMode": "host"}}]
        with mock.patch.object(audit.subprocess, "run", side_effect=[
            mock.Mock(stdout=b"abc\n"), mock.Mock(stdout=json.dumps(inspect).encode()),
        ]):
            output, failed = audit.container_evidence("podman")
        self.assertFalse(failed)
        self.assertNotIn("SENTINEL", json.dumps(output))
        self.assertEqual(output["containers"][0]["memory_limit"], 100)


if __name__ == "__main__":
    unittest.main()
