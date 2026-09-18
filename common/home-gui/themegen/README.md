# Theming

This repo uses `themegen` to derive Material You and Base16 colors from each host wallpaper, then renders root-level plain templates in a Nix derivation.

Templates live under `themegen/` and are already relative to `$HOME`; there is no extra `home/` path segment.

## Pipeline

1. Each host chooses a wallpaper in its host Home Manager module.
2. `common/home-gui/themegen/default.nix` builds a host-specific `themegen-cache-<host>` derivation from the wallpaper plus `themegen/common/` and `themegen/<host>/` templates.
3. Host-specific templates overwrite common templates when their relative paths match.
4. The same module installs the derivation outputs into Home Manager using the target list known at evaluation time.
5. On Framework, Home Manager wraps the generated GTK CSS into a named Nix GTK theme package under `share/themes` and switches between `Themegen` and `Themegen-dark`.

## File Map

- `themegen/common/`: shared Kitty, fish, starship, Zed, VSCodium, and Pi theme templates.
  Kitty palettes render to `.config/kitty/{dark,light}-theme.auto.conf`, preserving
  the terminal, cursor, selection, and 16 ANSI colors. `no-preference-theme.auto.conf`
  includes the light palette. Kitty 0.38+ follows the OS color scheme automatically
  (macOS appearance / Framework's GNOME Settings portal, updated by darkman); no theme-switch hook
  or `kitten themes` invocation is needed. See [Kitty automatic themes](https://sw.kovidgoyal.net/kitty/kittens/themes/#auto-color-scheme).
  Shared behavior is managed by `common/home-gui/kitty.nix`, with host-specific
  `kittyFontSize`. Background opacity remains 0.75, with blur radius 20 where
  supported. Unlike Ghostty's all-cell opacity, Kitty only makes the default
  terminal background transparent; other cell backgrounds remain opaque.
  The Pi pair renders to `.pi/agent/themes/themegen-{dark,light}.json`; Pi picks
  them up through global theme auto-discovery, and `common/home-base/pi.nix`
  selects `themegen-light/themegen-dark` whenever those files are installed.
- `themegen/framework/`: Linux-only GTK, Qt, fuzzel, Niri, and Eww bar templates. GTK templates become a standalone package on Framework.
- `themegen/m5pro/`: macOS-only Equibop template.
- `common/home-gui/themegen/default.nix`: Nix derivation builder and Home Manager installer for generated concrete files.
- `pkgs/themegen/`: Rust CLI that extracts palette data and renders placeholders.

## Workflows

Normal build and switch recipes build the theme derivation automatically:

```sh
just build
just switch
```

Render a local cache for quick inspection outside a system build:

```sh
just theme
```

The local cache is written to `.cache/themegen/<host>/`; it is not used by Home Manager activation.

Render and open an HTML preview for a wallpaper palette:

```sh
just theme-preview
just theme-preview ./assets/another-wallpaper.png
```

The generated preview is written to `.cache/themegen/preview/index.html`.

## Editing

- Change shared templates in `themegen/common/`.
- Change host-only templates in `themegen/m5pro/` or `themegen/framework/`.
- Add a new themed file by placing it at the final `$HOME`-relative target path under the right scope.
- Use direct `{{color.dark.primary}}`-style lookups in template bodies. Put derived colors in an optional leading `{{#themegen ... }}` header with `let local.name = ...` declarations, then reference them as `{{local.name}}`.
- Header helpers cover the current derived-color operations: `alpha`, `mix`, `lightness_add`, `tone`, `readable`, `readable_alpha`, `tone_alpha`, and `tone_readable`.
- Framework GTK templates should define the full Adwaita/libadwaita color token surface; `hosts/framework/home/gui.nix` adds the Adwaita base imports and packages the rendered CSS as `Themegen` / `Themegen-dark`.
- Framework Niri templates should render mode-specific snippets as `.config/niri/theme-{dark,light}.kdl`; the static Niri config includes `.config/niri/theme.kdl`, and darkman switches that symlink with the rest of the appearance files.

## Validation

For template or theme installer changes:

```sh
just build
just fmt
```

If flake wiring or shared modules changed too, also run:

```sh
just check
```
