{
  pkgs,
  lib,
  dotfiles,
  desktopWallpaper,
  ...
}:

let
  templates = import (dotfiles + /shared/home/themegen/templates) {
    inherit lib pkgs;
  };
  vscodeExtensionManifest = builtins.toFile "themegen-vscode-package.json" (
    builtins.toJSON {
      name = "themegen";
      publisher = "themegen";
      displayName = "Themegen";
      version = "0.0.1";
      engines.vscode = "^1.74.0";
      categories = [ "Themes" ];
      contributes.themes = [
        {
          label = "Themegen Dark";
          uiTheme = "vs-dark";
          path = "./themes/themegen-dark-color-theme.json";
        }
        {
          label = "Themegen Light";
          uiTheme = "vs";
          path = "./themes/themegen-light-color-theme.json";
        }
      ];
    }
    + "\n"
  );
  generated =
    pkgs.runCommandLocal "themegen-themes"
      {
        nativeBuildInputs = [ pkgs.themegen ];
      }
      ''
        themegen render \
          --image "${desktopWallpaper}" \
          --scheme tonal-spot \
          --base16-contrast 0.3 \
          --base16-mode follow-palette \
          --render "${templates.ghosttyDark}=$out/ghostty/themes/themegen-dark" \
          --render "${templates.ghosttyLight}=$out/ghostty/themes/themegen-light" \
          --render "${templates.opencodeColors}=$out/opencode/themes/themegen.json" \
          --render "${templates.vscodeDark}=$out/vscode/extensions/themegen.themegen/themes/themegen-dark-color-theme.json" \
          --render "${templates.vscodeLight}=$out/vscode/extensions/themegen.themegen/themes/themegen-light-color-theme.json" \
          --render "${templates.zedThemes}=$out/zed/themes/themegen.json" \
          --render "${templates.starship}=$out/starship.toml" \
          --render "${templates.terminalSequences}=$out/fish/conf.d/themegen-terminal-sequences.fish"

        install -Dm644 "${vscodeExtensionManifest}" "$out/vscode/extensions/themegen.themegen/package.json"
      '';
in
{
  home.packages = [ pkgs.themegen ];

  home.file = {
    ".config/fish/conf.d/themegen-terminal-sequences.fish".source =
      "${generated}/fish/conf.d/themegen-terminal-sequences.fish";
    ".config/ghostty/themes/themegen-dark".source = "${generated}/ghostty/themes/themegen-dark";
    ".config/ghostty/themes/themegen-light".source = "${generated}/ghostty/themes/themegen-light";
    ".config/opencode/themes/themegen.json".source = "${generated}/opencode/themes/themegen.json";
    ".config/starship.toml".source = "${generated}/starship.toml";
    ".vscode-oss/extensions/themegen.themegen".source =
      "${generated}/vscode/extensions/themegen.themegen";
    ".config/zed/themes/themegen.json".source = "${generated}/zed/themes/themegen.json";
  };

  programs.opencode.settings.theme = "themegen";
}
