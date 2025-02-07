{
  pkgs,
  hostname,
  username,
  homeDirectory,
  ...
}:
#############################################################
#
#  Host & Users configuration
#
#############################################################
{
  networking.hostName = hostname;
  networking.computerName = hostname;
  system.defaults.smb.NetBIOSName = hostname;

  users.users."${username}" = {
    uid = 501;
    home = homeDirectory;
    description = username;
    shell = pkgs.nushell;
  };

  users.knownUsers = [username];

  nix.settings.trusted-users = [username];
}
