# Theming

This repo uses `themegen` to derive a Material You palette and Base16 colors from a host wallpaper, then render app-specific theme files during the Home Manager build.

The current setup keeps the heavy lifting in Rust and uses Nix to generate the theme source templates. That split keeps image analysis and color math in `pkgs/themegen/` while letting the repo share repeated theme expressions across apps.

## Pipeline

1. Each host chooses a wallpaper and passes it as `desktopWallpaper` through `_module.args`.
2. `common/home/themegen/default.nix` auto-discovers every module in `common/home/themegen/templates/` except `lib.nix`.
3. Each template module declares the files it renders or copies and the `home.file` targets that should receive them.
4. The shared module runs `themegen render` with the wallpaper, `tonal-spot`, `--base16-contrast 0.3`, and `--base16-mode follow-palette`, then installs the generated outputs into Home Manager.

Relevant entrypoints:

- `hosts/m3air/home/default.nix`
- `hosts/framework/home/default.nix`
- `common/home/themegen/default.nix`
- `pkgs/themegen/`

## File Map

- `common/home/themegen/default.nix`: build-time entrypoint that renders and installs all generated theme files.
- `common/home/themegen/templates/lib.nix`: shared helpers for template placeholders, color pipelines, syntax colors, terminal palettes, and module metadata constructors.
- `common/home/themegen/templates/ghostty.nix`: Ghostty dark and light theme sources.
- `common/home/themegen/templates/equibop.nix`: Equibop Midnight CSS theme with automatic Discord light and dark mode switching.
- `common/home/themegen/templates/terminal-sequences.nix`: fish startup script that applies the terminal palette and follows desktop dark/light mode.
- `common/home/themegen/templates/opencode.nix`: Opencode theme JSON.
- `common/home/themegen/templates/starship.nix`: starship palette TOML.
- `common/home/themegen/templates/zed.nix`: Zed theme JSON for both appearances.
- `pkgs/themegen/`: Rust CLI that extracts the seed color from an image, generates Material/Base16 palettes, and renders template placeholders.

## How To Change It

Change the wallpaper:

- Update `desktopWallpaper` in the relevant host file.

Change shared terminal or syntax semantics:

- Edit `common/home/themegen/templates/lib.nix`.
- Use `terminal` for ANSI and surface mappings shared by Ghostty, fish, and Zed.
- Use `syntax` for reusable syntax families shared by Zed and Opencode.
- Prefer the descriptive helper names when authoring templates: `placeholder`, `renderPipeline`, `templateExpression`, `renderMix`, and `renderAlpha`.

Change one app only:

- Edit the matching file in `common/home/themegen/templates/`.
- Keep app-specific key mapping local there and prefer reusing values from `lib.nix` instead of rebuilding color pipelines inline.

Add a new themed app:

1. Add a new module under `common/home/themegen/templates/`.
2. Return a `generated` list describing rendered or copied files.
3. Return a `homeFiles` list describing where those generated files should be installed.

Minimal shape:

```nix
{ lib, pkgs }:

let
  theme = import ./lib.nix { inherit lib; };
  myTheme = pkgs.writeText "themegen-my-app" ''
    accent = ${theme.placeholder theme.color.dark.primary}
  '';
in
{
  generated = [
    (theme.mkRenderedFile {
      template = myTheme;
      output = "my-app/theme.conf";
    })
  ];

  homeFiles = [
    (theme.mkHomeFile {
      target = ".config/my-app/theme.conf";
      source = "my-app/theme.conf";
    })
  ];
}
```

Nothing else needs updating. New template modules are discovered automatically.

Preview a wallpaper quickly:

```sh
just themegen-preview
just themegen-preview ./assets/another-wallpaper.png
```

Without an argument, the recipe previews the current host wallpaper.

## Validation

For changes under `common/home/themegen/default.nix` or `common/home/themegen/templates/`:

- Run `just fmt`.
- Dry-build `m3air`.
- Validate `framework` as well, since it consumes the same shared Home Manager module.

Useful commands:

```sh
just fmt
sudo darwin-rebuild build --flake .#iceice666@m3air
home-manager build --flake .#iceice666@framework
```

If you change `pkgs/themegen/` or flake wiring too, also run:

```sh
just check
```

## Design Notes

- Nix owns template assembly and reuse.
- Rust `themegen` owns image-derived palette extraction, color-space transforms, and placeholder evaluation.
- Shared semantic layers belong in `common/home/themegen/templates/lib.nix`.
- App files should mostly map semantic values into the target app's schema.

That split is intentional: it reduces duplication in the version-controlled theme sources without moving complex image and color math into Nix.
