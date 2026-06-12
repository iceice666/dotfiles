{
  homolab,
  lib,
  pkgs,
  ...
}:

let
  rootDomainRegex = builtins.replaceStrings [ "." ] [ "\\." ] homolab.domains.root;
  nginxConfig = pkgs.writeText "homolab-dev-port-proxy-nginx.conf" ''
    worker_processes 1;
    error_log stderr info;
    pid /run/lumo-dev-port-proxy/nginx.pid;

    events {
      worker_connections 1024;
    }

    http {
      access_log off;
      client_body_temp_path /run/lumo-dev-port-proxy/client_body_temp;
      proxy_temp_path /run/lumo-dev-port-proxy/proxy_temp;

      map $host $dev_backend_port {
        default "";
        ~^(?<matched_dev_port>3[0-9][0-9][0-9])\.test\.${rootDomainRegex}$ $matched_dev_port;
      }

      map $http_upgrade $connection_upgrade {
        default upgrade;
        "" close;
      }

      server {
        listen 0.0.0.0:${toString homolab.ports.devPortProxy};
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

  proxyService = pkgs.writeText "lumo-dev-port-proxy" ''
    #!/sbin/openrc-run
    name="lumo-dev-port-proxy"
    description="Lumo dynamic development port proxy"
    supervisor=supervise-daemon
    command="${pkgs.nginx}/bin/nginx"
    command_args="-c ${nginxConfig} -g 'daemon off;'"
    command_user="devproxy:devproxy"
    output_log="/var/log/lumo/dev-port-proxy.log"
    error_log="/var/log/lumo/dev-port-proxy.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need net
    }

    start_pre() {
      checkpath -f -m 0640 -o devproxy:devproxy /var/log/lumo/dev-port-proxy.log
      checkpath -d -m 0750 -o devproxy:devproxy /run/lumo-dev-port-proxy
      checkpath -d -m 0750 -o devproxy:devproxy /run/lumo-dev-port-proxy/client_body_temp
      checkpath -d -m 0750 -o devproxy:devproxy /run/lumo-dev-port-proxy/proxy_temp
      /bin/rm -f /run/lumo-dev-port-proxy/nginx.pid
      ${pkgs.util-linux}/bin/runuser -u devproxy -- \
        ${pkgs.nginx}/bin/nginx -t -c ${nginxConfig}
    }
  '';
in
{
  home.packages = [ pkgs.nginx ];

  home.activation.lumoDevPortProxy = lib.hm.dag.entryAfter [ "lumoDirectories" ] ''
    if ! /usr/bin/getent group devproxy >/dev/null; then
      /usr/sbin/addgroup -S devproxy
    fi
    if ! /usr/bin/id devproxy >/dev/null 2>&1; then
      /usr/sbin/adduser -S -D -H -h /var/empty -s /sbin/nologin -G devproxy devproxy
    fi

    install -Dm755 ${proxyService} /etc/init.d/lumo-dev-port-proxy
    /sbin/rc-update add lumo-dev-port-proxy default
    /sbin/rc-service lumo-dev-port-proxy restart
  '';
}
