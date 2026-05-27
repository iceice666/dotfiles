{ config, homolab, ... }:

{
  services.cloudflare-dyndns = {
    enable = true;

    # This secret must contain only the raw Cloudflare API token.
    apiTokenFile = config.sops.secrets."cloudflare-ddns-key".path;

    domains = [
      homolab.domains.root
    ];

    frequency = "hourly";
    proxied = true;

    ipv4 = true;
    ipv6 = false;
  };
}
