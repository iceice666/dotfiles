#!/usr/bin/env python3

from __future__ import annotations

import argparse
import html
import json
import os
import re
import subprocess
import sys
import traceback
from datetime import datetime, timedelta
from ipaddress import ip_address, ip_network
from pathlib import Path
from typing import Any, TypedDict

import markdown
import resend
from langchain_ollama import ChatOllama
from langgraph.graph import END, START, StateGraph


LOG_TIMESTAMP_RE = re.compile(r"^(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2})")
FAILED_UNIT_RE = re.compile(r"^[● ]*(?P<unit>[A-Za-z0-9@._-]+\.(?:service|timer|mount|socket|target))\b")
SSH_ACCEPT_RE = re.compile(r"Accepted (?P<method>\S+) for (?P<user>\S+) from (?P<ip>\S+)")
ANSI_ESCAPE_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")
FORGEJO_MIRROR_RE = re.compile(
    r"SyncPushMirror \[mirror: (?P<mirror>\d+)\]\[repo: <Repository \d+:(?P<repo>[^>]+)>\]: unexpected error"
)

SEVERITY_ORDER = {
    "critical": 0,
    "high": 1,
    "medium": 2,
    "low": 3,
    "info": 4,
}

REPORT_SECTIONS = [
    "# Homolab Daily Audit",
    "## Executive Summary",
    "## Findings",
    "## Benign Noise",
    "## Follow-Up Actions",
    "## Evidence Reviewed",
]

EMAIL_FROM = "Homolab Audit <noreply@justaslime.dev>"
EMAIL_TO = "iceice666@outlook.com"
OLLAMA_MODEL = "qwen3.5:9b"
OLLAMA_BASE_URL = "http://192.168.1.127:11434"


