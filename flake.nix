{
  description = "The entrypoint for the system";

  inputs = {
    self.submodules = true;

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      home-manager,
      nixpkgs,
      nixpkgs-unstable,
      treefmt-nix,
      sops-nix,
      ...
    }:
    let
      overlay = final: prev: {
        equibop-bin = final.callPackage ./pkgs/equibop-bin { };
        mise-bin = final.callPackage ./pkgs/mise-bin { };
        themegen = final.callPackage ./pkgs/themegen { };
        direnv = prev.direnv.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            for makefile in Makefile GNUmakefile; do
              if [ -f "$makefile" ]; then
                substituteInPlace "$makefile" --replace "-linkmode=external" ""
              fi
            done
          '';
        });
      };

      unstablePkgsFor =
        system:
        import nixpkgs-unstable {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
          overlays = [ overlay ];
        };

      treefmtEval =
        system: treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} (self + /treefmt.nix);
    in
    {
      formatter.aarch64-darwin = (treefmtEval "aarch64-darwin").config.build.wrapper;
      formatter.x86_64-linux = (treefmtEval "x86_64-linux").config.build.wrapper;

      darwinConfigurations."iceice666@m3air" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {
          inherit inputs self;
          username = "iceice666";
          homeDirectory = "/Users/iceice666";
          dotfiles = ./.;
          unstablePkgs = unstablePkgsFor "aarch64-darwin";
        };
        modules = [
          ./hosts/m3air/configuration
          sops-nix.darwinModules.sops
          home-manager.darwinModules.home-manager
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
          dotfiles = ./.;
          unstablePkgs = unstablePkgsFor "x86_64-linux";
        };
        modules = [
          ./hosts/framework/home
          sops-nix.homeManagerModules.sops
        ];
      };

      # Build with: sudo nixos-rebuild switch --flake .#server
      nixosConfigurations."homolab" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs self;
          username = "iceice666";
          homeDirectory = "/home/iceice666";
          dotfiles = ./.;
          unstablePkgs = unstablePkgsFor "x86_64-linux";
        };
        modules = [
          ./hosts/server/configuration
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          { nixpkgs.overlays = [ overlay ]; }
        ];
      };

    };
}
