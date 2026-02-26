{ pkgs, lib, ... }:

{
  imports = [ ./zed.nix ];

  home.packages = with pkgs; [
    opencode
    antigravity
  ];
}
