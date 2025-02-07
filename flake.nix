{
  description = "My flake config";

  inputs = {
    ### packages
    master.url = "github:nixos/nixpkgs/master";
    stable.url = "github:nixos/nixpkgs/release-24.11";
    unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    darwin.url = "github:lnl7/nix-darwin";
    home.url = "github:nix-community/home-manager";

    ### other
    # upgrade with
    #   nix flake lock --update-input nixpkgs-firefox-darwin
    nixpkgs-firefox-darwin.url = "github:bandithedoge/nixpkgs-firefox-darwin";

    darwin.inputs.nixpkgs.follows = "nixpkgs";
    home.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    nixpkgs,
    darwin,
    home,
    unstable,
    ...
  }: {
    darwinConfigurations."MacBookM3Air" = let
      hostname = "MacBookM3Air";
      username = "iceice666";
      useremail = "iceice666@outlook.com";
      system = "aarch64-darwin";
      homeDirectory = "/Users/${username}";

      specialArgs = {
        inherit inputs hostname username useremail system homeDirectory;
        pkgs-unstable = import unstable {
          inherit system;
        };
      };
    in
      darwin.lib.darwinSystem {
        inherit system specialArgs;

        modules = [
          ./common/default.nix
          ./hosts/MacBookM3Air/default.nix
          home.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = specialArgs;
            home-manager.users.${username} = import ./home;
          }
        ];
      };
    formatter."aarch64-darwin" = nixpkgs.legacyPackages."aarch64-darwin".alejandra;
  };
}