class AuditState(TypedDict, total=False):
    state_dir: Path
    run_dir: Path
    bundle_dir: Path
    analysis_dir: Path
    report_file: Path
    deterministic_report_file: Path
    model_report_file: Path
    findings_file: Path
    summary_file: Path
    manifest_file: Path
    email_payload: Path
    email_response: Path
    pipeline_stderr: Path
    model_error_file: Path
    last_success_file: Path
    bundle_mode: str
    send_email: bool
    should_update_last_success: bool
    report_date: str
    audit_subject: str
    host_name: str
    since_iso: str
    until_iso: str
    since_journal: str
    until_journal: str
    manifest: dict[str, Any]
    summary: dict[str, Any]
    findings: list[dict[str, Any]]
    benign: list[dict[str, Any]]
    deterministic_report: str
    final_report: str
    baseline: dict[str, Any]
    rules: dict[str, Any]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the homolab daily audit LangGraph pipeline.")
    parser.add_argument(
        "--state-dir",
        default=os.environ.get("STATE_DIRECTORY", "/var/lib/homolab-daily-audit"),
        help="Directory that stores audit runs and state",
    )
    parser.add_argument(
        "--bundle-dir",
        help="Reuse an existing bundle directory instead of collecting a fresh one",
    )
    parser.add_argument(
        "--run-dir",
        help="Directory where analysis and report artifacts should be written",
    )
    parser.add_argument(
        "--send-email",
        action="store_true",
        help="Send the final report email even when reusing an existing bundle",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parse_timestamp(line: str) -> datetime | None:
    match = LOG_TIMESTAMP_RE.match(line)
    if not match:
        return None

    try:
        return datetime.fromisoformat(match.group("timestamp"))
    except ValueError:
        return None


def isoformat_or_none(value: datetime | None) -> str | None:
    return value.isoformat() if value else None


def parse_metadata(markdown: str) -> dict[str, str]:
    metadata: dict[str, str] = {}
    for line in markdown.splitlines():
        if line.startswith("## "):
            break

        if not line.startswith("- "):
            continue

        key, _, value = line[2:].partition(":")
        metadata[key.strip().lower().replace(" ", "_")] = value.strip()

    return metadata


def first_code_block(markdown: str) -> list[str]:
    lines = markdown.splitlines()
    in_code = False
    block: list[str] = []

    for line in lines:
        if line.startswith("```"):
            if in_code:
                return block
            in_code = True
            continue

        if in_code:
            block.append(line)

    return block


def section_code_blocks(markdown: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    current_heading: str | None = None
    buffer: list[str] = []
    in_code = False

    for line in markdown.splitlines():
        if line.startswith("## "):
            if current_heading is not None:
                sections[current_heading] = buffer[:]
            current_heading = line[3:].strip()
            buffer = []
            in_code = False
            continue

        if line.startswith("```") and current_heading is not None:
            in_code = not in_code
            continue

        if current_heading is not None and in_code:
            buffer.append(line)

    if current_heading is not None:
        sections[current_heading] = buffer[:]

    return sections


def build_manifest(bundle_dir: Path, baseline: dict[str, Any]) -> dict[str, Any]:
    manifest_path = bundle_dir / "manifest.json"
    if manifest_path.exists():
        return load_json(manifest_path)

    overview_path = bundle_dir / "00-overview.md"
    metadata = parse_metadata(read_text(overview_path))
    evidence_files = sorted(path.name for path in bundle_dir.glob("*.md"))

    return {
        "schemaVersion": 1,
        "host": metadata.get("host") or baseline["host"],
        "auditWindow": {
            "since": metadata.get("since"),
            "until": metadata.get("until"),
            "trigger": metadata.get("trigger"),
        },
        "evidenceFiles": evidence_files,
    }


def merge_windows(windows: list[tuple[datetime, datetime]]) -> list[tuple[datetime, datetime]]:
    if not windows:
        return []

    merged: list[tuple[datetime, datetime]] = []
    for start, end in sorted(windows, key=lambda item: item[0]):
        if not merged or start > merged[-1][1]:
            merged.append((start, end))
            continue

        merged[-1] = (merged[-1][0], max(merged[-1][1], end))

    return merged


def line_in_windows(line: str, windows: list[tuple[datetime, datetime]]) -> bool:
    timestamp = parse_timestamp(line)
    if timestamp is None:
        return False

    return any(start <= timestamp <= end for start, end in windows)


def make_evidence(file_name: str, line: str) -> dict[str, Any]:
    return {
        "file": file_name,
        "timestamp": isoformat_or_none(parse_timestamp(line)),
        "message": line,
    }


def make_item(
    *,
    item_id: str,
    classification: str,
    category: str,
    severity: str,
    title: str,
    summary: str,
    evidence: list[dict[str, Any]],
    follow_up: str,
) -> dict[str, Any]:
    sorted_evidence = sorted(
        evidence,
        key=lambda item: (
            item.get("timestamp") is None,
            item.get("timestamp") or "",
            item["message"],
        ),
    )
    timestamps = [
        evidence_item["timestamp"]
        for evidence_item in sorted_evidence
        if evidence_item.get("timestamp")
    ]

    return {
        "id": item_id,
        "classification": classification,
        "category": category,
        "severity": severity,
        "title": title,
        "summary": summary,
        "count": len(sorted_evidence),
        "firstSeen": timestamps[0] if timestamps else None,
        "lastSeen": timestamps[-1] if timestamps else None,
        "evidence": sorted_evidence,
        "followUp": follow_up,
    }


def sort_items(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    def sort_key(item: dict[str, Any]) -> tuple[int, str, str]:
        return (
            SEVERITY_ORDER.get(item["severity"], 99),
            item.get("firstSeen") or "",
            item["title"],
        )

    return sorted(items, key=sort_key)


def detect_maintenance(
    overview_lines: list[str],
    rules: dict[str, Any],
) -> tuple[list[tuple[datetime, datetime]], list[dict[str, Any]]]:
    windows: list[tuple[datetime, datetime]] = []
    marker_evidence: list[dict[str, Any]] = []

    for line in overview_lines:
        for marker in rules["maintenanceMarkers"]:
            if marker["pattern"] not in line:
                continue

            timestamp = parse_timestamp(line)
            if timestamp is None:
                continue

            windows.append(
                (
                    timestamp - timedelta(minutes=marker["windowBeforeMinutes"]),
                    timestamp + timedelta(minutes=marker["windowAfterMinutes"]),
                )
            )
            marker_evidence.append(make_evidence("00-overview.md", line))

    return merge_windows(windows), marker_evidence


def detect_ssh(
    ssh_lines: list[str],
    sudo_lines: list[str],
    baseline: dict[str, Any],
    rules: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    findings: list[dict[str, Any]] = []
    benign: list[dict[str, Any]] = []
    ssh_config = baseline["ssh"]
    trusted_networks = [ip_network(network) for network in ssh_config["trustedSourceCidrs"]]
    expected_users = set(ssh_config["expectedUsers"])

    expected_logins: list[dict[str, Any]] = []
    unexpected_logins: list[dict[str, Any]] = []
    failed_attempts: list[dict[str, Any]] = []
    sudo_denials: list[dict[str, Any]] = []

    for line in ssh_lines:
        match = SSH_ACCEPT_RE.search(line)
        if match:
            user = match.group("user")
            method = match.group("method")
            source_ip = match.group("ip")
            evidence = make_evidence("20-authentication.md", line)

            if user == "root" and not ssh_config["rootLoginAllowed"]:
                findings.append(
                    make_item(
                        item_id="security-root-ssh-success",
                        classification="finding",
                        category="security",
                        severity="critical",
                        title="Root SSH login succeeded",
                        summary="A successful SSH login for `root` was recorded even though root login should be disabled.",
                        evidence=[evidence],
                        follow_up="Disable root SSH access immediately and review the source IP and session activity.",
                    )
                )
                continue

            if method == "password" and not ssh_config["passwordAuthenticationAllowed"]:
                findings.append(
                    make_item(
                        item_id="security-password-ssh-success",
                        classification="finding",
                        category="security",
                        severity="critical",
                        title="Password-based SSH authentication succeeded",
                        summary="A successful SSH password login was recorded even though password authentication should be disabled.",
                        evidence=[evidence],
                        follow_up="Inspect `sshd_config`, rotate credentials, and review the full session immediately.",
                    )
                )
                continue

            is_expected_user = user in expected_users
            is_trusted_source = False
            try:
                parsed_ip = ip_address(source_ip)
                is_trusted_source = any(parsed_ip in network for network in trusted_networks)
            except ValueError:
                is_trusted_source = False

            if is_expected_user and is_trusted_source:
                expected_logins.append(evidence)
            else:
                unexpected_logins.append(evidence)

            continue

        if any(pattern in line for pattern in rules["sshFailurePatterns"]):
            failed_attempts.append(make_evidence("20-authentication.md", line))

    for line in sudo_lines:
        if any(pattern in line for pattern in rules["sudoDeniedPatterns"]):
            sudo_denials.append(make_evidence("20-authentication.md", line))

    if unexpected_logins:
        findings.append(
            make_item(
                item_id="security-unexpected-ssh-success",
                classification="finding",
                category="security",
                severity="medium",
                title="Unexpected SSH login succeeded",
                summary="At least one successful SSH login did not match the expected user or trusted source ranges.",
                evidence=unexpected_logins,
                follow_up="Confirm whether the login source and account were expected for this audit window.",
            )
        )

    if len(failed_attempts) >= rules["thresholds"]["sshFailureBurst"]:
        findings.append(
            make_item(
                item_id="security-ssh-failure-burst",
                classification="finding",
                category="security",
                severity="medium",
                title="Burst of SSH authentication failures detected",
                summary=f"Detected {len(failed_attempts)} SSH failure lines across the audit window.",
                evidence=failed_attempts,
                follow_up="Check whether the source IPs warrant a temporary block or additional hardening.",
            )
        )

    if sudo_denials:
        findings.append(
            make_item(
                item_id="security-sudo-or-polkit-denials",
                classification="finding",
                category="security",
                severity="medium",
                title="Privilege escalation denials were recorded",
                summary="`sudo` or `polkit` denial messages were recorded during the audit window.",
                evidence=sudo_denials,
                follow_up="Review whether the denied privilege escalation attempts were expected operator actions.",
            )
        )

    if expected_logins:
        sources = sorted(
            {
                SSH_ACCEPT_RE.search(item["message"]).group("ip")
                for item in expected_logins
                if SSH_ACCEPT_RE.search(item["message"])
            }
        )
        benign.append(
            make_item(
                item_id="benign-expected-ssh-logins",
                classification="benign-noise",
                category="access",
                severity="info",
                title="Expected SSH logins for the admin account",
                summary=(
                    f"Recorded {len(expected_logins)} successful public-key SSH login(s) for `iceice666` "
                    f"from trusted source range(s): {', '.join(f'`{source}`' for source in sources)}."
                ),
                evidence=expected_logins,
                follow_up="None",
            )
        )

    return findings, benign


def detect_rebuild_and_failed_units(
    overview_lines: list[str],
    failed_units: list[str],
    baseline: dict[str, Any],
) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    rebuild_evidence: list[dict[str, Any]] = []

    for line in overview_lines:
        if "nixos-rebuild-switch-to-configuration.service: Failed with result" in line:
            rebuild_evidence.append(make_evidence("00-overview.md", line))
        elif "home-manager-iceice666.service: Failed with result" in line:
            rebuild_evidence.append(make_evidence("00-overview.md", line))
        elif "sops-nix.service: Failed with result" in line:
            rebuild_evidence.append(make_evidence("00-overview.md", line))

    if rebuild_evidence:
        persistent_units = ", ".join(f"`{unit}`" for unit in failed_units) if failed_units else "none"
        findings.append(
            make_item(
                item_id="operations-rebuild-or-activation-failure",
                classification="finding",
                category="operations",
                severity="medium",
                title="Recent rebuild or activation failed",
                summary=(
                    "The audit window captured a failed NixOS rebuild or activation sequence. "
                    f"The window ended with these failed units still present: {persistent_units}."
                ),
                evidence=rebuild_evidence,
                follow_up="Inspect `nixos-rebuild-switch-to-configuration.service`, `home-manager-iceice666.service`, and `sops-nix.service` logs before the next switch.",
            )
        )
        return findings

    if not failed_units:
        return findings

    severity = "medium"
    if any(unit in baseline["internetFacingServices"] for unit in failed_units):
        severity = "high"

    findings.append(
        make_item(
            item_id="operations-persistent-failed-units",
            classification="finding",
            category="operations",
            severity=severity,
            title="Systemd units remained failed at the end of the audit window",
            summary="The audit window ended with one or more failed units that did not recover cleanly.",
            evidence=[
                {
                    "file": "00-overview.md",
                    "timestamp": None,
                    "message": unit,
                }
                for unit in failed_units
            ],
            follow_up="Inspect `systemctl status` for the failed units and clear the failed state only after the root cause is fixed.",
        )
    )

    return findings


def detect_system_stability(
    priority_lines: list[str],
    kernel_lines: list[str],
    rules: dict[str, Any],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    findings: list[dict[str, Any]] = []
    benign: list[dict[str, Any]] = []

    benign_kernel_matches: dict[str, dict[str, Any]] = {}
    remaining_kernel_lines: list[str] = []
    for line in kernel_lines:
        matched_benign = False
        for pattern in rules["benignKernelPatterns"]:
            if re.search(pattern["pattern"], line):
                match = benign_kernel_matches.setdefault(
                    pattern["id"],
                    {
                        "pattern": pattern,
                        "evidence": [],
                    },
                )
                match["evidence"].append(make_evidence("50-kernel.md", line))
                matched_benign = True
                break

        if not matched_benign:
            remaining_kernel_lines.append(line)

    for match in benign_kernel_matches.values():
        pattern = match["pattern"]
        benign.append(
            make_item(
                item_id=f"benign-kernel-{pattern['id']}",
                classification="benign-noise",
                category="kernel",
                severity="info",
                title=pattern["title"],
                summary=pattern["title"],
                evidence=match["evidence"],
                follow_up=pattern["followUp"],
            )
        )

    for pattern in rules["systemStabilityPatterns"]:
        evidence: list[dict[str, Any]] = []
        for line in priority_lines:
            if re.search(pattern["pattern"], line, re.IGNORECASE):
                evidence.append(make_evidence("10-priority-journal.md", line))
        for line in remaining_kernel_lines:
            if re.search(pattern["pattern"], line, re.IGNORECASE):
                evidence.append(make_evidence("50-kernel.md", line))

        if not evidence:
            continue

        findings.append(
            make_item(
                item_id=f"operations-{pattern['id']}",
                classification="finding",
                category=pattern["category"],
                severity=pattern["severity"],
                title=pattern["title"],
                summary=pattern["title"],
                evidence=evidence,
                follow_up=pattern["followUp"],
            )
        )

    return findings, benign


def detect_cloudflared(
    lines: list[str],
    rules: dict[str, Any],
    maintenance_windows: list[tuple[datetime, datetime]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    findings: list[dict[str, Any]] = []
    benign: list[dict[str, Any]] = []
    active_lines = [line for line in lines if not line_in_windows(line, maintenance_windows)]
    error_patterns = rules["cloudflared"]["errorPatterns"]
    recovery_patterns = rules["cloudflared"]["recoveryPatterns"]
    recovery_grace = timedelta(minutes=rules["cloudflared"]["recoveryGraceMinutes"])

    error_evidence = [
        make_evidence("30-edge-services.md", line)
        for line in active_lines
        if any(pattern in line for pattern in error_patterns)
    ]
    recovery_evidence = [
        make_evidence("30-edge-services.md", line)
        for line in active_lines
        if any(pattern in line for pattern in recovery_patterns)
    ]

    if not error_evidence:
        return findings, benign

    last_error_time = parse_timestamp(error_evidence[-1]["message"])
    recovered = False
    if last_error_time is not None:
        for recovery in recovery_evidence:
            recovery_time = parse_timestamp(recovery["message"])
            if recovery_time is None:
                continue
            if last_error_time <= recovery_time <= last_error_time + recovery_grace:
                recovered = True
                break

    if recovered:
        benign.append(
            make_item(
                item_id="benign-cloudflared-transient-reconnect",
                classification="benign-noise",
                category="network",
                severity="info",
                title="Cloudflare tunnel recovered after transient connection churn",
                summary=(
                    f"Cloudflared logged {len(error_evidence)} transient QUIC or DNS errors outside maintenance windows, "
                    "then re-registered tunnel connections within the configured recovery window."
                ),
                evidence=error_evidence + recovery_evidence,
                follow_up="None",
            )
        )
    else:
        findings.append(
            make_item(
                item_id="operations-cloudflared-unrecovered-errors",
                classification="finding",
                category="operations",
                severity="high",
                title="Cloudflare tunnel errors did not show a clean recovery",
                summary="Cloudflared logged repeated transport or protocol errors without a matching recovery event outside the maintenance windows.",
                evidence=error_evidence,
                follow_up="Inspect `cloudflared-tunnel.service` and upstream DNS reachability before the next audit run.",
            )
        )

    return findings, benign


def detect_forgejo(
    lines: list[str],
    rules: dict[str, Any],
    maintenance_windows: list[tuple[datetime, datetime]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    findings: list[dict[str, Any]] = []
    benign: list[dict[str, Any]] = []
    active_lines = [line for line in lines if not line_in_windows(line, maintenance_windows)]

    mirror_errors: list[dict[str, Any]] = []
    mirror_repos: set[str] = set()
    crawler_noise: list[dict[str, Any]] = []

    for line in active_lines:
        match = FORGEJO_MIRROR_RE.search(line)
        if match:
            mirror_errors.append(make_evidence("40-application-services.md", line))
            mirror_repos.add(match.group("repo"))
            continue

        if "Privatekey: chacha20poly1305: message authentication failed" in line:
            mirror_errors.append(make_evidence("40-application-services.md", line))
            continue

        if "router: completed GET" in line and ("303 See Other" in line or "/user/login" in line):
            crawler_noise.append(make_evidence("40-application-services.md", line))

    if len(mirror_errors) >= rules["thresholds"]["forgejoMirrorFailure"]:
        repo_list = ", ".join(f"`{repo}`" for repo in sorted(mirror_repos)) or "the configured mirrors"
        findings.append(
            make_item(
                item_id="operations-forgejo-mirror-failures",
                classification="finding",
                category="operations",
                severity="medium",
                title="Forgejo mirror pushes failed repeatedly",
                summary=f"Forgejo logged repeated mirror push failures for {repo_list} during the audit window.",
                evidence=mirror_errors,
                follow_up="Verify the Forgejo mirror SSH credentials or deploy keys, then rerun the affected mirror syncs.",
            )
        )

    if len(crawler_noise) >= rules["thresholds"]["forgejoCrawlerNoise"]:
        benign.append(
            make_item(
                item_id="benign-forgejo-crawler-noise",
                classification="benign-noise",
                category="web",
                severity="info",
                title="Forgejo saw routine unauthenticated browse traffic",
                summary=(
                    f"Forgejo logged {len(crawler_noise)} unauthenticated browse or login redirect lines, "
                    "which matched ordinary public crawler or probe traffic rather than a successful access event."
                ),
                evidence=crawler_noise[:20],
                follow_up="None",
            )
        )

    return findings, benign


def detect_maintenance_noise(
    overview_lines: list[str],
    maintenance_windows: list[tuple[datetime, datetime]],
    marker_evidence: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    if not maintenance_windows:
        return []

    impacted_units: set[str] = set()
    for line in overview_lines:
        if not line_in_windows(line, maintenance_windows):
            continue
        unit_match = re.search(r"([A-Za-z0-9@._-]+\.service)", line)
        if unit_match:
            impacted_units.add(unit_match.group(1))

    window_start = min(start for start, _ in maintenance_windows).isoformat()
    window_end = max(end for _, end in maintenance_windows).isoformat()
    impacted_summary = ", ".join(f"`{unit}`" for unit in sorted(impacted_units)) or "service restarts"

    return [
        make_item(
            item_id="benign-maintenance-window",
            classification="benign-noise",
            category="maintenance",
            severity="info",
            title="Configuration switch maintenance window detected",
            summary=(
                f"Detected a configuration switch window from `{window_start}` to `{window_end}`. "
                f"Stop/start churn for {impacted_summary} was treated as expected maintenance noise unless a unit remained failed afterward."
            ),
            evidence=marker_evidence,
            follow_up="None",
        )
    ]


def parse_failed_units(overview_markdown: str) -> list[str]:
    sections = section_code_blocks(overview_markdown)
    failed_units: list[str] = []

    for line in sections.get("Failed Units", []):
        match = FAILED_UNIT_RE.match(line)
        if match:
            failed_units.append(match.group("unit"))

    return failed_units


def build_summary(
    manifest: dict[str, Any],
    findings: list[dict[str, Any]],
    benign: list[dict[str, Any]],
) -> dict[str, Any]:
    actionable = [item for item in findings if item["classification"] == "finding"]
    security_findings = [item for item in actionable if item["category"] == "security"]
    operations_findings = [item for item in actionable if item["category"] != "security"]
    follow_up_actions = [item["followUp"] for item in actionable if item["followUp"] != "None"]

    if not actionable:
        executive_summary = "No actionable security or service-health regressions were detected in the audit window."
        status = "clean"
    elif security_findings and operations_findings:
        executive_summary = (
            f"Detected {len(security_findings)} security finding(s) and {len(operations_findings)} operational finding(s) "
            "that require follow-up."
        )
        status = "action-required"
    elif security_findings:
        executive_summary = f"Detected {len(security_findings)} security finding(s) that require follow-up."
        status = "action-required"
    else:
        executive_summary = "No direct compromise indicators were detected, but operational issues require follow-up."
        status = "action-required"

    return {
        "schemaVersion": 1,
        "host": manifest["host"],
        "auditWindow": manifest["auditWindow"],
        "status": status,
        "executiveSummary": executive_summary,
        "counts": {
            "findings": len(actionable),
            "securityFindings": len(security_findings),
            "operationalFindings": len(operations_findings),
            "benignNoise": len(benign),
        },
        "highlights": [item["title"] for item in actionable[:5]],
        "followUpActions": list(dict.fromkeys(follow_up_actions)),
        "evidenceFiles": manifest["evidenceFiles"],
    }


def render_report(
    manifest: dict[str, Any],
    summary: dict[str, Any],
    findings: list[dict[str, Any]],
    benign: list[dict[str, Any]],
) -> str:
    actionable = [item for item in findings if item["classification"] == "finding"]
    follow_up_actions = list(dict.fromkeys(summary["followUpActions"]))
    lines: list[str] = [
        "# Homolab Daily Audit",
        "",
        "## Executive Summary",
        "",
        f"{summary['executiveSummary']} This report was generated from deterministic pipeline outputs.",
        "",
        "## Findings",
        "",
    ]

    if actionable:
        for item in actionable:
            lines.append(f"- `{item['severity']}` `{item['category']}` {item['title']}: {item['summary']}")
            if item["evidence"]:
                lines.append(f"  Evidence: `{item['evidence'][0]['message']}`")
            if item["followUp"] != "None":
                lines.append(f"  Follow-up: {item['followUp']}")
    else:
        lines.append("None noted.")

    lines.extend(["", "## Benign Noise", ""])
    if benign:
        for item in benign:
            lines.append(f"- {item['title']}: {item['summary']}")
    else:
        lines.append("None noted.")

    lines.extend(["", "## Follow-Up Actions", ""])
    if follow_up_actions:
        for action in follow_up_actions:
            lines.append(f"- {action}")
    else:
        lines.append("None.")

    lines.extend(["", "## Evidence Reviewed", ""])
    for evidence_file in manifest["evidenceFiles"]:
        lines.append(f"- `{evidence_file}`")

    return "\n".join(lines) + "\n"


def shell_output(*args: str) -> list[str]:
    completed = subprocess.run(
        list(args),
        check=False,
        capture_output=True,
        text=True,
    )
    output = completed.stdout
    if completed.stderr:
        separator = "" if not output or output.endswith("\n") else "\n"
        output = f"{output}{separator}{completed.stderr}"
    return [ANSI_ESCAPE_RE.sub("", line) for line in output.splitlines()]


def write_code_block_file(path: Path, title: str, lines: list[str]) -> None:
    content = [f"# {title}", "", "```text", *lines, "```", ""]
    path.write_text("\n".join(content), encoding="utf-8")


def render_section_block(title: str, lines: list[str]) -> list[str]:
    return [f"## {title}", "", "```text", *lines, "```", ""]


def resolve_host_name() -> str:
    hostnamectl_lines = shell_output("hostnamectl", "--static")
    if hostnamectl_lines:
        host_name = hostnamectl_lines[0].strip()
        if host_name:
            return host_name

    hostname_path = Path("/etc/hostname")
    if hostname_path.exists():
        host_name = hostname_path.read_text(encoding="utf-8").strip()
        if host_name:
            return host_name

    return "unknown"


def parse_last_success(path: Path, now: datetime) -> datetime | None:
    if not path.exists() or not path.read_text(encoding="utf-8").strip():
        return None

    raw_value = path.read_text(encoding="utf-8").strip()
    try:
        parsed = datetime.fromisoformat(raw_value)
    except ValueError:
        return None

    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=now.tzinfo)
    return parsed


def prepare_run_context(args: argparse.Namespace) -> AuditState:
    script_dir = Path(__file__).resolve().parent
    state_dir = Path(args.state_dir).resolve()
    now = datetime.now().astimezone()
    run_stamp = now.isoformat(timespec="seconds").replace(":", "-")
    bundle_dir_arg = Path(args.bundle_dir).resolve() if args.bundle_dir else None
    run_dir_arg = Path(args.run_dir).resolve() if args.run_dir else None

    if bundle_dir_arg is not None and not bundle_dir_arg.is_dir():
        raise SystemExit(f"Bundle directory not found: {bundle_dir_arg}")

    if bundle_dir_arg is None:
        run_dir = run_dir_arg or state_dir / "runs" / run_stamp
        bundle_dir = run_dir / "bundle"
        bundle_mode = "collect"
        send_email = True
        should_update_last_success = True
    else:
        if run_dir_arg is not None:
            run_dir = run_dir_arg
        elif bundle_dir_arg.parent.name == "bundle":
            run_dir = bundle_dir_arg.parent
        else:
            run_dir = state_dir / "replays" / run_stamp
        bundle_dir = bundle_dir_arg
        bundle_mode = "reuse"
        send_email = args.send_email
        should_update_last_success = False

    analysis_dir = run_dir / "analysis"
    report_file = run_dir / "report.md"
    state: AuditState = {
        "state_dir": state_dir,
        "run_dir": run_dir,
        "bundle_dir": bundle_dir,
        "analysis_dir": analysis_dir,
        "report_file": report_file,
        "deterministic_report_file": analysis_dir / "report.deterministic.md",
        "model_report_file": run_dir / "report.model.md",
        "findings_file": analysis_dir / "findings.json",
        "summary_file": analysis_dir / "summary.json",
        "manifest_file": bundle_dir / "manifest.json",
        "email_payload": run_dir / "email.json",
        "email_response": run_dir / "email-response.json",
        "pipeline_stderr": run_dir / "pipeline.stderr",
        "model_error_file": run_dir / "model-error.txt",
        "last_success_file": state_dir / "last-success",
        "bundle_mode": bundle_mode,
        "send_email": send_email,
        "should_update_last_success": should_update_last_success,
        "report_date": now.date().isoformat(),
        "audit_subject": f"[homolab] Daily audit report for {now.date().isoformat()}",
        "baseline": load_json(script_dir / "baseline.json"),
        "rules": load_json(script_dir / "rules.json"),
    }

    run_dir.mkdir(parents=True, exist_ok=True)
    analysis_dir.mkdir(parents=True, exist_ok=True)
    if bundle_mode == "collect":
        bundle_dir.mkdir(parents=True, exist_ok=True)

    latest_link = state_dir / "latest"
    latest_link.parent.mkdir(parents=True, exist_ok=True)
    latest_link.unlink(missing_ok=True)
    latest_link.symlink_to(run_dir, target_is_directory=True)

    if bundle_mode == "collect":
        host_name = resolve_host_name()
        default_since = now - timedelta(hours=48)
        last_success = parse_last_success(state["last_success_file"], now)
        since = last_success if last_success and last_success > default_since else default_since
        state.update(
            {
                "host_name": host_name,
                "since_iso": since.isoformat(timespec="seconds"),
                "until_iso": now.isoformat(timespec="seconds"),
                "since_journal": since.strftime("%Y-%m-%d %H:%M:%S"),
                "until_journal": now.strftime("%Y-%m-%d %H:%M:%S"),
            }
        )

    return state


def route_bundle_source(state: AuditState) -> str:
    return state["bundle_mode"]


def route_email_delivery(state: AuditState) -> str:
    return "send-email" if state["send_email"] else "persist-success"


def passthrough(_: AuditState) -> dict[str, Any]:
    return {}


def collect_overview(state: AuditState) -> dict[str, Any]:
    failed_units = shell_output("systemctl", "list-units", "--state=failed", "--all", "--no-pager", "--no-legend")
    recent_restart_lines = shell_output(
        "journalctl",
        "--since",
        state["since_journal"],
        "--until",
        state["until_journal"],
        "--grep",
        "Failed with result|Main process exited|Scheduled restart job|Starting |Started |Stopping |Stopped ",
        "-o",
        "short-iso",
        "--no-pager",
        "-n",
        "200",
    )
    lines = [
        "# Homolab Audit Window",
        "",
        f"- Host: {state['host_name']}",
        f"- Since: {state['since_iso']}",
        f"- Until: {state['until_iso']}",
        "- Trigger: systemd timer",
        "",
        "## Service Scope",
        "",
        "- Public edge: `sshd.service`, `traefik.service`, `cloudflared-tunnel.service`",
        "- Auth: `authelia-main.service`",
        "- Apps: `forgejo.service`, `woodpecker-server.service`, `woodpecker-agent-docker.service`, `dynacat.service`",
        "- Platform: `docker.service`, `postgresql.service`, `rustfs.service`, `dnsmasq.service`, `cloudflare-ips-refresh.service`, `cloudflare-dyndns.service`",
        "",
        *render_section_block("Failed Units", failed_units),
        *render_section_block("Recent Restarts And Failures", recent_restart_lines),
    ]
    (state["bundle_dir"] / "00-overview.md").write_text("\n".join(lines), encoding="utf-8")
    return {}


def collect_priority_journal(state: AuditState) -> dict[str, Any]:
    lines = shell_output(
        "journalctl",
        "--since",
        state["since_journal"],
        "--until",
        state["until_journal"],
        "-o",
        "short-iso",
        "--no-pager",
        "-p",
        "warning..alert",
        "-n",
        "400",
    )
    write_code_block_file(state["bundle_dir"] / "10-priority-journal.md", "Priority Journal", lines)
    return {}


def collect_authentication(state: AuditState) -> dict[str, Any]:
    sshd_lines = shell_output(
        "journalctl",
        "--since",
        state["since_journal"],
        "--until",
        state["until_journal"],
        "-u",
        "sshd.service",
        "-o",
        "short-iso",
        "--no-pager",
        "-n",
        "300",
    )
    authelia_lines = shell_output(
        "journalctl",
        "--since",
        state["since_journal"],
        "--until",
        state["until_journal"],
        "-u",
        "authelia-main.service",
        "-o",
        "short-iso",
        "--no-pager",
        "-n",
        "300",
    )
    sudo_lines = shell_output(
        "journalctl",
        "--since",
        state["since_journal"],
        "--until",
        state["until_journal"],
        "-u",
        "polkit.service",
        "-t",
        "sudo",
        "--grep",
        "authentication failure|not allowed|denied|COMMAND=|session opened|session closed",
        "-o",
        "short-iso",
        "--no-pager",
        "-n",
        "200",
    )
    lines = [
        "# Authentication And Access",
        "",
        *render_section_block("sshd.service", sshd_lines),
        *render_section_block("authelia-main.service", authelia_lines),
        *render_section_block("sudo And polkit", sudo_lines),
    ]
    (state["bundle_dir"] / "20-authentication.md").write_text("\n".join(lines), encoding="utf-8")
    return {}


def collect_edge_services(state: AuditState) -> dict[str, Any]:
    traefik_lines = shell_output(
        "journalctl",
        "--since",
        state["since_journal"],
        "--until",
        state["until_journal"],
        "-u",
        "traefik.service",
        "-o",
        "short-iso",
        "--no-pager",
        "-n",
        "250",
    )
    cloudflared_lines = shell_output(
        "journalctl",
        "--since",
        state["since_journal"],
        "--until",
        state["until_journal"],
        "-u",
        "cloudflared-tunnel.service",
        "-o",
        "short-iso",
        "--no-pager",
        "-n",
        "250",
    )
    dnsmasq_lines = shell_output(
        "journalctl",
        "--since",
        state["since_journal"],
        "--until",
        state["until_journal"],
        "-u",
        "dnsmasq.service",
        "-o",
        "short-iso",
        "--no-pager",
        "-n",
        "250",
    )
    lines = [
        "# Edge Services",
        "",
        *render_section_block("traefik.service", traefik_lines),
        *render_section_block("cloudflared-tunnel.service", cloudflared_lines),
        *render_section_block("dnsmasq.service", dnsmasq_lines),
    ]
    (state["bundle_dir"] / "30-edge-services.md").write_text("\n".join(lines), encoding="utf-8")
    return {}


def collect_application_services(state: AuditState) -> dict[str, Any]:
    service_names = [
        "forgejo.service",
        "woodpecker-server.service",
        "woodpecker-agent-docker.service",
        "docker.service",
        "postgresql.service",
        "rustfs.service",
        "dynacat.service",
    ]
    lines: list[str] = ["# Application Services", ""]
    for service_name in service_names:
        service_lines = shell_output(
            "journalctl",
            "--since",
            state["since_journal"],
            "--until",
            state["until_journal"],
            "-u",
            service_name,
            "-o",
            "short-iso",
            "--no-pager",
            "-n",
            "250",
        )
        lines.extend(render_section_block(service_name, service_lines))

    (state["bundle_dir"] / "40-application-services.md").write_text("\n".join(lines), encoding="utf-8")
    return {}


def collect_kernel(state: AuditState) -> dict[str, Any]:
    lines = shell_output(
        "journalctl",
        "--since",
        state["since_journal"],
        "--until",
        state["until_journal"],
        "-k",
        "-o",
        "short-iso",
        "--no-pager",
        "-p",
        "warning..alert",
        "-n",
        "250",
    )
    write_code_block_file(state["bundle_dir"] / "50-kernel.md", "Kernel Messages", lines)
    return {}


def write_manifest(state: AuditState) -> dict[str, Any]:
    manifest = {
        "schemaVersion": 1,
        "host": state["host_name"],
        "auditWindow": {
            "since": state["since_iso"],
            "until": state["until_iso"],
            "trigger": "systemd timer",
        },
        "evidenceFiles": [
            "00-overview.md",
            "10-priority-journal.md",
            "20-authentication.md",
            "30-edge-services.md",
            "40-application-services.md",
            "50-kernel.md",
        ],
    }
    state["manifest_file"].write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return {"manifest": manifest}


def analyze_bundle(state: AuditState) -> dict[str, Any]:
    overview_markdown = read_text(state["bundle_dir"] / "00-overview.md")
    overview_sections = section_code_blocks(overview_markdown)
    auth_sections = section_code_blocks(read_text(state["bundle_dir"] / "20-authentication.md"))
    edge_sections = section_code_blocks(read_text(state["bundle_dir"] / "30-edge-services.md"))
    app_sections = section_code_blocks(read_text(state["bundle_dir"] / "40-application-services.md"))
    priority_lines = first_code_block(read_text(state["bundle_dir"] / "10-priority-journal.md"))
    kernel_lines = first_code_block(read_text(state["bundle_dir"] / "50-kernel.md"))

    overview_lines = overview_sections.get("Recent Restarts And Failures", [])
    failed_units = parse_failed_units(overview_markdown)
    maintenance_windows, marker_evidence = detect_maintenance(overview_lines, state["rules"])

    findings: list[dict[str, Any]] = []
    benign: list[dict[str, Any]] = []

    ssh_findings, ssh_benign = detect_ssh(
        auth_sections.get("sshd.service", []),
        auth_sections.get("sudo And polkit", []),
        state["baseline"],
        state["rules"],
    )
    findings.extend(ssh_findings)
    benign.extend(ssh_benign)

    findings.extend(detect_rebuild_and_failed_units(overview_lines, failed_units, state["baseline"]))

    stability_findings, stability_benign = detect_system_stability(priority_lines, kernel_lines, state["rules"])
    findings.extend(stability_findings)
    benign.extend(stability_benign)

    cloudflared_findings, cloudflared_benign = detect_cloudflared(
        edge_sections.get("cloudflared-tunnel.service", []),
        state["rules"],
        maintenance_windows,
    )
    findings.extend(cloudflared_findings)
    benign.extend(cloudflared_benign)

    forgejo_findings, forgejo_benign = detect_forgejo(
        app_sections.get("forgejo.service", []),
        state["rules"],
        maintenance_windows,
    )
    findings.extend(forgejo_findings)
    benign.extend(forgejo_benign)

    benign.extend(detect_maintenance_noise(overview_lines, maintenance_windows, marker_evidence))

    findings = sort_items(findings)
    benign = sort_items(benign)

    manifest = state.get("manifest") or build_manifest(state["bundle_dir"], state["baseline"])
    summary = build_summary(manifest, findings, benign)
    deterministic_report = render_report(manifest, summary, findings, benign)

    state["findings_file"].write_text(json.dumps(findings + benign, indent=2) + "\n", encoding="utf-8")
    state["summary_file"].write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    state["deterministic_report_file"].write_text(deterministic_report, encoding="utf-8")

    return {
        "manifest": manifest,
        "summary": summary,
        "findings": findings,
        "benign": benign,
        "deterministic_report": deterministic_report,
        "host_name": manifest["host"],
        "since_iso": manifest["auditWindow"].get("since") or state.get("since_iso", "unknown"),
        "until_iso": manifest["auditWindow"].get("until") or state.get("until_iso", "unknown"),
    }


def model_prompt(state: AuditState) -> str:
    structured_findings = state["findings"] + state["benign"]
    return f"""Generate the final homolab daily audit email.

Treat the deterministic outputs below as authoritative. Do not inspect raw logs, do not invent new findings, and do not change follow-up actions unless the deterministic output is clearly malformed.

Output Markdown with exactly these sections and in this exact order:
# Homolab Daily Audit
## Executive Summary
## Findings
## Benign Noise
## Follow-Up Actions
## Evidence Reviewed

Requirements:
- Keep the findings in severity order.
- Keep the benign noise separated from actionable issues.
- Say explicitly that the report is based on deterministic pipeline outputs.
- If there are no notable problems, say so explicitly in Executive Summary and Findings.
- Preserve the deterministic categories and follow-up actions.

summary.json:
```json
{json.dumps(state['summary'], indent=2)}
```

findings.json:
```json
{json.dumps(structured_findings, indent=2)}
```

report.deterministic.md:
```markdown
{state['deterministic_report']}
```
"""


def coerce_message_text(content: Any) -> str:
    if isinstance(content, str):
        return content

    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, dict) and isinstance(item.get("text"), str):
                parts.append(item["text"])
            else:
                parts.append(str(item))
        return "\n".join(parts)

    return str(content)


def strip_fenced_block(text: str) -> str:
    stripped = text.strip()
    if stripped.startswith("```") and stripped.endswith("```"):
        lines = stripped.splitlines()
        if len(lines) >= 2:
            return "\n".join(lines[1:-1]).strip()
    return stripped


def has_required_sections(text: str) -> bool:
    stripped = text.strip()
    if not stripped.startswith(REPORT_SECTIONS[0]):
        return False

    cursor = 0
    for section in REPORT_SECTIONS:
        position = stripped.find(section, cursor)
        if position == -1:
            return False
        cursor = position + len(section)

    return "deterministic pipeline outputs" in stripped.lower()


def generate_final_report(state: AuditState) -> dict[str, Any]:
    final_report = state["deterministic_report"]

    try:
        llm = ChatOllama(
            model=os.environ.get("DAILY_AUDIT_OLLAMA_MODEL", OLLAMA_MODEL),
            base_url=os.environ.get("DAILY_AUDIT_OLLAMA_BASE_URL", OLLAMA_BASE_URL),
            temperature=0,
        )
        response = llm.invoke(model_prompt(state))
        model_output = strip_fenced_block(coerce_message_text(response.content))
        if has_required_sections(model_output):
            final_report = model_output.rstrip() + "\n"
            state["model_report_file"].write_text(final_report, encoding="utf-8")
        else:
            state["model_error_file"].write_text(
                "Model output was missing required report sections.\n\n"
                f"{model_output.rstrip()}\n",
                encoding="utf-8",
            )
    except Exception:
        state["model_error_file"].write_text(traceback.format_exc(), encoding="utf-8")

    state["report_file"].write_text(final_report, encoding="utf-8")
    return {"final_report": final_report}


def send_email(state: AuditState) -> dict[str, Any]:
    api_key_path = Path(os.environ["DAILY_AUDIT_RESEND_API_KEY_FILE"])
    api_key = api_key_path.read_text(encoding="utf-8").strip()
    resend.api_key = api_key

    payload = {
        "from": os.environ.get("DAILY_AUDIT_EMAIL_FROM", EMAIL_FROM),
        "to": [os.environ.get("DAILY_AUDIT_EMAIL_TO", EMAIL_TO)],
        "subject": state["audit_subject"],
        "html": render_report_html(state["final_report"], state["audit_subject"]),
        "text": state["final_report"],
    }
    payload_json = json.dumps(payload, indent=2) + "\n"
    state["email_payload"].write_text(payload_json, encoding="utf-8")

    try:
        response = resend.Emails.send(payload)
    except resend.exceptions.ResendError as error:
        raise RuntimeError(
            f"Resend API request failed with HTTP {error.code}: {error.message}"
        ) from error

    formatted_response = format_email_response(response)

    state["email_response"].write_text(formatted_response, encoding="utf-8")
    return {}


def render_report_html(report_markdown: str, subject: str) -> str:
    report_body = markdown.markdown(
        report_markdown,
        extensions=["extra", "nl2br", "sane_lists"],
    )
    escaped_subject = html.escape(subject)
    return (
        "<!doctype html>\n"
        '<html lang="en">\n'
        "  <head>\n"
        '    <meta charset="utf-8">\n'
        f"    <title>{escaped_subject}</title>\n"
        "  </head>\n"
        "  <body>\n"
        f"{report_body}\n"
        "  </body>\n"
        "</html>\n"
    )


def format_email_response(response: Any) -> str:
    if isinstance(response, dict):
        serialized = response
    elif hasattr(response, "__dict__"):
        serialized = vars(response)
    else:
        return f"{response}\n"

    return json.dumps(serialized, indent=2, sort_keys=True, default=str) + "\n"


def persist_success(state: AuditState) -> dict[str, Any]:
    if state["should_update_last_success"]:
        state["last_success_file"].write_text(f"{state['until_iso']}\n", encoding="utf-8")
    return {}


def build_failure_report(state: AuditState, error_output: str) -> str:
    manifest_path = state["manifest_file"]
    evidence_paths: list[Path] = []
    if manifest_path.exists():
        evidence_paths.append(manifest_path)

    if state["bundle_dir"].exists():
        evidence_paths.extend(sorted(state["bundle_dir"].glob("*.md")))

    lines = [
        "# Homolab Daily Audit",
        "",
        "## Executive Summary",
        "",
        "The daily audit LangGraph pipeline failed before a report could be generated.",
        "",
        "## Findings",
        "",
        f"- Audit window: `{state.get('since_iso', 'unknown')}` to `{state.get('until_iso', 'unknown')}`",
        f"- Run directory: `{state['run_dir']}`",
        "",
        "```text",
        error_output.rstrip(),
        "```",
        "",
        "## Benign Noise",
        "",
        "Not evaluated because the pipeline failed.",
        "",
        "## Follow-Up Actions",
        "",
        f"- Inspect `{state['run_dir']}` on homolab.",
        "- Re-run `systemctl start homolab-daily-audit.service` after fixing the failure.",
        "",
        "## Evidence Reviewed",
        "",
    ]

    if evidence_paths:
        lines.extend(f"- `{path}`" for path in evidence_paths)
    else:
        lines.append("None.")

    lines.append("")
    return "\n".join(lines)


def write_failure_artifacts(state: AuditState, error_output: str) -> None:
    state["pipeline_stderr"].write_text(error_output, encoding="utf-8")
    state["audit_subject"] = f"[homolab] Daily audit pipeline failed for {state['report_date']}"
    failure_report = build_failure_report(state, error_output)
    state["report_file"].write_text(failure_report, encoding="utf-8")
    state["final_report"] = failure_report


def build_graph() -> Any:
    builder = StateGraph(AuditState)
    builder.add_node("route-bundle-source", passthrough)
    builder.add_node("collect-overview", collect_overview)
    builder.add_node("collect-priority-journal", collect_priority_journal)
    builder.add_node("collect-authentication", collect_authentication)
    builder.add_node("collect-edge-services", collect_edge_services)
    builder.add_node("collect-application-services", collect_application_services)
    builder.add_node("collect-kernel", collect_kernel)
    builder.add_node("write-manifest", write_manifest)
    builder.add_node("analyze-bundle", analyze_bundle)
    builder.add_node("generate-final-report", generate_final_report)
    builder.add_node("send-email", send_email)
    builder.add_node("persist-success", persist_success)

    builder.add_edge(START, "route-bundle-source")
    builder.add_conditional_edges(
        "route-bundle-source",
        route_bundle_source,
        {
            "collect": "collect-overview",
            "reuse": "analyze-bundle",
        },
    )
    builder.add_edge("collect-overview", "collect-priority-journal")
    builder.add_edge("collect-priority-journal", "collect-authentication")
    builder.add_edge("collect-authentication", "collect-edge-services")
    builder.add_edge("collect-edge-services", "collect-application-services")
    builder.add_edge("collect-application-services", "collect-kernel")
    builder.add_edge("collect-kernel", "write-manifest")
    builder.add_edge("write-manifest", "analyze-bundle")
    builder.add_edge("analyze-bundle", "generate-final-report")
    builder.add_conditional_edges(
        "generate-final-report",
        route_email_delivery,
        {
            "send-email": "send-email",
            "persist-success": "persist-success",
        },
    )
    builder.add_edge("send-email", "persist-success")
    builder.add_edge("persist-success", END)
    return builder.compile()


def main() -> int:
    args = parse_args()
    state = prepare_run_context(args)
    graph = build_graph()

    try:
        graph.invoke(state)
    except Exception:
        error_output = traceback.format_exc()
        write_failure_artifacts(state, error_output)
        if state["send_email"]:
            send_email(state)
            return 0
        return 1

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        sys.exit(1)
