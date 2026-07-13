let
  baseDomain = "justaslime.dev";
  lanAddress = "192.168.1.127";

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
    homolab = {
      lan = lanAddress;
      tailnet = "100.110.95.111";
      mac = "24:4b:fe:df:2d:45";
      role = "ai";
    };
  };

  ports = {
    ssh = 2222;
    traefikPing = 18081;
    traefikMetrics = 18082;
    prometheus = 18083;
    grafana = 18084;
    postgresql = 25432;
    authelia = 18091;
    cliproxyapi = 20129;
    shimmy = 11434;
    dynacat = 18075;
    devPortProxy = 18076;
    hermesGateway = 8642;
    hermesDashboard = 9119;
    honcho = 18077;
    umami = 18078;
    ntfy = 18079;
  };

  portRanges = {
    dev = {
      from = 3000;
      to = 3999;
    };
  };
in
rec {
  hostName = "homolab";

  network = {
    interface = "enp7s0";
    lan = {
      address = lanAddress;
      broadcast = "192.168.1.255";
      cidr = "192.168.1.0/24";
      gateway = "192.168.1.1";
      prefixLength = 24;
    };

    tailnet = {
      address = "100.110.95.111";
      dnsName = "homolab-linux.skate-kanyu.ts.net";
    };

    docker.bridgeAddress = "172.17.0.1";
  };

  domains = rec {
    root = baseDomain;
    auth = "auth.${root}";
    dns = "dns.${root}";
    grafana = "grafana.${root}";
    cliproxyapi = "cliproxyapi.${root}";
    traefik = "traefik.${root}";
    home = "home.${root}";
    dev = "dev.${root}";
    npu = "npu.${root}";
    analytics = "analytics.${root}";
    push = "push.${root}";
  };

  urls = {
    auth = "https://${domains.auth}";
    grafana = "https://${domains.grafana}";
    dns = "https://${domains.dns}/dns-query";
    cliproxyapi = "https://${domains.cliproxyapi}";
    traefik = "https://${domains.traefik}";
    home = "https://${domains.home}";
    dev = "https://${domains.dev}";
    npu = "https://${domains.npu}";
    analytics = "https://${domains.analytics}";
    push = "https://${domains.push}";
  };

  contact = {
    adminEmail = "iceice666@${baseDomain}";
    noReplyEmail = "noreply@${baseDomain}";
    noReplyDomain = "noreply.${baseDomain}";
  };

  inherit ports;
  inherit portRanges;
  inherit hosts;

  ai = rec {
    host = "127.0.0.1";
    tailnetHost = hosts.homolab.tailnet;
    port = ports.shimmy;
    baseUrl = "http://${host}:${toString port}";
    tailnetBaseUrl = "http://${tailnetHost}:${toString port}";
    openaiBaseUrl = "${baseUrl}/v1";
    tailnetOpenaiBaseUrl = "${tailnetBaseUrl}/v1";
    model = "qwen3.6-35b-a3b";
  };
}
