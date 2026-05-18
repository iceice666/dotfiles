# Theming

This repo uses `themegen` to derive Material You and Base16 colors from each host wallpaper, then renders root-level plain templates before the Nix build starts.

Templates live under `themegen/` and are already relative to `$HOME`; there is no extra `home/` path segment.

## Pipeline

1. Each host chooses a wallpaper in its host module.
2. `just themegen-generate <host>` renders `themegen/common/` and then `themegen/<host>/` into `.cache/themegen/<host>/` when the wallpaper or templates changed.
3. Host-specific templates overwrite common templates when their relative paths match.
4. `common/home/themegen/default.nix` recursively installs the generated cache into Home Manager.

## File Map

- `themegen/common/`: shared Ghostty, fish, starship, Zed, and VSCodium theme templates.
- `themegen/framework/`: Linux-only GTK, Qt, fuzzel, and framework-bar templates.
- `themegen/m3air/`: macOS-only Equibop template.
- `common/home/themegen/default.nix`: Home Manager installer for generated concrete files.
- `pkgs/themegen/`: Rust CLI that extracts palette data and renders placeholders.

## Workflows

Generate concrete themes:

```sh
just themegen-generate m3air
just themegen-generate framework
```

Normal build and switch recipes run generation first and pass the generated cache into the flake:

```sh
just m3air-build
just framework-build
```

Generation is skipped when the host wallpaper and all `themegen/common/` plus `themegen/<host>/` templates match the last run. Input fingerprints live under `.cache/themegen/.state/`, outside the generated cache that Home Manager installs.

Direct Nix commands must pass the generated cache input explicitly:

```sh
nix build .#nixosConfigurations.framework.config.system.build.toplevel \
  --override-input themegen-cache path:$PWD/.cache/themegen/framework
```

Render and open an HTML preview for a wallpaper palette:

```sh
just themegen-preview
just themegen-preview ./assets/another-wallpaper.png
```

The generated file is written to `.cache/themegen/preview/index.html`.

## Editing

- Change shared templates in `themegen/common/`.
- Change host-only templates in `themegen/m3air/` or `themegen/framework/`.
- Add a new themed file by placing it at the final `$HOME`-relative target path under the right scope.
- Use `{{...}}` placeholders supported by `themegen render` for wallpaper-derived colors.

## Validation

For template or theme installer changes:

```sh
just themegen-generate framework
just framework-build
just fmt
```

If flake wiring or shared modules changed too, also run:

```sh
just check
```
