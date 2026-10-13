# Homolab Server Security Audit Guide

This is the baseline interpretation guide for automated daily Homolab audit
reports. It intentionally avoids decrypted secret content.

## Expected Exposure

| Surface | Expected reachability | Notes |
| --- | --- | --- |
| `:80`, `:443` | LAN and Cloudflare; tailnet if explicitly trusted | Traefik terminates TLS and forwards to protected services. |
| `:22` | LAN host SSH (Alpine `sshd`, `AllowUsers root git`) | Password auth disabled; root public-key login permitted (`prohibit-password`). This is the real host-management SSH service; see `scripts/alpine-bootstrap`. |
| Forgejo / Woodpecker | Temporarily offline | `lumo.forgejoWoodpecker.enable = false` by default. No stack containers or port 2222 listener are expected. Persistent data and configuration are retained. Their individual status checks may report stopped (exit 3); this is intentional, not a failed enabled service. |
| `:53` | Blocky on lumo's Tailscale address | DNS is provided over the tailnet; DoH is published through Traefik. |
| Internal service ports | Loopback or explicit network trust | Some backends bind broadly; inspect nftables and tailnet ACLs rather than assuming loopback-only exposure. |

## Priority Checks

- Compare `input/listeners.txt` to `lib/homolab.nix` and service modules.
- Flag wildcard listeners that are not intentionally public.
- Compare `input/nftables.txt` to the lumo edge nftables configuration.
- Flag stale firewall rules for removed services.
- Confirm expected Cloudflare source sets are present and non-empty.
- Confirm private Traefik routes remain Authelia-protected or source-restricted.
- Treat rootful Podman socket access as host-root equivalent.
- Treat rootful container image tags as trust-boundary sensitive.
- Check `input/host-sshd-status.txt`, `input/host-syslog-status.txt`, and each
  `input/service-lumo-*-status.txt`; nonzero command statuses are evidence of a
  failed check, even when later collection succeeds. Do not infer that a healthy
  container proves the host SSH service or sysklogd logger is healthy.
- Review `input/system-log.txt` for suspicious authentication or daemon activity.
  The sysklogd evidence includes current `auth.log`, `syslog`, `messages`,
  `daemon.log`, and `kern.log` files and rotations `.0`/`.1`/`.2`, plain or gzip.
  Each file is capped at its last 500 lines and 64 KiB. Missing current files,
  unreadable files, and command failures must be reported as collector gaps;
  absent optional rotations alone are not failures. Never claim complete
  24-hour log coverage from this bounded sample or treat missing evidence as
  proof of no suspicious activity.
- Flag failed services, suspicious captured logs, model load failures, and
  resource pressure. Process evidence intentionally omits arguments and
  environment to avoid collecting credentials.

## Known Triage Areas

- Tailscale can become broader than comments imply if `tailscale0` is trusted or
  `ts-input` accepts the interface before port-specific rules.
- Dynacat should not be directly reachable except through the intended protected
  route.
- IPv6 SSH exposure can change if the host receives a global IPv6 address.
- Long-running container images should be digest-pinned where possible.
- The Alpine support window and host firmware age should be reviewed regularly.
