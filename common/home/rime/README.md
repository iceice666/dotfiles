# Rime

Shared Rime data is managed by `common/home/rime/default.nix`.

The module copies packaged Rime data into the writable user data directory on each host:

- macOS Squirrel (`squirrel-app` Homebrew cask): `~/Library/Rime`
- Linux Fcitx5 Rime: `~/.local/share/fcitx5/rime`

On Linux, Home Manager starts the Fcitx5 daemon for the graphical session, enables
the Wayland frontend, and installs the GTK bridge. Framework imports the Fcitx5
session variables into user systemd and dbus so apps launched from Niri,
portals, and desktop services can reach the input method.

Managed data:

- `pkgs.rime-frost`: Frost schema, dictionaries, Lua helpers, and OpenCC configs.
- `pkgs.rime-octagram-zh-hant-essay-bgw`: Traditional Chinese octagram grammar model.
- `default.custom.yaml`: restricts the schema list to `rime_frost`.
- `rime_frost.custom.yaml`: enables Traditional Chinese by default, uses `s2tw.json`, enables the user dictionary, and enables contextual suggestions with `zh-hant-t-essay-bgw`.

After switching, redeploy Rime from the input method menu if the frontend does not pick up the new files automatically.
