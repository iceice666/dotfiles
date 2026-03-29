{ pkgs, ... }:

{
  systemd.services.youtube-rss-proxy = {
    description = "YouTube RSS to JSON proxy";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.youtube-rss-proxy}/bin/youtube-rss-proxy --host 127.0.0.1 --port 8095 --limit 25";
      Environment = [
        "YOUTUBE_CHANNEL_IDS=UCbRP3c757lWg9M-U7TyEkXA,UCEbYhDd6c6vngsF5PQpFVWg,UCrqM0Ym_NbK1fqeQG2VIohg,UCUyeluBRhGPCW4rPe_UvBZQ,UC6biysICWOJ-C3P4Tyeggzg,UCam3IAA-nyfxRL8_wDQ35VA"
        "YOUTUBE_PLAYLIST_IDS="
      ];
      Restart = "on-failure";
      RestartSec = "5s";

      DynamicUser = true;
      NoNewPrivileges = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = "AF_INET AF_INET6 AF_UNIX";
    };
  };
}
