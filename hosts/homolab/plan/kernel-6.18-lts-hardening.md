# Kernel 6.18 LTS And Kernel Surface Hardening Plan

## Goal

Bump `homolab` from the manually pinned Linux `6.12.89` kernel to the Linux `6.18` LTS kernel line, while preserving the mitigations and hardening decisions from the May 2026 kernel CVE audit.

The intended result is:

- Run a maintained LTS kernel line newer than `6.12`.
- Keep Fragnesia/Dirty Frag/RxRPC mitigations until the fix status is explicit.
- Remove unused Bluetooth and kernel SMB attack surface.
- Keep Tailscale LAN trust as an intentional policy.
- Validate NVIDIA, Podman, Tailscale, networking, and service behavior before applying.

## Context

Current audited state:

- Live kernel: `6.12.89`.
- NixOS generation: booted and current generations differ, but both use `6.12.89`.
- `configuration/system.nix` manually pins `pkgs.linux_6_12` to upstream `6.12.89`.
- `esp4`, `esp6`, and `rxrpc` are already blacklisted and forced to fail through `boot.extraModprobeConfig`.
- `bluetooth` and `btusb` are loaded on the host even though Bluetooth userspace is disabled.
- `ksmbd` is not loaded and SMB is not used.
- Tailscale is intentionally trusted as a LAN-equivalent interface.

The audit conclusion was that Linux `6.12.89` appears fixed or mitigated for the listed CVEs except that Fragnesia should still be treated conservatively. The move to `6.18` LTS is for a newer maintained base, not a reason to remove the existing ESP/RxRPC mitigations yet.

## Fixed Decisions

- Prefer Linux `6.18` LTS over Linux `7.0` stable for this server.
- Do not move to Linux `7.0` unless a required security fix is unavailable on maintained LTS lines.
- Keep Tailscale trusted by policy.
- Do not treat broad tailnet reachability as a bug, but document it clearly.
- Bluetooth is unused and should be blocked at the kernel module level.
- Kernel SMB/`ksmbd` is unused and should be blocked at the kernel module level.
- Keep `esp4`, `esp6`, and `rxrpc` blocked until Fragnesia and related shared-frag fixes are confirmed in the deployed kernel line.

## Files Expected To Change

- `configuration/system.nix`
- possibly `plan/kernel-6.18-lts-hardening.md` as implementation notes are updated

No secret files should change.

## Target Kernel Configuration

Replace the manual `6.12.89` source override with the Nixpkgs-provided `6.18` LTS package set if available:

```nix
boot.kernelPackages = pkgs.linuxPackages_6_18;
```

If the current nixpkgs revision does not expose `pkgs.linuxPackages_6_18`, use the least custom alternative:

1. Update nixpkgs to a revision that has `linuxPackages_6_18`.
2. If that is not acceptable, temporarily use `pkgs.linuxPackagesFor pkgs.linux_6_18`.
3. Avoid a manual upstream tarball override unless Nixpkgs is behind a security release and no package attribute exists.

## Module Blocking Target

Keep the existing module block:

- `esp4`
- `esp6`
- `rxrpc`

Add unused kernel surfaces:

- `ksmbd`
- `bluetooth`
- `btusb`
- `btrtl`
- `btintel`
- `btbcm`
- `btmtk`

Use both `boot.blacklistedKernelModules` and `boot.extraModprobeConfig` install overrides for the high-risk modules. Blacklisting alone prevents hotplug autoload, but install overrides make manual or alias-based `modprobe` attempts fail.

Suggested shape:

```nix
boot.blacklistedKernelModules = [
  "esp4"
  "esp6"
  "rxrpc"
  "ksmbd"
  "bluetooth"
  "btusb"
  "btrtl"
  "btintel"
  "btbcm"
  "btmtk"
];

boot.extraModprobeConfig = ''
  install esp4 /run/current-system/sw/bin/false
  install esp6 /run/current-system/sw/bin/false
  install rxrpc /run/current-system/sw/bin/false
  install ksmbd /run/current-system/sw/bin/false
  install bluetooth /run/current-system/sw/bin/false
  install btusb /run/current-system/sw/bin/false
  install btrtl /run/current-system/sw/bin/false
  install btintel /run/current-system/sw/bin/false
  install btbcm /run/current-system/sw/bin/false
  install btmtk /run/current-system/sw/bin/false
'';
```

The activation script can be renamed from `dirtyfragMitigation` to a more general kernel surface mitigation name and expanded to unload the newly blocked modules if present.

## Tailscale Policy

Leave this behavior unchanged:

