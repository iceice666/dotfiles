{ config, ... }:

{
  services.cloudflare-dyndns = {
    enable = true;

    # This secret must contain only the raw Cloudflare API token.
    apiTokenFile = config.sops.secrets."cloudflare-ddns-key".path;

    domains = [  "justaslime.dev" "proxy.justaslime.dev" ];

    frequency = "hourly";
    proxied = true;

    ipv4 = true;
    ipv6 = false;
  };
}
