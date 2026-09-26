# Framework AGS shell

The Framework shell uses the flake-pinned **AGS 2.3 / Astal GTK3** API, not AGS 1 or
current AGS 3 examples. No additional flake input is needed.

- `app.tsx`: per-monitor Niri app/workspace strip, media and performance indicators,
  battery, Astal tray, calendar, and control-center views.
- `style.scss`: GTK3 styling using wallpaper-derived palette variables. Battery
  and tray retain Eww's 40×32 icon slots; the 32px battery ring uses a 3px stroke
  (`font-size` in Astal) and equal start/end positions for a full-circle track.
  Both hover revealers are local to each monitor.
- `default.nix`: builds JavaScript and both CSS variants, installs runtime config,
  and starts `framework-ags.service` with the graphical session.
- `icons.nix`: SVG assets shared with the state helper.
- `pkgs/framework-shell-state`: UI-neutral Rust collectors/actions. The daemon
  emits newline-delimited JSON patches; values are strings, including the encoded
  `niri_groups` and `notifications_history` arrays. Actions emit refreshed patches.

AGS owns monitor/window lifecycle. Mako remains the notification daemon; the shell
reads its active/history lists and existing hooks track unread notifications.
Media keys invoke the helper directly, without depending on a running UI.
Commands use argv arrays rather than interpolated shell strings. Wi-Fi errors
must never log passwords or command argv.

## Theme and lifecycle

`themegen/framework/.config/ags/theme-{light,dark}.scss` supplies palette values.
Both stylesheets are compiled during the Framework build. The appearance installer
selects `style.css` and `theme.scss`, then asynchronously restarts AGS. The latter
link also lets the Rust helper choose the matching icon colors.

The lid-sleep toggle starts/stops `framework-lid-inhibit.service`. This optional
inhibitor belongs to the graphical session and is not enabled at login.

## Migration and validation

```sh
nix build .#framework-shell-state
cargo test --locked --manifest-path pkgs/framework-shell-state/Cargo.toml
just fmt
just build
just check
```

After reviewing the build, deploy with `just switch`. Home Manager replaces the
old `framework-eww`/`framework-eww-bars` units and managed Eww config with AGS. An
old unmanaged `~/.config/eww/theme.scss` link or old runtime caches can remain; AGS
does not read them. No user files are forcibly deleted.

Check `systemctl --user status framework-ags.service` and
`journalctl --user -u framework-ags.service -b` after activation. Verify:

1. Each connected display gets one bar, with its own workspace/window list;
   unplugging/reconnecting a display removes/recreates its windows.
2. Tray menus, calendar, click-outside/Escape dismissal, and control-center
   navigation work; Wi-Fi connection failures are visible without exposing secrets.
3. Speaker/microphone/brightness controls and media keys update live.
4. Mako notifications, unread badges, history and DND work together.
5. Light/dark switching retains transparent surfaces and the wallpaper palette.
6. Lid sleep is restored when the inhibitor is toggled off or the session ends.

Do not run a second shell on the live session merely to test compilation: it would
claim the tray watcher and reserve another bar. `smoke-test.sh` uses two headless
labwc outputs, a private home/runtime directory and D-Bus session, synthetic state,
and mock action commands. It opens every control-center view and the calendar,
checks battery/tray geometry and independent hover revealers, fails on startup/UI
criticals, and cleans up its owned processes. Run once per
palette with the built dependency paths:

```sh
AGS=/nix/store/…-ags-2.3.0 \
LABWC=/nix/store/…-labwc \
SASS=/nix/store/…-dart-sass \
THEME_SCSS=/nix/store/…-themegen-cache-framework/.config/ags/theme-dark.scss \
bash hosts/framework/home/ags/smoke-test.sh
```

Set `KEEP_SMOKE_LOGS=1` to retain private fixture logs. This exercises widget
construction, not real Wi-Fi/audio changes, physical monitor hotplug, or live
StatusNotifierItem tray menus; those still require the post-activation checks
above. The harness also needs Bash, Python 3, `dbus-run-session`, and coreutils.

Upstream API references: [AGS v2.3](https://github.com/Aylur/ags/tree/v2.3.0),
[Astal](https://github.com/Aylur/astal).
