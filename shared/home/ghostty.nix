{ ... }:

{
  home.file.".config/ghostty/config".text = builtins.concatStringsSep "\n" [
    "font-size = 16"
    "background-opacity = 0.75"
    "theme = light:themegen-light,dark:themegen-dark"
  ];
}
