{ pkgs, ... }:

{
  imports = [
  ];

  environment.systemPackages = import ./packages.nix { inherit pkgs; };
}
