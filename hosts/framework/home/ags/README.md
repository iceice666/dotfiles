# Framework AGS shell

The Framework shell uses **AGS 3 / Astal GTK4 / Gnim**, pinned to upstream
**AGS v3.1.2** and its matching Astal revision through `flake.lock`. Both of the
repo's nixpkgs inputs still package AGS 2.3, so this shell uses the upstream flake
instead. Upstream v3.1.2 leaves `cli/version` at `3.1.0`; that version in the
package path or CLI output does not mean the wrong revision was selected.
The service executes the bundle at `~/.config/ags/app.js` directly. Despite the
historical filename, AGS 3 emits a shell launcher that starts GJS with the GTK4
layer-shell preload; it is not JavaScript input for `ags run`. A Nix-generated
`framework-ags` wrapper supplies GTK/Astal typelibs and runtime data independently
of the AGS CLI wrapper.

## Ownership

- `app.tsx`: per-monitor Niri app/workspace strip, media and performance indicators,
  battery, Astal tray, calendar, popup dismissal and monitor lifecycle.
- `state.ts`: string-valued Rust JSON patches, shared reactive state and argv-based
  actions. Wi-Fi failures never log passwords, argv or command stderr.
- `control-center.tsx`: Material/GNOME-inspired two-column quick settings, audio
  and brightness controls, media, Wi-Fi connection/password UI, notification
  center, and session actions. Bluetooth device settings open Overskride; detailed audio
  settings open pavucontrol. This is an independently authored adaptation of our
  existing shell, not a vendored Matshell or DankMaterialShell component.
- `notifications.tsx`: AstalNotifd daemon ownership, popups, notification cards,
  in-memory unread tracking, history cap and Do Not Disturb.
- `style.scss`: GTK4 styling using the existing wallpaper-derived Material palette.
- `default.nix`: bundles TypeScript and both CSS variants, installs runtime config,
  and starts `framework-ags.service` with the graphical session.
- `icons.nix`: SVG assets shared with the state helper.
- `pkgs/framework-shell-state`: UI-neutral Rust collectors/actions. The daemon
  emits newline-delimited JSON patches; values are strings, including the encoded
  `niri_groups` array. Actions emit refreshed patches. It has no notification role.

AGS owns monitor/window lifecycle. Output matching uses GTK4's monitor connector
rather than GDK index ordering. Each monitor has its own hover revealers; opening
one control/calendar/power popup closes the other monitors' popups. Escape and clicking
the backdrop dismiss a popup, and dismissal clears password input. The panel is
height-limited to its monitor and scrolls on small displays.

## Notifications

AGS is the notification daemon: `AstalNotifd` owns `org.freedesktop.Notifications`
inside `framework-ags.service`, and a user D-Bus activation file
(`SystemdService=framework-ags.service`) starts the shell for early senders. There
is no Mako or other fallback daemon; if AGS is down, notifications wait for
activation/restart.

- The daemon never expires entries (`ignore-timeout`, `default-timeout = -1`).
  Popups hide after 7 s in the UI (critical popups stay), but entries remain in
  the center until dismissed, invoked, or closed by the sending app. Only the
  newest 50 are kept; older ones are dismissed automatically.
- Entries persist across AGS restarts and reboots through AstalNotifd's
  `io.astal.notifd` GSettings keys (dconf). Unread state is in memory only.
- The bar badge counts unread notifications. Clicking/acting on a popup or opening
  the Notifications page marks them read. Left click runs a popup's default action;
  right click or the close button dismisses.
- The DND tile toggles `dont-disturb`: new notifications are still recorded and
  counted but show no popup.
- Popups use one layer surface without a fixed output, so Niri places it on the
  focused output.

Media keys invoke the helper
without depending on a running UI. The lid-sleep toggle starts/stops
`framework-lid-inhibit.service`, which is session-scoped and disabled at login.

## Tray and theme

Astal handles StatusNotifier discovery, icons and DBusMenu import. The GTK4 front
end supports menu items, normal activation, middle-click secondary activation,
right-click menus and scrolling. Dynamic menu refresh requests have a bounded
asynchronous timeout; an unresponsive tray app must not block GTK. An open menu
keeps the tray revealer expanded until dismissal. Passive items are hidden.

