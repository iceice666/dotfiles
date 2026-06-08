{ pkgs, ... }:

{
  nix.package = pkgs.lixPackageSets.stable.lix;
  nixpkgs.config.allowUnfree = true;
  fonts.packages = with pkgs; [ cascadia-code ];
  programs.fish.enable = true;
}
