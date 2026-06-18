{
  config,
  homolab,
  pkgs,
  ...
}:

let
  # Direct host-port API is LAN-only; public access goes through Traefik at
  # ${homolab.urls.cliproxyapi}.
  dataDir = "/mnt/storage/cliproxyapi";
  configPath = config.sops.templates."cliproxyapi-config.yaml".path;
in
{
  users.groups.cliproxyapi = { };
  users.users.cliproxyapi = {
    isSystemUser = true;
    group = "cliproxyapi";
    home = dataDir;
    createHome = false;
  };

  environment.systemPackages = [ pkgs.cliproxyapi-bin ];

  systemd.tmpfiles.rules = [
    "d '/mnt/storage/cliproxyapi' 0750 cliproxyapi cliproxyapi - -"
    "d '${dataDir}' 0750 cliproxyapi cliproxyapi - -"
    "d '${dataDir}/auths' 0750 cliproxyapi cliproxyapi - -"
    "d '${dataDir}/plugins' 0750 cliproxyapi cliproxyapi - -"
    "z '${dataDir}' 0750 cliproxyapi cliproxyapi - -"
  ];

  systemd.services.cliproxyapi = {
    description = "CLIProxyAPI OpenAI-compatible CLI proxy";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = dataDir;

    serviceConfig = {
      Type = "simple";
      User = "cliproxyapi";
      Group = "cliproxyapi";
      WorkingDirectory = dataDir;
      ExecStart = "${pkgs.cliproxyapi-bin}/bin/cli-proxy-api -config ${configPath}";
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ dataDir ];
    };
  };
}
