{
  inputs,
  self,
  nixpkgs,
  nix-darwin,
  home-manager,
  sops-nix,
  overlay,
  unstablePkgsFor,
  dotfiles,
}:

host:

let
  commonSpecialArgs = {
    inherit inputs self;
    inherit (host) username homeDirectory;
    dotfiles = dotfiles;
    unstablePkgs = unstablePkgsFor host.system;
  };

  specialArgs = commonSpecialArgs // (host.extraSpecialArgs or { });
  overlayModule = {
    nixpkgs.overlays = [ overlay ];
  };

  nixosModules =
    host.modules
    ++ (if host.features.sops or false then [ sops-nix.nixosModules.sops ] else [ ])
    ++ (if host.features.homeManager or false then [ home-manager.nixosModules.home-manager ] else [ ])
    ++ [ overlayModule ];

  darwinModules =
    host.modules
    ++ (if host.features.sops or false then [ sops-nix.darwinModules.sops ] else [ ])
    ++ (if host.features.homeManager or false then [ home-manager.darwinModules.home-manager ] else [ ])
    ++ [ overlayModule ];
in
if host.kind == "nixos" then
  nixpkgs.lib.nixosSystem {
    inherit specialArgs;
    inherit (host) system;
    modules = nixosModules;
  }
else if host.kind == "darwin" then
  nix-darwin.lib.darwinSystem {
    inherit specialArgs;
    inherit (host) system;
    modules = darwinModules;
  }
else
  throw "Unsupported host kind: ${host.kind}"
