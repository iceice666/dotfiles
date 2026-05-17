{ pkgs, ... }:

{
  nix.package = pkgs.lixPackageSets.stable.lix;

  fonts.packages = with pkgs; [ cascadia-code ];
}
