{
  description = "The entrypoint for the system";

  inputs = {
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
      overlay =
        final: prev:
        let
          unstablePkgs = import nixpkgs-unstable {
            system = prev.stdenv.hostPlatform.system;
            config = {
              allowUnfree = true;
              cudaSupport = true;
            };
          };
        in
        {
          equibop-bin = final.callPackage ./pkgs/equibop-bin { };
          zed-editor-unstable = unstablePkgs.zed-editor;

          woodpecker-cli-unstable = unstablePkgs.woodpecker-cli;
          woodpecker-agent-unstable = unstablePkgs.woodpecker-agent;
          woodpecker-server-unstable = unstablePkgs.woodpecker-server;
          ollama-unstable = unstablePkgs.ollama;
          codex-unstable = unstablePkgs.codex;
          opencode-unstable = unstablePkgs.opencode;
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
