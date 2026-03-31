{
  config,
  pkgs,
  ...
}:

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
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --metrics localhost:49312 run --token-file ${
        config.sops.secrets."cloudflared-token".path
      }";
    };
  };
}
