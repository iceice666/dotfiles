let
  baseDomain = "justaslime.dev";
  lanAddress = "192.168.1.127";

  ports = {
    ssh = 2222;
    traefikPing = 18081;
    traefikMetrics = 18082;
    prometheus = 18083;
    grafana = 18084;
    postgresql = 25432;
    authelia = 18091;
    omnirouteDashboard = 20128;
    omnirouteApi = 20129;
    shimmy = 11434;
    technitium = 5380;
    technitiumDoh = 8053;
    dynacat = 18075;
    devPortProxy = 18076;
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
      cidr = "192.168.1.0/24";
      gateway = "192.168.1.1";
      prefixLength = 24;
    };

    docker.bridgeAddress = "172.17.0.1";
  };

  domains = rec {
    root = baseDomain;
    auth = "auth.${root}";
    dns = "dns.${root}";
    grafana = "grafana.${root}";
    omniroute = "omniroute.${root}";
    traefik = "traefik.${root}";
    home = "home.${root}";
    dev = "dev.${root}";
  };

  urls = {
    auth = "https://${domains.auth}";
    grafana = "https://${domains.grafana}";
    omniroute = "https://${domains.omniroute}";
    traefik = "https://${domains.traefik}";
    technitium = "https://${domains.dns}/";
    home = "https://${domains.home}";
    dev = "https://${domains.dev}";
  };

  contact = {
    adminEmail = "iceice666@${baseDomain}";
    noReplyEmail = "noreply@${baseDomain}";
    noReplyDomain = "noreply.${baseDomain}";
  };

  inherit ports;
  inherit portRanges;

  ai = rec {
    host = "127.0.0.1";
    port = ports.shimmy;
    baseUrl = "http://${host}:${toString port}";
    openaiBaseUrl = "${baseUrl}/v1";
    model = "qwen3.6-35b-a3b";
  };
}
