let
  baseDomain = "justaslime.dev";

  hosts = {
    # LAN addresses are stable; tailnet IPs filled in after board provision.
    # lumo also carries the edge role (Traefik/Authelia/Cloudflare) that the
    # retired gateway Pi used to host.
    lumo = {
      lan = "192.168.1.128";
      tailnet = "100.120.152.7";
      role = "apps";
    };
    # worker: the ex-gateway Pi, repurposed for disposable work / agent
    # runtimes. Stateless — persistent data lives on lumo.
    worker = {
      lan = "192.168.1.129";
      tailnet = "100.119.84.114";
      role = "worker";
    };
  };

  ports = {
    traefikPing = 18081;
    traefikMetrics = 18082;
    prometheus = 18083;
    postgresql = 25432;
    authelia = 18091;
    cliproxyapi = 20129;
    cliproxyapiUsageKeeper = 20130;
    dynacat = 18075;
    umami = 18078;
    forgejo = 18079;
    forgejoSsh = 2222;
    woodpecker = 18080;
    woodpeckerGrpc = 19001;
    woodpeckerAgentHealth = 19002;
  };

in
rec {
  network.lan = {
    broadcast = "192.168.1.255";
    cidr = "192.168.1.0/24";
    gateway = "192.168.1.1";
    prefixLength = 24;
  };

  domains = rec {
    root = baseDomain;
    auth = "auth.${root}";
    pirc = "pirc.${root}";
    dns = "dns.${root}";
    cliproxyapi = "cliproxyapi.${root}";
    traefik = "traefik.${root}";
    home = "home.${root}";
    npu = "npu.${root}";
    analytics = "analytics.${root}";
    forgejo = "git.${root}";
    woodpecker = "ci.${root}";
    proxy = "proxy.${root}";
  };

  urls = {
    auth = "https://${domains.auth}";
    dns = "https://${domains.dns}/dns-query";
    cliproxyapi = "https://${domains.cliproxyapi}";
    traefik = "https://${domains.traefik}";
    home = "https://${domains.home}";
    npu = "https://${domains.npu}";
    analytics = "https://${domains.analytics}";
    forgejo = "https://${domains.forgejo}";
    woodpecker = "https://${domains.woodpecker}";
  };

  contact = {
    adminEmail = "iceice666@${baseDomain}";
    noReplyEmail = "noreply@${baseDomain}";
    noReplyDomain = "noreply.${baseDomain}";
  };

  inherit ports hosts;
}
