# SleepGuard

A minimal macOS menu-bar-less app + WidgetKit widget that toggles sleep
prevention (`IOPMAssertionCreateWithName`, the same mechanism `caffeinate`
uses) from Notification Center. No root/sudo required.

Not built as a Nix derivation: it needs codesigning with a real "Apple
Development" identity from the login keychain (App Sandbox + App Groups
entitlements require it), which isn't available inside the Nix build sandbox.
Instead it's built imperatively with `xcodegen` + `xcodebuild` and installed
straight to `/Applications`.

Build and install with:

```
just sleepguard-install
```

The launchd agent that keeps it running across reboots is declared in
`hosts/m5pro/home/sleepguard.nix` and activated via `just switch`.
