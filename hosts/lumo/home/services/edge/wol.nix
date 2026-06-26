{ homolab, pkgs, ... }:

{
  home.packages = [ pkgs.wakeonlan ];

  # Any tailnet client can ssh root@lumo homolab-wake to have lumo
  # broadcast the magic packet on the home LAN.
  home.file.".local/bin/homolab-wake" = {
    executable = true;
    text = ''
      #!/bin/sh
      exec ${pkgs.wakeonlan}/bin/wakeonlan \
          -i ${homolab.network.lan.broadcast} \
          ${homolab.hosts.homolab.mac}
    '';
  };
}
