{ config, pkgs, ... }:

{
  services.freshrss = {
    enable = true;
    baseUrl = "https://rss.justaslime.dev";
    authType = "http_auth";
    defaultUser = "iceice666";
    extensions = with pkgs.freshrss-extensions; [ youtube ];
    virtualHost = "rss.justaslime.dev";
    webserver = "nginx";
  };

  systemd.services.freshrss-api-password-setup = {
    description = "Enable FreshRSS API for Homepage";
    after = [ "freshrss-config.service" ];
    requires = [ "freshrss-config.service" ];
    wantedBy = [ "multi-user.target" ];
    restartIfChanged = true;

    environment.DATA_PATH = config.services.freshrss.dataDir;

    serviceConfig = {
      Type = "oneshot";
      User = config.services.freshrss.user;
      Group = config.users.users.${config.services.freshrss.user}.group;
      UMask = "0077";
      StateDirectory = "freshrss";
      WorkingDirectory = config.services.freshrss.package;
      ReadWritePaths = config.services.freshrss.dataDir;
      DeviceAllow = "";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      PrivateUsers = true;
      ProcSubset = "pid";
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RemoveIPC = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@resources"
        "~@privileged"
      ];
    };

    script = ''
      ./cli/reconfigure.php --api-enabled

      php_bin=
      IFS= read -r php_bin < ./cli/update-user.php
      php_bin="''${php_bin#\#!}"

      "$php_bin" -r '
        declare(strict_types=1);
        require getcwd() . "/cli/_cli.php";
        $username = cliInitUser("${config.services.freshrss.defaultUser}");
        $apiPassword = trim(file_get_contents("${config.sops.secrets."freshrss-api-password".path}"));
        $error = FreshRSS_api_Controller::updatePassword($apiPassword);
        if ($error !== false) {
          fail($error);
        }
        invalidateHttpCache($username);
        accessRights();
        done();
      '
    '';
  };

  services.nginx.virtualHosts."rss.justaslime.dev" = {
    listen = [
      {
        addr = "127.0.0.1";
        port = 8083;
      }
    ];

    locations."~ ^.+?\\.php(/.*)?$".extraConfig = ''
      fastcgi_param REMOTE_USER $http_remote_user;
    '';
  };
}
