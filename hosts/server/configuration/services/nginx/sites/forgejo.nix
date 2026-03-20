{ nginxLib, ... }:

{
  services.nginx.virtualHosts = nginxLib.mkProxyVhost {
    hostName = "code.justaslime.dev";
    upstream = "http://127.0.0.1:3000";
  };
}
