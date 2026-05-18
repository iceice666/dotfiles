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

    themegen-cache = {
      url = "path:./common/home/themegen/empty-cache";
      flake = false;
    };

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
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
        inherit (prev.lixPackageSets.stable)
          colmena
          nix-eval-jobs
          nix-fast-build
          nixpkgs-review
          ;

        codex-cli-bin = final.callPackage ./pkgs/codex-cli-bin { };
        default-browser = final.callPackage ./pkgs/default-browser { };
        equibop-bin = final.callPackage ./pkgs/equibop-bin { };
        framework-bar = final.callPackage ./pkgs/framework-bar { };
        zen-bin =
          if final.stdenv.hostPlatform.isLinux then
            final.wrapFirefox
              (inputs."zen-browser".packages.${final.system}.zen-browser-unwrapped
                or inputs."zen-browser".packages.${final.system}.default
              )
              {
                pname = "zen-bin";
                applicationName = "zen";
              }
          else
            final.callPackage ./pkgs/zen-bin { };
        themegen = final.callPackage ./pkgs/themegen { };
        utiluti = final.callPackage ./pkgs/utiluti { };
        zed-bin = final.callPackage ./pkgs/zed-bin { };
        linux_zen_7_0 = prev.linux_zen.override {
          argsOverride = rec {
            version = "7.0.9";
            suffix = "zen1";
            modDirVersion = final.lib.versions.pad 3 "${version}-${suffix}";
            structuredExtraConfig = builtins.removeAttrs prev.linux_zen.structuredExtraConfig [
              "PREEMPT_VOLUNTARY"
            ];
            src = final.fetchFromGitHub {
              owner = "zen-kernel";
              repo = "zen-kernel";
              rev = "v${version}-${suffix}";
              sha256 = "1fm1v1ghhls6kvfn6mdzcsq8rmng428ws329xb6ry1j3ax3apvmy";
            };
          };
        };
        linuxPackages_zen_7_0 = final.linuxPackagesFor final.linux_zen_7_0;
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

      devShellFor =
        system:
        let
          pkgs = unstablePkgsFor system;
          linuxLibraries = with pkgs; [
            fontconfig
            freetype
            libGL
            libxkbcommon
            vulkan-loader
            wayland
          ];
        in
        pkgs.mkShell {
          packages =
            with pkgs;
            [
              cargo
              clippy
              pkg-config
              rust-analyzer
              rustc
              rustfmt
            ]
            ++ lib.optionals stdenv.isLinux linuxLibraries;

          LD_LIBRARY_PATH = pkgs.lib.optionalString pkgs.stdenv.isLinux (
            pkgs.lib.makeLibraryPath linuxLibraries
          );
        };

      treefmtEval =
        system: treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} (self + /treefmt.nix);
    in
    {
      devShells.aarch64-darwin.default = devShellFor "aarch64-darwin";
      devShells.x86_64-linux.default = devShellFor "x86_64-linux";

      formatter.aarch64-darwin = (treefmtEval "aarch64-darwin").config.build.wrapper;
      formatter.x86_64-linux = (treefmtEval "x86_64-linux").config.build.wrapper;

      darwinConfigurations."iceice666@m3air" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {
          inherit inputs self;
          username = "iceice666";
          homeDirectory = "/Users/iceice666";
          dotfiles = ./.;
          themegenCache = inputs."themegen-cache";
          unstablePkgs = unstablePkgsFor "aarch64-darwin";
        };
        modules = [
          ./hosts/m3air/configuration
          sops-nix.darwinModules.sops
          home-manager.darwinModules.home-manager
          { nixpkgs.overlays = [ overlay ]; }
        ];
      };

      nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs self;
          username = "iceice666";
          homeDirectory = "/home/iceice666";
          dotfiles = ./.;
          themegenCache = inputs."themegen-cache";
          unstablePkgs = unstablePkgsFor "x86_64-linux";
        };
        modules = [
          ./hosts/framework/configuration
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          { nixpkgs.overlays = [ overlay ]; }
        ];
      };

      # Legacy standalone Home Manager output; Framework normally uses nixosConfigurations.framework.
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
          themegenCache = inputs."themegen-cache";
          unstablePkgs = unstablePkgsFor "x86_64-linux";
        };
        modules = [
          ./hosts/framework/home
          sops-nix.homeManagerModules.sops
        ];
      };

    };
}
