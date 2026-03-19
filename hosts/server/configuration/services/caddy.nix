{ ... }:

{
  services.caddy = {
    enable = true;

    virtualHosts."code.justaslime.dev".extraConfig = ''
      reverse_proxy 127.0.0.1:3000
    '';
  };
}
