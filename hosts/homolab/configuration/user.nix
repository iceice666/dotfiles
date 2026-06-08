{
  pkgs,
  username,
  homeDirectory,
  ...
}:

{
  security.sudo.wheelNeedsPassword = false;

  users.users.${username} = {
    isNormalUser = true;
    home = homeDirectory;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
    ];
  };
}
