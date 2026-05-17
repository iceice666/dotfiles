{ pkgs, unstablePkgs, ... }:

{
  imports = [
  ];

  nix.package = pkgs.lixPackageSets.stable.lix;

  environment.systemPackages = (import ./packages.nix { inherit pkgs; }) ++ [
    unstablePkgs.codex
    unstablePkgs.agent-browser
  ];

  fonts.packages = with pkgs; [ cascadia-code ];
}
