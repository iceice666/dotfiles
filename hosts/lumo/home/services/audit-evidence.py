"""Read-only, allowlisted audit evidence. Never emit raw config, logs or errors."""

import collections
import datetime
import json
import os
import pathlib
import re
import subprocess
import sys

import yaml

MAX_BYTES = 65536
MAX_LINES = 500
SERVICES = ("prometheus", "pirc-daemon", "blocky", "traefik", "authelia")


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def identifier(value):
    return value if isinstance(value, str) and re.fullmatch(r"[\w.@:/-]{1,200}", value) else None


def boolean(value):
    return value if type(value) is bool else None


def integer(value):
    return value if type(value) is int else None


def digest(value):
    return value if isinstance(value, str) and re.fullmatch(r"(?:sha256:)?[a-f0-9]{12,64}", value) else None


def read_yaml(path):
    path = pathlib.Path(path).resolve()
    # These services use immutable, generated store files, not secret files.
    if not str(path).startswith("/nix/store/") or not path.is_file() or path.stat().st_size > 2 * 1024 * 1024:
        raise ValueError("unsupported config")
    return yaml.safe_load(path.read_text())


def active_config(service, option):
    matches = []
    for proc in pathlib.Path("/proc").glob("[0-9]*"):
        try:
            executable = (proc / "exe").resolve()
            if proc.stat().st_uid != 0 or not str(executable).startswith("/nix/store/"):
                continue
            if executable.name not in {service, f".{service}-wrapped"}:
                continue
            args = (proc / "cmdline").read_bytes().decode().split("\0")
            for index, arg in enumerate(args):
                if arg == option:
                    matches.append(args[index + 1])
                elif arg.startswith(option + "="):
                    matches.append(arg.split("=", 1)[1])
        except (OSError, UnicodeError, IndexError):
            continue
    if len(matches) != 1:
        raise ValueError("active config not uniquely identified")
    return matches[0]


def traefik_summary(static, dynamic):
    http = dynamic.get("http", {})
    return {
        "entrypoints": {
            identifier(name): {
                "address": identifier(value.get("address")),
                "trusted_proxy_ips": [identifier(ip) for ip in value.get("forwardedHeaders", {}).get("trustedIPs", [])],
                "insecure_forwarded_headers": boolean(value.get("forwardedHeaders", {}).get("insecure", False)),
                "entrypoint_tls_declared": "tls" in value.get("http", {}),
            }
            for name, value in static.get("entryPoints", {}).items() if identifier(name)
        },
        "routers": {
            identifier(name): {
                "hosts": re.findall(r"Host\(`([a-zA-Z0-9.-]+)`\)", value.get("rule", "")),
                "has_client_ip_constraint": "ClientIP(" in value.get("rule", ""),
                "has_path_constraint": "Path" in value.get("rule", ""),
                "entrypoints": [identifier(v) for v in value.get("entryPoints", [])],
                "middlewares": [identifier(v) for v in value.get("middlewares", [])],
                "service": identifier(value.get("service")),
                "router_tls_declared": "tls" in value,
                "priority": value.get("priority") if isinstance(value.get("priority"), int) else None,
            }
            for name, value in http.get("routers", {}).items() if identifier(name)
        },
        "middlewares": {
            identifier(name): {
                "types": [identifier(key) for key in value],
                "forward_auth_configured": "forwardAuth" in value,
                "trust_forward_header": boolean(value.get("forwardAuth", {}).get("trustForwardHeader", False)),
            }
            for name, value in http.get("middlewares", {}).items() if identifier(name)
        },
        "limits": "Rule paths, header values, backend URLs and auth endpoints omitted; middleware presence is not an authorization test.",
    }


def authelia_summary(config):
    access = config.get("access_control", {})
    policies = {"deny", "bypass", "one_factor", "two_factor"}
    return {
        "default_policy": access.get("default_policy") if access.get("default_policy") in policies else "unknown",
        "rules": [
            {
                "domains": [identifier(v) for v in ([rule.get("domain")] if isinstance(rule.get("domain"), str) else rule.get("domain", []))],
                "policy": rule.get("policy") if rule.get("policy") in policies else "unknown",
                "has_subject_constraint": "subject" in rule,
                "has_network_constraint": "networks" in rule,
                "has_resource_constraint": "resources" in rule,
            } for rule in access.get("rules", [])
        ],
        "limits": "Ordered config rules only; users, sessions, secrets and runtime environment overrides omitted. Not an authorization test.",
    }


def proxy_evidence():
    output = {}
    failed = False
    for service, option in (("traefik", "--configFile"), ("authelia", "--config")):
        try:
            path = active_config(service, option)
            config = read_yaml(path)
            if service == "traefik":
                dynamic = read_yaml(config["providers"]["file"]["filename"])
                summary = traefik_summary(config, dynamic)
            else:
                summary = authelia_summary(config)
            output[service] = {"status": "ok", "source": path, "summary": summary}
        except Exception:
            # Exception text may include secrets or unparsed config content.
            output[service] = {"status": "gap", "reason": "active config unavailable, unsupported or invalid"}
            failed = True
    return output, failed


