{
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
    home = homeDirectory;
    description = username;
  };

  nix.settings.trusted-users = [username];
}
