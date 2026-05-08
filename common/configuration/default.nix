{ pkgs, unstablePkgs, ... }:

{
  imports = [
  ];

  environment.systemPackages = (import ./packages.nix { inherit pkgs; }) ++ [
    unstablePkgs.agent-browser
  ];

  fonts.packages = with pkgs; [ cascadia-code ];
}
