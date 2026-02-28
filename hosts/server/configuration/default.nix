{
  pkgs,
  inputs,
  self,
  username,
  homeDirectory,
  ...
}:

{
  imports = [ ../../../common/system ];

  nix.settings.experimental-features = "nix-command flakes";

  programs.fish.enable = true;

  users.users.${username}.shell = pkgs.fish;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit
        inputs
        self
        username
        homeDirectory
        ;
    };
    users.${username} = {
      imports = [ ../home ];
    };
  };

  # Add ./hardware-configuration.nix when provisioning the actual server:
  # imports = [ ./hardware-configuration.nix ];

  system.stateVersion = "25.11";

  # Adjust to the actual server architecture (x86_64-linux or aarch64-linux)
  nixpkgs.hostPlatform = "x86_64-linux";
}
