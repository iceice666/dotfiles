{ pkgs, unstablePkgs, ... }:

{
  imports = [
  ];

  environment.systemPackages = (import ./packages.nix { inherit pkgs; }) ++ [
    unstablePkgs.codex
    unstablePkgs.agent-browser
  ];

  fonts.packages = with pkgs; [ cascadia-code ];
}
