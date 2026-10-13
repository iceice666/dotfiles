{
  pkgs,
  ghosttyFontSize ? 16,
  ...
}:
{
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty;
    enableFishIntegration = true;
    settings = {
      font-family = "JetBrainsMono Nerd Font Mono";
      font-size = ghosttyFontSize;
      background-opacity = 0.75;
      background-blur = 20;
      macos-option-as-alt = true;
      window-tab-bar-position = "left";
      window-show-tab-bar = "always";
      theme = "light:themegen-light,dark:themegen-dark";
      keybind = [
        "super+c=copy_to_clipboard"
        "super+v=paste_from_clipboard"
      ];
    };
  };
}
