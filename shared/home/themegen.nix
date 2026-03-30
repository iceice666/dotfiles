{ pkgs, dotfiles, ... }:

let
  wallpaper = dotfiles + /assets/desktop_wallpaper.png;
  templates = dotfiles + /shared/themegen/templates;
  generated =
    pkgs.runCommandLocal "themegen-themes"
      {
        nativeBuildInputs = [ pkgs.themegen ];
      }
      ''
        mkdir -p "$out/ghostty/themes"
        mkdir -p "$out/opencode/themes"
        mkdir -p "$out/zed/themes"
        mkdir -p "$out/fish/conf.d"

        themegen "${wallpaper}" --type scheme-tonal-spot --template "${templates}/ghostty-dark" > "$out/ghostty/themes/themegen-dark"
        themegen "${wallpaper}" --type scheme-tonal-spot --template "${templates}/ghostty-light" > "$out/ghostty/themes/themegen-light"
        themegen "${wallpaper}" --type scheme-tonal-spot --template "${templates}/opencode-colors.json" > "$out/opencode/themes/themegen.json"
        themegen "${wallpaper}" --type scheme-tonal-spot --template "${templates}/zed-colors.json" > "$out/zed/themes/themegen.json"
        themegen "${wallpaper}" --type scheme-tonal-spot --template "${templates}/starship.toml" > "$out/starship.toml"
        themegen "${wallpaper}" --type scheme-tonal-spot --template "${templates}/terminal-sequences.fish" > "$out/fish/conf.d/themegen-terminal-sequences.fish"
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