def log_evidence(path):
    result = {"source": str(path), "collected_at": now(), "byte_limit": MAX_BYTES, "line_limit": MAX_LINES}
    try:
        with path.open("rb") as stream:
            stat = os.fstat(stream.fileno())
            start = max(0, stat.st_size - MAX_BYTES)
            stream.seek(start)
            data = stream.read(MAX_BYTES)
        lines = data.splitlines()
        if start and lines:
            lines = lines[1:]  # Never interpret a partial first record.
        selected = lines[-MAX_LINES:]
        counts = collections.Counter()
        levels = collections.Counter()
        statuses = collections.Counter()
        timestamps = []
        structured_records = 0
        unclassified_records = 0
        for raw in selected:
            text = raw.decode("utf-8", errors="replace")
            classified = False
            for category, pattern in {
                "authentication_failure": r"authentication.*fail|invalid credentials|access denied|unauthorized",
                "startup_failure": r"failed to start|startup.*fail|error.*starting",
                "restart_or_exit": r"respawn|restarting|shutting down|exited",
                "resource_pressure": r"out of memory|oom|no space left|too many open files",
                "upstream_failure": r"connection refused|upstream.*error|timeout|timed out",
                "warning_or_error": r"\b(error|warn|warning|fatal|panic)\b",
            }.items():
                if re.search(pattern, text, re.I):
                    counts[category] += 1
                    classified = True
            if not classified:
                unclassified_records += 1
            match = re.search(r"\b\d{4}-\d{2}-\d{2}[T ][0-9:.]+(?:Z|[+-]\d{2}:\d{2})?", text)
            if match:
                timestamps.append(match.group())
            try:
                item = json.loads(text)
                if isinstance(item, dict):
                    structured_records += 1
                level = str(item.get("level", "")).lower()
                if level in {"debug", "info", "warn", "warning", "error", "fatal", "panic"}:
                    levels[level] += 1
                status = item.get("DownstreamStatus")
                if type(status) is int and 100 <= status <= 599:
                    statuses[str(status)] += 1
            except (ValueError, AttributeError):
                pass
        result.update(status="ok", source_size_bytes=stat.st_size,
                      modified_at=datetime.datetime.fromtimestamp(stat.st_mtime, datetime.timezone.utc).isoformat(),
                      bytes_read=len(data), records_sampled=len(selected),
                      truncated_bytes=start > 0, truncated_lines=len(lines) > MAX_LINES,
                      first_observed_timestamp=timestamps[0] if timestamps else None,
                      last_observed_timestamp=timestamps[-1] if timestamps else None,
                      structured_records=structured_records, non_json_records=len(selected) - structured_records,
                      unclassified_records=unclassified_records,
                      category_counts=dict(counts), level_counts=dict(levels), http_status_counts=dict(statuses))
    except OSError:
        result.update(status="gap", reason="missing or unreadable")
    return result


def application_logs(root=pathlib.Path("/var/log/lumo")):
    output = {"coverage": "Current and .0/.1/.2 plain rotations only; no complete 24h guarantee. Counts overlap and use heuristics, not confirmed incidents. No raw messages, headers, URLs or identities emitted.", "files": []}
    for service in SERVICES:
        for suffix in ("", ".0", ".1", ".2"):
            path = root / (service + ".log" + suffix)
            if suffix and not path.exists():
                continue
            output["files"].append(log_evidence(path))
    return output, any(f["status"] != "ok" for f in output["files"])


def container_evidence(podman):
    def run(*args):
        return subprocess.run([podman, *args], check=True, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, timeout=30).stdout
    ids = run("ps", "-aq").decode().split()
    containers = []
    for cid in ids:
        data = json.loads(run("inspect", cid))[0]
        host = data.get("HostConfig", {})
        containers.append({
            "id": digest(data.get("Id")), "name": identifier(data.get("Name")),
            "image_id": digest(data.get("Image")), "image_digest": digest(data.get("ImageDigest")),
            "privileged": boolean(host.get("Privileged")), "network_mode": identifier(host.get("NetworkMode")),
            "memory_limit": integer(host.get("Memory")), "memory_swap": integer(host.get("MemorySwap")),
            "pids_limit": integer(host.get("PidsLimit")), "readonly_rootfs": boolean(host.get("ReadonlyRootfs")),
        })
    return {"containers": containers, "limits": "Environment, commands, mounts and labels omitted. Image ID/digest does not prove provenance."}, False


def main():
    try:
        mode = sys.argv[1]
        if mode == "proxy":
            output, failed = proxy_evidence()
        elif mode == "logs":
            output, failed = application_logs()
        elif mode == "containers":
            output, failed = container_evidence(sys.argv[2])
        else:
            raise ValueError("unknown mode")
    except Exception:
        output, failed = {"status": "gap", "reason": "collection failed; raw diagnostics suppressed"}, True
    print(json.dumps(output, indent=2))
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
