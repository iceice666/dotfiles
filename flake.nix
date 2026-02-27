{
  description = "The entrypoint for the system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { self, nix-darwin, home-manager, nixpkgs, ... }:
  let
    overlay = final: prev: {
      equibop-bin = final.callPackage ./pkgs/equibop-bin { };
      aerospace-swipe = final.callPackage ./pkgs/aerospace-swipe { };
    };
  in
  {
    darwinConfigurations."iceice666@m3air" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {
        inherit inputs self;
        username      = "iceice666";
        homeDirectory = "/Users/iceice666";
      };
      modules = [
        home-manager.darwinModules.home-manager
        ./hosts/m3air/configuration
        { nixpkgs.overlays = [ overlay ]; }
      ];
    };

    # Build with: home-manager switch --flake .#iceice666@framework
    homeConfigurations."iceice666@framework" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = [ overlay ];
      };
      extraSpecialArgs = {
        inherit inputs self;
        username = "iceice666";
        homeDirectory = "/home/iceice666";
      };
      modules = [ ./hosts/framework/home ];
    };

    # Build with: sudo nixos-rebuild switch --flake .#server
    nixosConfigurations."homolab" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs self;
        username      = "root";
        homeDirectory = "/root";
      };
      modules = [
        home-manager.nixosModules.home-manager
        ./hosts/server/configuration
        { nixpkgs.overlays = [ overlay ]; }
      ];
    };

  };
}
