{ pkgs, ... }:

{
  systemd.services.cloudflared-tunnel = {
    description = "Cloudflare Tunnel";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "root";
      Restart = "always";
      RestartSec = "5s";
      ExecStart = "${pkgs.bash}/bin/bash -lc 'exec ${pkgs.cloudflared}/bin/cloudflared tunnel run --token \"$(< /var/lib/secrets/cloudflared-token)\"'";
    };
  };
}
