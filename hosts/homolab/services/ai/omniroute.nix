{ config, homolab, ... }:

let
  # Direct host-port API is LAN-only; public access goes through Traefik at
  # ${homolab.urls.omniroute}/v1 and still requires an OmniRoute API key.
  apiHost = homolab.network.lan.address;
  apiPort = homolab.ports.omnirouteApi;
  dashboardHost = "127.0.0.1";
  dashboardPort = homolab.ports.omnirouteDashboard;
  dashboardUrl = homolab.urls.omniroute;
  omnirouteDataDir = "/mnt/storage/omniroute/data";
in
{
  systemd.tmpfiles.rules = [
    "d '/mnt/storage/omniroute' 0750 root root - -"
    "d '${omnirouteDataDir}' 0750 root root - -"
    "d '${omnirouteDataDir}/home' 0750 root root - -"
    "d '${omnirouteDataDir}/home/.config' 0750 root root - -"
    "d '${omnirouteDataDir}/home/.local' 0750 root root - -"
    "d '${omnirouteDataDir}/home/.local/share' 0750 root root - -"
    "z '${omnirouteDataDir}' 0750 root root - -"
  ];

  virtualisation.oci-containers = {
    backend = "podman";

    containers.omniroute = {
      serviceName = "omniroute";
      image = "docker.io/diegosouzapw/omniroute:3.8.2@sha256:af1e1e99acd76c8413a33cc6e9b913843fa6d3d7e680b70fb7eb6dc610ed42a4";

      environment = {
        API_HOST = "0.0.0.0";
        API_PORT = toString apiPort;
        AUTH_COOKIE_SECURE = "true";
        BASE_URL = dashboardUrl;
        CLI_ALLOW_CONFIG_WRITES = "true";
        CLI_CONFIG_HOME = "/app/data/home";
        DASHBOARD_PORT = toString dashboardPort;
        DATA_DIR = "/app/data";
        HOME = "/app/data/home";
        HOSTNAME = "0.0.0.0";
        NEXT_PUBLIC_BASE_URL = dashboardUrl;
        PORT = toString dashboardPort;
        REQUIRE_API_KEY = "true";
        STORAGE_ENCRYPTION_KEY_VERSION = "v1";
        XDG_CONFIG_HOME = "/app/data/home/.config";
        XDG_DATA_HOME = "/app/data/home/.local/share";
      };

      environmentFiles = [ config.sops.templates."omniroute.env".path ];
      ports = [
        "${dashboardHost}:${toString dashboardPort}:${toString dashboardPort}"
        "${apiHost}:${toString apiPort}:${toString apiPort}"
      ];
      volumes = [ "${omnirouteDataDir}:/app/data" ];
      extraOptions = [ "--stop-timeout=40" ];
    };
  };

  systemd.services.omniroute = {
    unitConfig.RequiresMountsFor = omnirouteDataDir;
  };
}
