{ ... }:

{
  home.file.".config/ghostty/config".text = builtins.concatStringsSep "\n" [
    "font-size = 16"
    "background-opacity = 0.75"
    "background-opacity-cells = true"
    "background-blur = true" # implies background-blur = true on non-macOS platforms.
    "theme = light:themegen-light,dark:themegen-dark"
  ];
}
