{ pkgs, ... }:

{
  programs.sketchybar = {
    enable = true;
    service.enable = true;

    extraPackages = [
      pkgs.jq
      pkgs.bc
      pkgs.sketchybar-app-font
      pkgs.aerospace
    ];

    config = {
      source = ../../../sketchybar;
      recursive = true;
    };
  };
}
