{
  lib,
  pkgs,
  unstablePkgs,
  dotfiles,
  homeDirectory,
  ...
}:

let
  wallpaper = dotfiles + /assets/desktop_wallpaper.png;
  templates = dotfiles + /shared/matugen-themes/templates;
  matugenConfig = ''
    [config]
    fallback_color = "#4c6fff"
    padding = 60

    [templates.ghostty]
    input_path = '${templates}/ghostty'
    output_path = '${homeDirectory}/.config/ghostty/themes/matugen'

    [templates.btop]
    input_path = '${templates}/btop.theme'
    output_path = '${homeDirectory}/.config/btop/themes/matugen.theme'

    [templates.opencode]
    input_path = '${templates}/opencode-colors.json'
    output_path = '${homeDirectory}/.config/opencode/themes/matugen.json'

    [templates.zed]
    input_path = '${templates}/zed-colors.json'
    output_path = '${homeDirectory}/.config/zed/themes/matugen.json'
  '';
  matugenConfigFile = pkgs.writeText "matugen-config.toml" matugenConfig;
in
{
  home.file.".config/matugen/config.toml".text = matugenConfig;

  home.file.".config/ghostty/config".text = ''
    config-file = ~/.config/ghostty/themes/matugen
  '';

  home.file.".config/btop/btop.conf".text = ''
    color_theme = "matugen.theme"
    theme_background = False
    truecolor = True
  '';

  programs.opencode.settings.theme = "matugen";

  home.activation.generateMatugenThemes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.config/ghostty/themes"
    $DRY_RUN_CMD mkdir -p "$HOME/.config/btop/themes"
    $DRY_RUN_CMD mkdir -p "$HOME/.config/opencode/themes"
    $DRY_RUN_CMD mkdir -p "$HOME/.config/zed/themes"

    if [ -f "${wallpaper}" ]; then
      $DRY_RUN_CMD ${unstablePkgs.matugen}/bin/matugen image -c "${matugenConfigFile}" "${wallpaper}"
    else
      echo "matugen source image not found: ${wallpaper}" >&2
    fi
  '';
}
