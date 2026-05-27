{
  homolab,
  pkgs,
  ...
}:

let
  rootDomainRegex = builtins.replaceStrings [ "." ] [ "\\." ] homolab.domains.root;
  nginxConfig = pkgs.writeText "homolab-dev-port-proxy-nginx.conf" ''
    worker_processes 1;
    error_log stderr info;
    pid /run/homolab-dev-port-proxy/nginx.pid;

    events {
      worker_connections 1024;
    }

    http {
      access_log off;
      client_body_temp_path /run/homolab-dev-port-proxy/client_body_temp;
      proxy_temp_path /run/homolab-dev-port-proxy/proxy_temp;

      map $host $dev_backend_port {
        default "";
        ~^(?<matched_dev_port>3[0-9][0-9][0-9])\.test\.${rootDomainRegex}$ $matched_dev_port;
      }

      map $http_upgrade $connection_upgrade {
        default upgrade;
        "" close;
      }

      server {
        listen 127.0.0.1:${toString homolab.ports.devPortProxy};
        client_max_body_size 110m;

        location / {
          if ($dev_backend_port = "") {
            return 404;
          }

          proxy_http_version 1.1;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_pass http://127.0.0.1:$dev_backend_port;
        }
      }
    }
  '';
in
{
  systemd.services.homolab-dev-port-proxy = {
    description = "Homolab dynamic dev-port proxy";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/homolab-dev-port-proxy/client_body_temp /run/homolab-dev-port-proxy/proxy_temp";
      ExecStart = "${pkgs.nginx}/bin/nginx -c ${nginxConfig} -g 'daemon off;'";
      RuntimeDirectory = "homolab-dev-port-proxy";
      Restart = "on-failure";
      Type = "simple";
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
    };
  };
}
