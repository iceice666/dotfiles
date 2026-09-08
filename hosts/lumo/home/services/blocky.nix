{
  homolab,
  lib,
  pkgs,
  ...
}:

let
  blockyMetricsPort = 4000;
  publicResolvers = [
    "https://dns.quad9.net/dns-query"
    "https://cloudflare-dns.com/dns-query"
    "tcp-tls:9.9.9.9:853"
    "tcp-tls:1.1.1.1:853"
  ];
  publicResolverEndpoints = builtins.concatStringsSep "," publicResolvers;

  blockyConfig = (pkgs.formats.yaml { }).generate "blocky.yml" {
    upstreams = {
      init.strategy = "failOnError";
      strategy = "parallel_best";
      timeout = "2s";
      groups.default = publicResolvers;
    };

    ports = {
      dns = "${homolab.hosts.lumo.tailnet}:53";
      http = "127.0.0.1:${toString blockyMetricsPort}";
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
        ${homolab.domains.auth} = homolab.hosts.lumo.tailnet;
        ${homolab.domains.dns} = homolab.hosts.lumo.tailnet;
        ${homolab.domains.grafana} = homolab.hosts.lumo.tailnet;
        ${homolab.domains.cliproxyapi} = homolab.hosts.lumo.tailnet;
        ${homolab.domains.analytics} = homolab.hosts.lumo.tailnet;
        ${homolab.domains.traefik} = homolab.hosts.lumo.tailnet;
        ${homolab.domains.home} = homolab.hosts.lumo.tailnet;
        ${homolab.domains.dev} = homolab.hosts.lumo.tailnet;
        ${homolab.domains.npu} = homolab.hosts.lumo.tailnet;
      };
      zone = "";
    };

    # CF Pages applications resolve through public upstreams, not internal DNS.
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

  blockyService = pkgs.writeText "lumo-blocky" ''
    #!/sbin/openrc-run
    name="lumo-blocky"
    description="Lumo Blocky DNS proxy and ad blocker"
    supervisor=supervise-daemon
    command="${lib.getExe pkgs.blocky-bin}"
    command_args="--config ${blockyConfig}"
    command_user="blocky:blocky"
    capabilities="^cap_net_bind_service"
    no_new_privs=yes
    output_log="/var/log/lumo/blocky.log"
    error_log="/var/log/lumo/blocky.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need net tailscale
      before lumo-traefik lumo-prometheus
    }

    start_pre() {
      checkpath -f -m 0640 -o blocky:blocky /var/log/lumo/blocky.log
      ${lib.getExe pkgs.blocky-bin} --config ${blockyConfig} validate
    }
  '';
in
{
  home.packages = [ pkgs.blocky-bin ];

  home.activation.lumoBlocky = lib.hm.dag.entryAfter [ "lumoDirectories" "lumoEdgeNftables" ] ''
    if ! /usr/bin/getent group blocky >/dev/null; then
      /usr/sbin/addgroup -S blocky
    fi
    if ! /usr/bin/id blocky >/dev/null 2>&1; then
      /usr/sbin/adduser -S -D -H -h /var/empty -s /sbin/nologin -G blocky blocky
    fi

    install -Dm755 ${blockyService} /etc/init.d/lumo-blocky
    /sbin/rc-update add lumo-blocky default
    /sbin/rc-service lumo-blocky restart
  '';
}
