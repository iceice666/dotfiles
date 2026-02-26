{ pkgs, inputs, username, homeDirectory, ... }:

{
  imports = [
    ../../../common/home/packages.nix
    ../../../common/home
    ../../../common/home/desktop
    ./host.nix
  ];
}
