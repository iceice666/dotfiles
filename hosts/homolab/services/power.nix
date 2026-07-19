{
  homolab,
  pkgs,
  ...
}:

let
  interface = homolab.network.interface;
in
{
  # Arm Wake-on-LAN so the NIC can receive magic packets while suspended.
  networking.interfaces.${interface}.wakeOnLan.enable = true;

  # Re-arm WoL after NetworkManager brings the interface up, so it survives
  # NM reapplying its connection profile on reconnect or resume.
  networking.networkmanager.dispatcherScripts = [
    {
      source = pkgs.writeText "nm-wol-rearm" ''
        #!/bin/sh
        [ "$1" = "${interface}" ] || exit 0
        [ "$2" = "up" ] || exit 0
        ${pkgs.ethtool}/bin/ethtool -s ${interface} wol g
      '';
      type = "basic";
    }
  ];
}
