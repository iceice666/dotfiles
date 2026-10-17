# SleepGuard

A minimal macOS menu-bar-less app + WidgetKit widget that toggles
`pmset -a disablesleep` from Notification Center. Unlike an idle-sleep
assertion (`caffeinate -i`), this disables system sleep entirely, including
lid-close sleep; display sleep still follows the normal `displaysleep` setting.

The sandboxed widget only flips a shared App Group flag and wakes the app. The
unsandboxed app runs `sudo -n /usr/bin/pmset -a disablesleep 0|1`, which works
through the narrow NOPASSWD rule in `hosts/m5pro/configuration/system-defaults.nix`.
On launch (login), the app re-applies the stored widget state, so the widget is
the source of truth and overrides manual `pmset disablesleep` changes.

Not built as a Nix derivation: it needs codesigning with a real "Apple
Development" identity from the login keychain (App Groups entitlements require
it), which isn't available inside the Nix build sandbox. Instead it's built
imperatively with `xcodegen` + `xcodebuild` and installed straight to
`/Applications`.

Build and install with:

```
just sleepguard-install
```

The launchd agent that keeps it running across reboots is declared in
`hosts/m5pro/home/sleepguard.nix` and activated via `just switch`.
App logs: `log stream --predicate 'subsystem == "com.iceice666.sleepguard"'`.
