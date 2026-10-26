{
  lab,
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

  # Names that must resolve to lumo itself for tailnet clients.
  privateNames = with lab.domains; [
    auth
    pirc
    dns
    cliproxyapi
    analytics
    traefik
    home
    forgejo
    woodpecker
    npu
  ];

  # lumo's own resolver order is not trustworthy for these names: Tailscale
  # refuses to loop back to a global resolver that is this node's address and
  # falls back to the base config (1.1.1.1 first), so glibc-linked Nix
  # binaries resolve them to Cloudflare and then fail the private ClientIP
  # routes. /etc/hosts is consulted before any resolver by musl and glibc.
  privateHostsBlock = pkgs.writeText "lumo-private-hosts" (
    "# dotfiles-lumo-private-begin\n"
    + lib.concatMapStringsSep "\n" (name: "${lab.hosts.lumo.tailnet} ${name}") privateNames
    + "\n# dotfiles-lumo-private-end\n"
  );

  blockyConfig = (pkgs.formats.yaml { }).generate "blocky.yml" {
    upstreams = {
      init.strategy = "failOnError";
      strategy = "parallel_best";
      timeout = "2s";
      groups.default = publicResolvers;
    };

    ports = {
      dns = "${lab.hosts.lumo.tailnet}:53";
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
      mapping = lib.genAttrs privateNames (_: lab.hosts.lumo.tailnet);
      zone = "";
    };

    # CF Pages applications resolve through public upstreams, not internal DNS.
    conditional.mapping = {
      "inm.${lab.domains.root}" = publicResolverEndpoints;
      "miaq.${lab.domains.root}" = publicResolverEndpoints;
      "ourbreak.${lab.domains.root}" = publicResolverEndpoints;
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

    # Replace only the marker-delimited block; keep Alpine's own entries.
    hosts_tmp="$(mktemp /etc/hosts.XXXXXX)"
    ${pkgs.gnused}/bin/sed '/^# dotfiles-lumo-private-begin$/,/^# dotfiles-lumo-private-end$/d' /etc/hosts > "$hosts_tmp"
    cat ${privateHostsBlock} >> "$hosts_tmp"
    chmod 0644 "$hosts_tmp"
    mv "$hosts_tmp" /etc/hosts
  '';
}
