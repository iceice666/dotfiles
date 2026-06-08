{
  host,
  specialArgs,
  homeImports,
  sops-nix,
}:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    sharedModules = if (host.features.sops or false) then [ sops-nix.homeManagerModules.sops ] else [ ];
    extraSpecialArgs = specialArgs;
    users.${host.username}.imports = homeImports;
  };
}
