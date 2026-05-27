{
  pkgs,
  inputs,
  self,
  username,
  homeDirectory,
  dotfiles,
  homolab,
  unstablePkgs,
  sopsNix,
  ...
}:

{
  programs.fish.enable = true;

  users.users.${username} = {
    isNormalUser = true;
    home = homeDirectory;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
    ];
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit
        inputs
        self
        username
        homeDirectory
        dotfiles
        homolab
        unstablePkgs
        sopsNix
        ;
    };
    users.${username} = {
      imports = [
        ../home
        sopsNix.homeManagerModules.sops
      ];
    };
  };
}
