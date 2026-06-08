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

  overlay = import ./overlay.nix {
    inherit inputs nixpkgs-unstable dotfiles;
  };

  pkgsLib = import ./pkgs.nix {
    inherit nixpkgs-unstable overlay;
  };

  inherit (pkgsLib) unstablePkgsFor;

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
in
{
  deploy = import ./deploy.nix {
    inherit inputs nixosConfigurations hosts;
  };

  checks = {
    x86_64-linux = { };
  };

  devShells = import ./dev-shells.nix { inherit unstablePkgsFor; };

  formatter = import ./formatters.nix {
    inherit self treefmt-nix unstablePkgsFor;
  };

  inherit darwinConfigurations nixosConfigurations;
}
