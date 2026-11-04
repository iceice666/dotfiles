# m5pro

Apple Silicon macOS managed by `darwinConfigurations.m5pro` (nix-darwin +
Home Manager). `just build` / `just switch` on macOS target this host.

- `configuration/` — `default.nix`, `system-defaults.nix`.
- `home/appearance.nix` — builds and launches the Swift appearance scheduler (`pkgs/appearance-scheduler`).
- `home/default-apps.nix` — uses `default-browser` and `utiluti` to manage default browser and editor associations.
- `home/sleepguard.nix`, `home/karabiner.nix`, `home/wallpaper.nix` — host-specific desktop settings.
- `wallpaper.jpg` — symlink into `assets/`, used by `just theme` / `just theme-preview`.

Helpers:

```sh
just m5pro-homebrew    # install Homebrew (first-time setup)
just m5pro-activate    # reapply macOS settings without a full rebuild
```

## Garbage collection and App Management

`just gc` runs `scripts/nix-gc`. macOS App Management blocks deleting a
`/nix/store` `.app` tagged with `com.apple.macl` (it was launched from the
store). When GC aborts on such a path after dropping its database row, the
script removes only that now-invalid path with `/bin/rm` and retries. The
terminal running it needs App Management permission.

To avoid new tags, launch only the copied `~/Applications/Home Manager Apps`
bundles: activation unregisters store bundles from Launch Services, and
Playwright uses the copied Helium.
