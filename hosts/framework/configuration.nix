{ pkgs, inputs, username, homeDirectory, ... }:

{
  imports = [
    ../../user/packages.nix
    ../../user/default.nix
    ../../user/desktop
    ./home.nix
  ];
}
