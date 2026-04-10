---
name: homolab-daily-audit
description: Analyze homolab server audit bundles generated from recent journald and systemd snapshots. This skill should be used when producing the recurring daily security and service-health report from prepared evidence files.
---

# Homolab Daily Audit

## Overview

Analyze prepared `homolab` audit bundles for the last 24-48 hours and turn them into a concise daily report. Focus on suspicious activity, externally exposed service health, authentication anomalies, and actionable follow-up without overstating confidence.

## When To Use

Use this skill when OpenCode is asked to review the recurring `homolab` daily audit bundle or to generate the email-ready report from attached evidence files. Expect the evidence to be bounded `journalctl` extracts, failed-unit summaries, and service-specific log slices rather than full-host shell access.

## Workflow

1. Read every attached audit bundle file before forming conclusions.
2. Load `references/homolab-services.md` to understand which services are expected on `homolab` and which ones are internet-facing.
3. Load `references/detection-rules.md` to apply the repo-specific triage rubric.
4. Separate evidence into likely malicious or abusive activity, operational regressions, and benign background noise.
5. State uncertainty explicitly when evidence is incomplete or ambiguous.
6. Prefer concrete timestamps, unit names, usernames, domains, IPs, and error strings over generic summaries.
7. Avoid asking for more context when the attached bundle already covers the audit window well enough to produce the daily report.

## Reporting Rules

- Use only the attached evidence and the loaded references.
- Do not label activity as confirmed compromise unless the logs clearly support it.
- Treat routine internet probes, crawler noise, and expected reverse-proxy chatter as benign unless they escalate into successful authentication, privilege changes, or service disruption.
- Call out successful logins, privilege escalations, crash loops, repeated 5xx or proxy failures, storage errors, and kernel-level instability.
- Mark a clean day explicitly instead of padding the report with filler.

## Output Expectations

- Write concise Markdown for email delivery.
- Put the executive summary first.
- List findings in descending severity.
- Include a `Benign Noise` section even if it only says `None noted`.
- Include a `Follow-Up Actions` section with concrete next steps or `None`.
- Include an `Evidence Reviewed` section that names the attached audit bundle files.
