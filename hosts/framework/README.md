# framework

NixOS laptop managed by `nixosConfigurations.framework`. The system imports
`home-manager.nixosModules.home-manager`, so user configuration lives under
`home/`, but the active switch path is the NixOS system target (`just build`,
`just switch`, `just boot`).

- `configuration/` — active NixOS entrypoint, hardware, and `grub-theme.nix` (GRUB theme built from repo assets).
- `home/` — GUI/Niri/AGS Home Manager modules.
- `home/niri-config.kdl` — Niri compositor config installed through Home Manager.
- `home/ags/` — AGS 3 / Astal GTK4 shell; see its README.

## Kernel

Framework uses nixpkgs' `linuxPackages_zen` directly so kernel security fixes
arrive with `just update nixpkgs`. Do not reintroduce a local pin to an
end-of-life kernel series; if a pin is ever needed, keep it on a supported
kernel.org branch and remove it once nixpkgs catches up.

## Fingerprint authentication

Configured in `configuration/default.nix` through `services.fprintd.enable` and
`security.pam.services.{greetd,sudo}.fprintAuth`. Keep `fprintd` in the system
packages so `fprintd-enroll` and related tools are available for enrollment and
troubleshooting.

## AGS shell

`home/ags/` runs `framework-ags.service`, pinned through the upstream AGS flake
with its matching Astal libraries. It provides per-monitor bars,
StatusNotifier tray/GTK4 menus, calendar, and a control center. `state.ts`
adapts the Rust backend (`pkgs/framework-shell-state/`, which emits UI-neutral
JSON-line state patches and handles media keys), `control-center.tsx` owns the
panel, and `app.tsx` owns monitor/window lifecycle and the bar. AGS owns
notifications through AstalNotifd (`notifications.tsx`), with a D-Bus activation
file pointing at `framework-ags.service` — there is no Mako. Theme files come
from `themegen/framework/.config/ags/`.

## Appearance scheduling

`home/gui.nix` uses Home Manager's `services.darkman` with coarse Taipei
coordinates, exposes darkman through the XDG Settings portal, and runs
GTK/GNOME color-scheme scripts on sunrise/sunset transitions.

## Wallpaper rotation

`home/wallpaper.nix`. `host.nix` lists the set as `desktopWallpapers` (files
under `assets/`, unique stems); `desktopWallpaper` stays the static regreet
login background. Every wallpaper gets its own themegen render plus AGS CSS and
`Themegen{,-dark}` GTK theme dirs at build time.

The `framework-wallpaper` helper copies the chosen bundle to
`~/.local/state/themegen/current`, which all themegen Home Manager links point
at, then reloads apps (darkman appearance links, GTK name bounce, link nudges
for Zed/Pi/Equibop dir watchers, kitty `SIGUSR1`, fish `themegen_generation`
uvar, AGS restart, `awww img`). The darkman hook rotates to a random different
wallpaper only when the mode actually changes (sunrise/sunset or a manual
toggle); logins and `just switch` keep the current one. `framework-wallpaper
next` rotates manually. awww replaces swaybg. libadwaita apps pick up new colors
only after restarting.

## Reinstallation

`just framework-iso` builds the `framework-installer` host without activating
it. Its source snapshot includes tracked encrypted secrets but never identities.
`scripts/framework-install` requires a local console, UEFI, an unused whole
disk, an explicit swap size and exact erasure confirmation; it dry-runs the
online build plan before wiping, then builds into the target disk store after
erasure. It creates the existing Btrfs subvolumes and patches only the installed
source copy's EFI UUID to `NIXOS_BOOT`. No destructive command runs on boot.

Run `just framework-install-test` for safe fixture tests; never execute the
destructive path on a real host as validation. See
`../framework-installer/README.md` for backups, credential recovery, and
disposable UEFI VM validation.
