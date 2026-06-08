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

  systemBase = [
    (dotfiles + /common/system)
  ]
  ++ (
    if kind == "darwin" then
      [ (dotfiles + /common/system-darwin) ]
    else if kind == "nixos" then
      [ (dotfiles + /common/system-nixos) ]
    else
      [ ]
  )
  ++ lib.optional (feat.nirinit or false) inputs.nirinit.nixosModules.nirinit;

  homeBase = dotfiles + /common/home-base;

  homeImports = [
    homeBase
  ]
  ++ lib.optional (feat.gui or false) (dotfiles + /common/home-gui)
  ++ lib.optional (feat.themegen or false) (dotfiles + /common/home-gui/themegen)
  ++ lib.optional (feat.rime or false) (dotfiles + /common/home-gui/rime)
  ++ lib.optional (feat.devEnv or false) (dotfiles + /common/home-base/dev-env.nix)
  ++ lib.optional (feat.pi or false) (dotfiles + /common/home-base/pi.nix)
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
    ++ host.modules
    ++ lib.optional (feat.sops or false) sopsModule
    ++ lib.optional (feat.homeManager or false) hmSystemModule
    ++ lib.optional (feat.homeManager or false) hmModule
    ++ [ overlayModule ];
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
else
  throw "Unsupported host kind: ${kind}"
