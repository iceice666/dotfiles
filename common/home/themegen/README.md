# Theming

This repo uses `themegen` to derive Material You and Base16 colors from each host wallpaper, then renders root-level plain templates before the Nix build starts.

Templates live under `themegen/` and are already relative to `$HOME`; there is no extra `home/` path segment.

## Pipeline

1. Each host chooses a wallpaper in its host module.
2. `just theme` renders `themegen/common/` and then `themegen/<host>/` into `.cache/themegen/<host>/` for the current platform host when the wallpaper or templates changed.
3. Host-specific templates overwrite common templates when their relative paths match.
4. `common/home/themegen/default.nix` recursively installs the generated cache into Home Manager.
5. On Framework, Home Manager wraps the generated GTK CSS into a named Nix GTK theme package under `share/themes` and switches between `Themegen` and `Themegen-dark`.

## File Map

- `themegen/common/`: shared Ghostty, fish, starship, Zed, and VSCodium theme templates.
- `themegen/framework/`: Linux-only GTK, Qt, fuzzel, Niri, and Eww bar templates. GTK templates become a standalone package on Framework.
- `themegen/m3air/`: macOS-only Equibop template.
- `common/home/themegen/default.nix`: Home Manager installer for generated concrete files.
- `pkgs/themegen/`: Rust CLI that extracts palette data and renders placeholders.

## Workflows

Generate concrete themes:

```sh
just theme
```

Run it on the platform that owns the host: macOS renders `m3air`, and Linux
renders `framework`.

Normal build and switch recipes run generation first and pass the generated cache into the flake:

```sh
just build
```

Generation is skipped when the host wallpaper and all `themegen/common/` plus `themegen/<host>/` templates match the last run. Input fingerprints live under `.cache/themegen/.state/`, outside the generated cache that Home Manager installs.

Direct Nix commands must pass the generated cache input explicitly:

```sh
nix build .#nixosConfigurations.framework.config.system.build.toplevel \
  --override-input themegen-cache path:$PWD/.cache/themegen/framework
```

Render and open an HTML preview for a wallpaper palette:

```sh
just theme-preview
just theme-preview ./assets/another-wallpaper.png
```

The generated file is written to `.cache/themegen/preview/index.html`.

## Editing

- Change shared templates in `themegen/common/`.
- Change host-only templates in `themegen/m3air/` or `themegen/framework/`.
- Add a new themed file by placing it at the final `$HOME`-relative target path under the right scope.
- Use direct `{{color.dark.primary}}`-style lookups in template bodies. Put derived colors in an optional leading `{{#themegen ... }}` header with `let local.name = ...` declarations, then reference them as `{{local.name}}`.
- Header helpers cover the current derived-color operations: `alpha`, `mix`, `lightness_add`, `tone`, `readable`, `readable_alpha`, `tone_alpha`, and `tone_readable`.
- Framework GTK templates should define the full Adwaita/libadwaita color token surface; `hosts/framework/home/gui.nix` adds the Adwaita base imports and packages the rendered CSS as `Themegen` / `Themegen-dark`.
- Framework Niri templates should render mode-specific snippets as `.config/niri/theme-{dark,light}.kdl`; the static Niri config includes `.config/niri/theme.kdl`, and darkman switches that symlink with the rest of the appearance files.

## Validation

For template or theme installer changes:

```sh
just theme
just build
just fmt
```

If flake wiring or shared modules changed too, also run:

```sh
just check
```
