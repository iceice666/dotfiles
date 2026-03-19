{ dotfiles, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./system.nix
    ./networking.nix
    ./secrets.nix
    ./services
    ./user.nix
    (dotfiles + /common/configuration)
  ];

  system.stateVersion = "25.11";
}
