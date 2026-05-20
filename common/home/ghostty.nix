{
  ghosttyFontSize ? 16,
  ...
}:

{
  home.file.".config/ghostty/config".text = builtins.concatStringsSep "\n" [
    "font-size = ${toString ghosttyFontSize}"
    "background-opacity = 0.75"
    "background-opacity-cells = true"
    "background-blur = true" # implies background-blur = true on non-macOS platforms.
    "theme = light:themegen-light,dark:themegen-dark"
    "keybind = super+c=copy_to_clipboard:mixed"
    "keybind = super+v=paste_from_clipboard"
  ];
}
