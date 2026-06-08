{
  config,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  dynacatPort = homolab.ports.dynacat;
  dynacatStateDir = "/var/lib/dynacat";
  dynacatConfigPath = "/etc/dynacat/dynacat.yml";

  dynacatPackage = pkgs.buildGoModule rec {
    pname = "dynacat";
    version = "2.2.2";

    src = pkgs.fetchFromGitHub {
      owner = "Panonim";
      repo = pname;
      rev = version;
      hash = "sha256-kPUv84yI4LPkoaiVLnBtUi5ecbLC0Is9+9jD00xAmDw=";
    };

    vendorHash = "sha256-7YfGV8ULD2eN3AtzYI18G9/UlpamT3fqjnbvkrCOa14=";
    ldflags = [ "-s -w -X github.com/Panonim/dynacat/internal/dynacat.buildVersion=${version}" ];

    meta.mainProgram = pname;
  };

  yamlFormat = pkgs.formats.yaml { };

  mkLoopbackUrl = port: path: "http://127.0.0.1:${toString port}${path}";

  serviceIcons = {
    authelia = "si:authelia";
    grafana = "si:grafana";
    omniroute = "https://raw.githubusercontent.com/diegosouzapw/OmniRoute/main/electron/assets/icon.png";
    proxy = "si:traefikproxy";
    shimmy = "si:openai";
  };

  mkMonitorSite =
    title: icon: url: checkUrl:
    monitorSiteDefaults
    // {
      inherit icon title url;
      "check-url" = checkUrl;
    };

  monitorSiteDefaults = {
    timeout = "5s";
    "alt-status-codes" = [
      302
      401
      403
    ];
  };

  mkMonitorWidget = title: sites: {
    type = "monitor";
    inherit title sites;
    cache = "1m";
    "update-interval" = "2m";
  };

  publicMonitorSites = [
    (mkMonitorSite "OmniRoute" serviceIcons.omniroute homolab.urls.omniroute (
      mkLoopbackUrl homolab.ports.omnirouteDashboard ""
    ))
  ];

  infraMonitorSites = [
    (mkMonitorSite "Traefik" serviceIcons.proxy homolab.urls.traefik (
      mkLoopbackUrl homolab.ports.traefikPing "/ping"
    ))
    (mkMonitorSite "Grafana" serviceIcons.grafana homolab.urls.grafana (
      mkLoopbackUrl homolab.ports.grafana "/api/health"
    ))
    (mkMonitorSite "Authelia" serviceIcons.authelia homolab.urls.auth (
      mkLoopbackUrl homolab.ports.authelia ""
    ))
    (mkMonitorSite "Shimmy" serviceIcons.shimmy "${homolab.ai.baseUrl}/health" (
      "${homolab.ai.baseUrl}/health"
    ))
  ];

  dynacatConfig = yamlFormat.generate "dynacat.yml" {
    server = {
      port = dynacatPort;
      proxied = true;
    };

    branding = {
      "hide-footer" = true;
      "logo-text" = "HL";
      "app-name" = homolab.hostName;
    };

    theme = {
      "background-color" = "295 10 23";
      "primary-color" = "10 45 71";
      "positive-color" = "156 6 69";
      "negative-color" = "11 37 64";
      "contrast-multiplier" = 1.1;
      "text-saturation-multiplier" = 1;
      "disable-picker" = true;
      presets = {
        "inm-light" = {
          light = true;
          "background-color" = "28 15 75";
          "primary-color" = "7 27 39";
          "positive-color" = "156 4 49";
          "negative-color" = "9 22 53";
          "contrast-multiplier" = 1.1;
          "text-saturation-multiplier" = 1;
        };
      };
    };

    pages = [
      {
        name = "system";
        width = "wide";
        columns = [
          {
            size = "small";
            widgets = [
              {
                type = "server-stats";
                title = "Server";
                servers = [
                  {
                    type = "local";
                    name = homolab.hostName;
                  }
                ];
              }
            ];
          }
          {
            size = "full";
            widgets = [
              {
                type = "split-column";
                "max-columns" = 3;
                widgets = [
                  (mkMonitorWidget "Public" publicMonitorSites)
                  (mkMonitorWidget "Infra" infraMonitorSites)
                ];
              }
            ];
          }
        ];
      }
    ];
  };
in
{
  users = {
    groups.dynacat = { };

    users.dynacat = {
      isSystemUser = true;
      group = "dynacat";
    };
  };

  environment.etc = {
    "dynacat/dynacat.yml".source = dynacatConfig;
  };

  systemd.services.dynacat = {
    description = "Dynacat dashboard";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      BIND = "127.0.0.1";
    };

    serviceConfig = {
      User = "dynacat";
      Group = "dynacat";
      ExecStart = lib.escapeShellArgs [
        "${dynacatPackage}/bin/dynacat"
        "-config"
        dynacatConfigPath
      ];
      WorkingDirectory = dynacatStateDir;
      StateDirectory = "dynacat";
      Restart = "on-failure";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ dynacatStateDir ];
    };
  };
}
