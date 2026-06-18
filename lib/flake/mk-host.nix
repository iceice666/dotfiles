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
  inherit (nixpkgs) lib;
  feat = host.features or { };
  kind = host.kind;

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

  systemBase =
    lib.optionals (kind == "nixos" || kind == "darwin") [ (dotfiles + /common/system) ]
    ++ lib.optional (kind == "darwin") (dotfiles + /common/system-darwin)
    ++ lib.optional (kind == "nixos") (dotfiles + /common/system-nixos)
    ++ lib.optional (kind == "nixos" && (feat.nirinit or false)) inputs.nirinit.nixosModules.nirinit;

  homeBase = dotfiles + /common/home-base;

  homeImports = [
    homeBase
  ]
  ++ lib.optional (feat.gui or false) (dotfiles + /common/home-gui)
  ++ lib.optional (feat.themegen or false) (dotfiles + /common/home-gui/themegen)
  ++ lib.optional (feat.rime or false) (dotfiles + /common/home-gui/rime)
  ++ lib.optional (feat.devEnv or false) (dotfiles + /common/home-base/dev-env.nix)
  ++ lib.optional (feat.omp or false) (dotfiles + /common/home-base/omp.nix)
  ++ (host.homeModules or [ ]);

  hmModule = import ./home-manager.nix {
    inherit
      host
      specialArgs
      homeImports
      sops-nix
      ;
  };

  sopsModule =
    if kind == "nixos" then
      sops-nix.nixosModules.sops
    else if kind == "darwin" then
      sops-nix.darwinModules.sops
    else
      null;

  hmSystemModule =
    if kind == "nixos" then
      home-manager.nixosModules.home-manager
    else if kind == "darwin" then
      home-manager.darwinModules.home-manager
    else
      null;

  modules =
    systemBase
    ++ (host.modules or [ ])
    ++ lib.optional (feat.sops or false) sopsModule
    ++ lib.optional (feat.homeManager or false) hmSystemModule
    ++ lib.optional (feat.homeManager or false) hmModule
    ++ [ overlayModule ];

  standalonePkgs = import nixpkgs {
    inherit (host) system;
    config.allowUnfree = true;
    overlays = [ overlay ];
  };

  standaloneModules =
    homeImports
    ++ lib.optional (feat.sops or false) sops-nix.homeManagerModules.sops
    ++ [
      {
        nixpkgs = {
          config.allowUnfree = true;
          overlays = [ overlay ];
        };
      }
    ];
in
if kind == "nixos" then
  nixpkgs.lib.nixosSystem {
    inherit specialArgs;
    inherit (host) system;
    inherit modules;
  }
else if kind == "darwin" then
  nix-darwin.lib.darwinSystem {
    inherit specialArgs;
    inherit (host) system;
    inherit modules;
  }
else if kind == "home-manager" then
  home-manager.lib.homeManagerConfiguration {
    pkgs = standalonePkgs;
    extraSpecialArgs = specialArgs;
    modules = standaloneModules;
  }
else
  throw "Unsupported host kind: ${kind}"
