{
  pkgs,
  dotfiles,
  desktopWallpaper,
  ...
}:

let
  templates = dotfiles + /shared/themegen/templates;
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
          --render "${templates}/ghostty-dark=$out/ghostty/themes/themegen-dark" \
          --render "${templates}/ghostty-light=$out/ghostty/themes/themegen-light" \
          --render "${templates}/opencode-colors.json=$out/opencode/themes/themegen.json" \
          --render "${templates}/zed-themes.jsonc=$out/zed/themes/themegen.json" \
          --render "${templates}/starship.toml=$out/starship.toml" \
          --render "${templates}/terminal-sequences.fish=$out/fish/conf.d/themegen-terminal-sequences.fish"
      '';
in
{
  home.packages = [ pkgs.themegen ];

  home.file = {
    ".config/fish/conf.d/themegen-terminal-sequences.fish".source =
      "${generated}/fish/conf.d/themegen-terminal-sequences.fish";
    ".config/ghostty/config".text = ''
      theme = light:themegen-light,dark:themegen-dark
    '';
    ".config/ghostty/themes/themegen-dark".source = "${generated}/ghostty/themes/themegen-dark";
    ".config/ghostty/themes/themegen-light".source = "${generated}/ghostty/themes/themegen-light";
    ".config/opencode/themes/themegen.json".source = "${generated}/opencode/themes/themegen.json";
    ".config/starship.toml".source = "${generated}/starship.toml";
    ".config/zed/themes/themegen.json".source = "${generated}/zed/themes/themegen.json";
  };

  programs.opencode.settings.theme = "themegen";
}
