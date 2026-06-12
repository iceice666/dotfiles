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
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBv4wUd0xFUa2wRlXbB2f2IntFxTGsxwNAhGQIyxfso8 iceice666@M3Air"
    ];
  };
}