Battery and tray retain 40×32 icon slots. The battery circle is now a GTK4 drawing
area, with a 32px full-circle track and a fixed 3px stroke; it no longer relies on
GTK3 Astal CircularProgress's font-size convention.
The battery label reads TLP's `Power profile` (1.9) or `TLP profile` (1.10+)
field and displays Performance, Balanced, or Power Saver; legacy `Mode` output
keeps AC/Battery labels. Missing or unrecognized profiles display Unknown rather
than guessing from the power source. Icons and charging styling use UPower's
supply state independently of the selected profile.
Clicking the battery opens a compact Power Mode panel with Performance, Balanced,
and Power Saver choices and a checkmark on the current TLP profile. Selection runs
an allowlisted TLP command through NixOS's `pkexec` wrapper; the Home Manager
`polkit-gnome` agent supplies the authorization dialog, without passwordless rules.
Choices are disabled while authorization/application is pending; failures stay
visible and do not optimistically change the selected mode. TLP's configured
policies define what each profile does (these are not raw hardware platform
profiles). Plug/unplug and reboot behavior remains controlled by TLP.

`themegen/framework/.config/ags/theme-{light,dark}.scss` supplies palette values.
Both stylesheets are compiled during the Framework build. The appearance installer
selects `style.css` and `theme.scss`, then asynchronously restarts AGS. The latter
link also lets the Rust helper choose the matching icon colors. There is no second
Matugen theme generator or competing shell/notification service.

## Validation and activation

```sh
just fmt
just build
just check
```

After reviewing the build, deploy explicitly with `just switch`. Check
`systemctl --user status framework-ags.service` and
`journalctl --user -u framework-ags.service -b`. Verify on the real desktop:

1. Every connected display gets one bar and its own Niri workspace/window list;
   unplugging/reconnecting a display removes/recreates its windows.
2. Tray applications update icons and menus, respond to all mouse buttons and
   scrolling, and close menus cleanly without collapsing the hovered tray early.
3. Calendar/control-center keyboard focus, Escape and click-outside dismissal work.
4. Wi-Fi scanning, saved/open/secured connections and errors work without exposing
   credentials; Bluetooth settings open correctly.
5. Speaker/microphone/brightness controls and media keys update live. State updates
   alone must not emit setter commands.
6. `notify-send` popups, actions, unread badge, center history, DND, and
   persistence across `systemctl --user restart framework-ags` work together.
7. Both themes retain the wallpaper palette and legible active/disabled states.
8. Lid sleep is restored when the inhibitor is toggled off or the session ends.
9. Clicking battery opens Power Mode; each profile prompts for authorization and
   updates the checkmark after success. Cancellation leaves the current mode intact.
   Escape, click-outside, other panels and monitor removal dismiss the panel.

Do not run a second shell on the live session merely to test compilation: it
would compete for the tray watcher and reserve another bar. `smoke-test.sh` uses
two headless labwc outputs, a private home/runtime directory and D-Bus session,
synthetic state, and mock action commands. It bundles the instrumented entry and
executes that launcher through the built runtime wrapper, matching the deployed
service's launch path.
`smoke-probe.ts` checks widget/layout,
real Notify calls through AstalNotifd (popups, actions, unread, DND, clear),
slider command isolation, power-profile success/denial and popup lifecycle,
masked Wi-Fi failures/password clearing, popup behavior
and monitor disposal/remount. `smoke-tray.js` exports isolated
StatusNotifier/DBusMenu fixtures to exercise delayed dynamic menu updates, menu
actions, activation, secondary activation, scrolling and removal. Run once per palette with built dependencies:

```sh
AGS=/nix/store/…-ags-3.1.0 \
AGS_LAUNCHER=/nix/store/…-framework-ags-assets/bin/framework-ags \
LABWC=/nix/store/…-labwc \
SASS=/nix/store/…-dart-sass \
THEME_SCSS=/nix/store/…-themegen-cache-framework/.config/ags/theme-dark.scss \
bash hosts/framework/home/ags/smoke-test.sh
```

Set `KEEP_SMOKE_LOGS=1` to retain private fixture logs. Optionally set
`SMOKE_GRIM=/absolute/path/to/grim` to capture the synthetic control center as
`control-home.png` alongside the logs. This is not a substitute
for real application tray menus, physical monitor hotplug or actual device
operations. The harness needs Bash, Python 3, `dbus-run-session`, and coreutils;
the AGS wrapper supplies GJS for the D-Bus fixture.

References: [AGS migration guide](https://aylur.github.io/ags/guide/migration-guide.html),
[AGS Nix packaging](https://aylur.github.io/ags/guide/nix.html),
[Astal](https://github.com/Aylur/astal),
[Material/AGS reference Matshell](https://github.com/Neurarian/matshell).