```nix
networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
```

Add a comment near the Tailscale firewall configuration explaining that the tailnet is intentionally trusted as a LAN-equivalent management network. This avoids future confusion because the lower-level iptables rules only mention selected ports, while the NixOS firewall trust rule accepts traffic from `tailscale0` broadly.

## BPF Hardening

Keep:

```text
kernel.unprivileged_bpf_disabled = 1
```

Consider adding:

```nix
boot.kernel.sysctl."net.core.bpf_jit_harden" = 2;
```

This is optional. It is reasonable for this server if no high-performance BPF workload depends on lower overhead JIT behavior.

## Implementation Phases

### Phase 1: Preflight

1. Confirm the current worktree is clean:
   ```sh
   git status --short
   ```
2. Confirm the kernel package attribute exists:
   ```sh
   nix eval --raw nixpkgs#linuxPackages_6_18.kernel.version
   ```
3. Confirm the configured NVIDIA package is available for the target kernel:
   ```sh
   nix eval .#nixosConfigurations.homolab.config.boot.kernelPackages.nvidiaPackages.stable.version --raw
   ```

### Phase 2: Config Change

1. Edit `configuration/system.nix`.
2. Replace the manual `6.12.89` override with `pkgs.linuxPackages_6_18`.
3. Keep `esp4`, `esp6`, and `rxrpc` blocks.
4. Add Bluetooth and `ksmbd` blocks.
5. Rename or generalize the activation script so it removes all blocked modules that may already be loaded.
6. Add a Tailscale trust comment in `services/edge/tailscale.nix` or `configuration/networking.nix`.

### Phase 3: Build Validation

Run:

```sh
just fmt
just build
just check
```

If `just build` fails on NVIDIA kernel module compatibility, stop and either:

- update nixpkgs to a revision with working NVIDIA support for Linux `6.18`, or
- revert only the kernel bump and keep the module hardening changes.

### Phase 4: Apply

Apply only after the build is clean:

```sh
just rebuild
```

This usually requires `sudo`; ask before running it.

Reboot during a maintenance window after rebuild so the booted system and current system match.

### Phase 5: Post-Reboot Verification

After reboot, verify:

```sh
uname -a
nixos-version --json
readlink -f /run/booted-system /run/current-system /run/booted-system/kernel /run/current-system/kernel
```

Check blocked modules:

```sh
awk '/^(esp4|esp6|rxrpc|ksmbd|bluetooth|btusb|btrtl|btintel|btbcm|btmtk)/ {print}' /proc/modules
modprobe -n -v esp4
modprobe -n -v esp6
modprobe -n -v rxrpc
modprobe -n -v ksmbd
modprobe -n -v bluetooth
modprobe -n -v btusb
```

Expected result:

- No blocked modules are loaded.
- `modprobe -n -v` shows the install override to `/run/current-system/sw/bin/false`.

Check critical services:

```sh
systemctl --no-pager --plain is-active tailscaled.service traefik.service sshd.service technitium-dns-server.service podman.service woodpecker-server.service woodpecker-agent-podman.service
ss -H -tulpen
iptables -S INPUT
ip6tables -S INPUT
```

Check kernel logs:

```sh
journalctl -k -b --no-pager -p warning
journalctl -k -b --no-pager -g 'BUG|Oops|KASAN|general protection|kernel BUG|NVRM|nvidia|tailscale|podman|Bluetooth|ksmbd|rxrpc|esp4|esp6'
```

## Rollback Plan

If the system fails to boot or core services fail:

1. Boot the previous generation from systemd-boot.
2. Revert the kernel package change only.
3. Keep the Bluetooth and `ksmbd` blocking changes if they are not responsible for the failure.
4. Re-run:
   ```sh
   just build
   ```
5. Rebuild back to a known-good generation.

If NVIDIA is the only failing component, prefer updating nixpkgs or the NVIDIA package set before abandoning Linux `6.18` LTS.

## Removal Criteria For Temporary Mitigations

Only remove `esp4`, `esp6`, and `rxrpc` blocks after all are true:

- The deployed kernel line has explicit Fragnesia fix confirmation.
- Dirty Frag and RxRPC shared-frag fixes are present in the same deployed kernel.
- `modprobe -n -v esp4`, `esp6`, and `rxrpc` are intentionally allowed again.
- There is an actual operational need for IPsec/XFRM ESP or RxRPC.

If there is no operational need, leave them blocked as attack-surface reduction.

Bluetooth and `ksmbd` blocks should remain indefinitely unless the server starts using those features.
