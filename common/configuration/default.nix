{ pkgs, ... }:

{
  imports = [
  ];

  environment.systemPackages = import ./packages.nix { inherit pkgs; };

  fonts.packages = with pkgs; [ cascadia-code ];
}
