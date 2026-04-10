# Detection Rules

Use this rubric to turn the attached audit bundle into a measured report.

## High-Signal Findings

Treat these as high priority when the evidence is present:

- Successful SSH authentication that is unexpected for the audit window
- Any successful root login attempt or evidence that root-login protections changed
- Any indication that password-based SSH auth succeeded
- Repeated privilege-escalation events that are not clearly tied to expected admin work
- Repeated `traefik`, `cloudflared-tunnel`, `authelia`, `forgejo`, or `woodpecker` crashes or restart loops
- Kernel, filesystem, storage, or OOM errors that threaten host stability or data integrity
- Authentication bypass, token failures, or reverse-proxy misrouting that expose protected services

## Medium-Signal Findings

Call these out when they are persistent or correlated with other anomalies:

- Large bursts of SSH failures against `iceice666`
- Authelia authentication failures, especially repeated failures from one source
- Repeated 4xx or 5xx proxy errors that suggest misconfiguration or abuse
- Service-specific errors that recur across the audit window without full outage
- Failed units that did not self-recover cleanly

## Usually Benign Noise

Treat these as benign unless accompanied by successful access or service impact:

- Background internet scanning against SSH or HTTPS endpoints
- Reverse-proxy requests for missing paths or random hostnames
- Routine crawler or bot traffic
- Short-lived reconnects from `cloudflared-tunnel`
- One-off warning lines with no follow-on failures

## Reporting Guidance

- Distinguish clearly between suspicious behavior and ordinary service-health problems.
- State when the bundle shows no notable suspicious activity.
- Quote specific evidence instead of summarizing loosely.
- Prefer short action items that an operator can execute immediately.
