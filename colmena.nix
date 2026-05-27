# Colmena hive for NixOS hosts (framework + homolab).
# m3air is nix-darwin and stays on darwin-rebuild — Colmena is NixOS-only.
{
  inputs,
  self,
  overlay,
  unstablePkgsFor,
}:
let
  inherit (inputs) nixpkgs sops-nix home-manager;

  commonSpecialArgs = {
    inherit inputs self;
    username = "iceice666";
    homeDirectory = "/home/iceice666";
    dotfiles = ./.;
    unstablePkgs = unstablePkgsFor "x86_64-linux";
  };

  commonModules = [
    sops-nix.nixosModules.sops
    home-manager.nixosModules.home-manager
    { nixpkgs.overlays = [ overlay ]; }
  ];
in
{
  meta = {
    nixpkgs = import nixpkgs { system = "x86_64-linux"; };
    specialArgs = commonSpecialArgs;
  };

  framework =
    { ... }:
    {
      deployment = {
        targetHost = null;
        targetUser = "iceice666";
        allowLocalDeployment = true;
      };
      imports = [ ./hosts/framework/configuration ] ++ commonModules;
    };

  homolab =
    { ... }:
    {
      deployment = {
        targetHost = "homolab";
        targetUser = "iceice666";
        buildOnTarget = true;
      };
      _module.args = {
        homolab = import ./lib/homolab.nix;
        sopsNix = inputs.sops-nix;
      };
      imports = [ ./hosts/homolab/configuration ] ++ commonModules;
    };
}
