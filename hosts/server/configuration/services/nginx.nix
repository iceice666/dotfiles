{ config, ... }:

{
  services.nginx = {
    enable = true;

    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts."code.justaslime.dev" = {
      forceSSL = true;
      sslCertificate = config.sops.secrets."cloudflare-origin-ca-cert".path;
      sslCertificateKey = config.sops.secrets."cloudflare-origin-ca-key".path;

      locations."/".proxyPass = "http://127.0.0.1:3000";
    };
  };
}
