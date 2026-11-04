# Alpine root Home Manager hosts

Shared baseline for `lumo` and `worker`: Alpine Linux 3.24 on Raspberry Pi
(aarch64) with root-only Lix installed using `--init none`. deploy-rs activates
the standalone root Home Manager profile and builds the aarch64 closure on the
target.

## Ownership split

- **Alpine/APK** owns boot, the kernel, networking, OpenSSH, Tailscale, cgroups,
  and the nftables launcher.
- **Home Manager** owns root tooling, Nix-built service binaries, generated
  configuration, and OpenRC-supervised application services.

Home Manager activation never runs `apk upgrade`. Only `scripts/alpine-upgrade`
(`just <host>-upgrade [apply]`) upgrades APK packages: it prints pending
upgrades, applies them only with `apply`, compares the installed `linux-rpi`
package to the running kernel, and prints reboot/restart hints. It never reboots
or restarts services itself.

## Bootstrap

`scripts/alpine-bootstrap` (`just <host>-bootstrap`) installs host primitives:
root SSH, static addresses, Tailscale, cgroups, nftables reachability, and
prints the host age recipient. It also:

- installs `/etc/sysctl.d/10-dotfiles-hardening.conf` (kptr/dmesg restrict, no
  ICMP redirects, protected fifos/regular);
- tightens sshd (`AllowAgentForwarding no`, `MaxAuthTries 3`, `LoginGraceTime 30`);
- prepends `cgroup_enable=memory cgroup_memory=1` to `/boot/cmdline.txt` so the
  Raspberry Pi firmware stops injecting `cgroup_disable=memory` (effective after
  a reboot).

Tailscale SSH (`tailscale set --ssh=true`) bypasses sshd's `authorized_keys`
entirely and grants root per tailnet ACL; keep that ACL tight.

## Provisioning a board

1. Run `just <host>-bootstrap`; it prints the age recipient.
2. Add the recipient anchor and host rule entry to `.sops.yaml`.
3. Re-encrypt host secrets with `just secret-refresh sensitive/hosts/<host>`.
4. Run `just <host>-build`, then `just <host>-switch`.
5. Reboot, and for lumo run `just lumo-smoke`.

CA bundle handling on Alpine is described in `docs/tls-trust.md`.
