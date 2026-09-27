# Homolab Server Security Audit Guide

This is the baseline interpretation guide for automated daily Homolab audit
reports. It intentionally avoids decrypted secret content.

## Expected Exposure

| Surface | Expected reachability | Notes |
| --- | --- | --- |
| `:80`, `:443` | LAN and Cloudflare on `enp7s0`; tailnet if explicitly trusted | Traefik terminates TLS and forwards to protected services. |
| `:22` | LAN host SSH (Alpine `sshd`, `AllowUsers root git`) | Password auth disabled, root login disabled (`prohibit-password`). This is the real host-management SSH service; see `scripts/alpine-bootstrap`. |
| `:2222` | Forgejo container's built-in Git SSH server, LAN-restricted to homolab and lumo only | `FORGEJO__server__SSH_PORT`/`SSH_LISTEN_HOST=0.0.0.0` in `hosts/lumo/home/services/forgejo-woodpecker.nix`; firewalled to `192.168.1.127`/`.128` only (see `hosts/lumo/home/services/edge/nftables.nix`). Not a host-management SSH service — do not flag as one on its own. |
| `:53` | LAN DNS only | Technitium may listen broadly; firewall is the boundary. |
| Internal service ports | Loopback only or dropped on `enp7s0` | Authelia, Multica, Grafana, Prometheus, Traefik metrics. |

## Priority Checks

- Compare `input/listeners.txt` to `lib/homolab.nix` and service modules.
- Flag wildcard listeners that are not intentionally public.
- Compare `input/iptables-v4.txt` and `input/iptables-v6.txt` to
  `configuration/networking.nix`.
- Flag stale firewall rules for removed services.
- Confirm Cloudflare ipsets are present and non-empty.
- Confirm private Traefik routes remain Authelia-protected or source-restricted.
- Treat rootful Podman socket access as host-root equivalent.
- Treat rootful container image tags as trust-boundary sensitive.
- Flag failed services, failed timers, suspicious 24-hour auth logs, model load
  failures, and resource pressure.

## Known Triage Areas

- Tailscale can become broader than comments imply if `tailscale0` is trusted or
  `ts-input` accepts the interface before port-specific rules.
- Dynacat should not be directly reachable except through the intended protected
  route.
- IPv6 SSH exposure can change if the host receives a global IPv6 address.
- Long-running container images should be digest-pinned where possible.
- The NixOS support window and host firmware age should be reviewed regularly.
