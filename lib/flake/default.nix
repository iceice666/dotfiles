{ inputs, dotfiles }:

let
  inherit (inputs)
    self
    nix-darwin
    home-manager
    nixpkgs
    nixpkgs-unstable
    treefmt-nix
    sops-nix
    ;

  overlay = import ./overlays {
    inherit inputs nixpkgs-unstable dotfiles;
  };

  pkgsLib = import ./pkgs.nix {
    inherit nixpkgs-unstable overlay;
  };

  inherit (pkgsLib) unstablePkgsFor;

  systems = import ./systems.nix;

  hosts = import ./hosts.nix { inherit inputs dotfiles; };

  mkHost = import ./mk-host.nix {
    inherit
      inputs
      self
      nixpkgs
      nix-darwin
      home-manager
      sops-nix
      overlay
      unstablePkgsFor
      dotfiles
      ;
  };

  hostConfigurations = builtins.listToAttrs (
    map (host: {
      name = host.name;
      value = mkHost host;
    }) hosts
  );

  nixosConfigurations = builtins.listToAttrs (
    map (host: {
      name = host.name;
      value = hostConfigurations.${host.name};
    }) (builtins.filter (host: host.kind == "nixos") hosts)
  );

  darwinConfigurations = builtins.listToAttrs (
    map (host: {
      name = host.name;
      value = hostConfigurations.${host.name};
    }) (builtins.filter (host: host.kind == "darwin") hosts)
  );

  homeConfigurations = builtins.listToAttrs (
    map (host: {
      name = host.name;
      value = hostConfigurations.${host.name};
    }) (builtins.filter (host: host.kind == "home-manager") hosts)
  );

  packages = builtins.listToAttrs (
    map (system: {
      name = system;
      value =
        let
          p = unstablePkgsFor system;
          isLinux = p.stdenv.hostPlatform.isLinux;
        in
        {
          inherit (p)
            themegen
            equibop-bin
            claude-code-bin
            oh-my-pi-bin
            zed-bin
            rime-frost
            rime-octagram-zh-hant-essay-bgw
            ;
        }
        // nixpkgs.lib.optionalAttrs (!isLinux) {
          inherit (p)
            utiluti
            default-browser
            ;
        }
        // nixpkgs.lib.optionalAttrs isLinux {
          inherit (p)
            blocky-bin
            cliproxyapi-bin
            framework-eww-state
            ;
        };
    }) systems
  );
in
{
  deploy = import ./deploy.nix {
    inherit
      inputs
      hostConfigurations
      hosts
      ;
  };

  checks = {
    x86_64-linux = { };
  };

  devShells = import ./dev-shells.nix { inherit unstablePkgsFor systems; };

  formatter = import ./formatters.nix {
    inherit
      self
      treefmt-nix
      unstablePkgsFor
      systems
      ;
  };

  inherit
    darwinConfigurations
    homeConfigurations
    nixosConfigurations
    packages
    ;
}
