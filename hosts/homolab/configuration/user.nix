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
    hashedPassword = "$6$ZuRS1jtUzGWpge9G$2LVYNIwjEBqBwu13qWdVZpf0cVTyuyBmbop7D63nWLzEtua9Wt3377uCQMjkTqPHhfWLtRF.0dcVr/8W7F3Wr1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBv4wUd0xFUa2wRlXbB2f2IntFxTGsxwNAhGQIyxfso8 iceice666@M3Air"
    ];
  };
}
