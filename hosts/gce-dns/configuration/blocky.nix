{ dotfiles, ... }:

let
  blockyMetricsPort = 4000;
  homolab = import (dotfiles + /lib/homolab.nix);
in
{
  services.blocky = {
    enable = true;
    settings = {
      upstreams = {
        init.strategy = "failOnError";
        strategy = "parallel_best";
        timeout = "2s";
        groups.default = [
          "https://dns.quad9.net/dns-query"
          "https://cloudflare-dns.com/dns-query"
          "tcp-tls:9.9.9.9:853"
          "tcp-tls:1.1.1.1:853"
        ];
      };

      ports = {
        dns = [ ];
        http = ":${toString blockyMetricsPort}";
        dohPath = "/dns-query";
      };

      blocking = {
        denylists.default = [
          "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/pro.txt"
          "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/tif.txt"
        ];
        clientGroupsBlock.default = [ "default" ];
        blockType = "zeroIp";
        loading = {
          strategy = "failOnError";
          refreshPeriod = "24h";
        };
      };

      customDNS = {
        customTTL = "5m";
        mapping.${homolab.domains.root} = homolab.network.tailnet.address;
      };

      caching = {
        minTime = "5m";
        maxTime = "30m";
        prefetching = true;
      };

      prometheus = {
        enable = true;
        path = "/metrics";
      };

      queryLog.type = "none";

      log = {
        level = "info";
        format = "text";
        privacy = true;
      };
    };
  };
}
