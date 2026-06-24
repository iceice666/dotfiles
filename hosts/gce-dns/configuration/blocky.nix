{ dotfiles, pkgs, ... }:

let
  blockyMetricsPort = 4000;
  homolab = import (dotfiles + /lib/homolab.nix);
  publicResolvers = [
    "https://dns.quad9.net/dns-query"
    "https://cloudflare-dns.com/dns-query"
    "tcp-tls:9.9.9.9:853"
    "tcp-tls:1.1.1.1:853"
  ];
  publicResolverEndpoints = builtins.concatStringsSep "," publicResolvers;
  tailnetAddress = "100.126.249.103";
in
{
  services.blocky = {
    enable = true;
    package = pkgs.blocky-bin;
    settings = {
      upstreams = {
        init.strategy = "failOnError";
        strategy = "parallel_best";
        timeout = "2s";
        groups.default = publicResolvers;
      };

      ports = {
        dns = "${tailnetAddress}:53";
        http = ":${toString blockyMetricsPort}";
        dohPath = "/dns-query";
      };

      blocking = {
        denylists.default = [
          "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/pro.plus.txt"
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
        filterUnmappedTypes = true;
        mapping = {
          ${homolab.domains.auth} = homolab.hosts.gateway.tailnet;
          ${homolab.domains.dns} = homolab.hosts.gateway.tailnet;
          ${homolab.domains.grafana} = homolab.hosts.gateway.tailnet;
          ${homolab.domains.cliproxyapi} = homolab.hosts.gateway.tailnet;
          ${homolab.domains.traefik} = homolab.hosts.gateway.tailnet;
          ${homolab.domains.home} = homolab.hosts.gateway.tailnet;
          ${homolab.domains.dev} = homolab.hosts.gateway.tailnet;
          ${homolab.domains.npu} = homolab.hosts.gateway.tailnet;
        };
        zone = "";
      };

      # CF Pages applications: resolve through public upstreams (Cloudflare).
      # Not in customDNS.mapping, so they bypass internal DNS entirely.
      conditional.mapping = {
        "inm.${homolab.domains.root}" = publicResolverEndpoints;
        "miaq.${homolab.domains.root}" = publicResolverEndpoints;
        "ourbreak.${homolab.domains.root}" = publicResolverEndpoints;
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

  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 19100;
    openFirewall = false;
  };
}
