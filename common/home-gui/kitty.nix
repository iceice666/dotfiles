{
  kittyFontSize ? 16,
  ...
}:
{
  programs.kitty = {
    enable = true;
    shellIntegration.enableFishIntegration = true;
    settings = {
      font_family = "Sarasa Term TC";
      font_size = kittyFontSize;
      background_opacity = 0.75;
      background_blur = 20;
      macos_option_as_alt = "both";
      tab_title_template = "{index}  {tab.active_wd.rsplit('/', 1)[-1] or '/'} · {tab.active_exe}";
    };
    keybindings = {
      "super+c" = "copy_or_noop";
      "super+v" = "paste_from_clipboard";
    };
  };
}
