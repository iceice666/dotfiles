{
  pkgs,
  inputs,
  self,
  username,
  homeDirectory,
  dotfiles,
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
      "docker"
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
        ;
    };
    users.${username} = {
      imports = [ ../home ];
    };
  };
}
