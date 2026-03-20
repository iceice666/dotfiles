{
  config,
  lib,
  ...
}:

let
  sslCertificate = config.sops.secrets."cloudflare-origin-ca-cert".path;
  sslCertificateKey = config.sops.secrets."cloudflare-origin-ca-key".path;

  mkProxyVhost =
    {
      hostName,
      upstream,
      extraConfig ? { },
    }:
    {
      ${hostName} = lib.recursiveUpdate {
        forceSSL = true;
        sslCertificate = sslCertificate;
        sslCertificateKey = sslCertificateKey;

        locations."/".proxyPass = upstream;
        locations."/".proxyWebsockets = true;
      } extraConfig;
    };
in
{
  imports = [ ./sites/forgejo.nix ];

  _module.args.nginxLib = {
    inherit mkProxyVhost;
  };

  services.nginx = {
    enable = true;

    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    commonHttpConfig = ''
      real_ip_header CF-Connecting-IP;
      real_ip_recursive on;

      set_real_ip_from 127.0.0.1;
      set_real_ip_from ::1;

      include /var/lib/cloudflare-ips/nginx-real-ip-v4.conf;
      include /var/lib/cloudflare-ips/nginx-real-ip-v6.conf;
    '';
  };
}
