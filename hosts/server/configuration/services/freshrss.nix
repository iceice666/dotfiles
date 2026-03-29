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
