{
  pkgs,
  inputs,
  self,
  username,
  homeDirectory,
  dotfiles,
  unstablePkgs,
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
        unstablePkgs
        ;
    };
    users.${username} = {
      imports = [ ../home ];
    };
  };
}
