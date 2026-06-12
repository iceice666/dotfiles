{ homolab, ... }:

let
  inherit (homolab.network) interface;
  lanCidr = homolab.network.lan.cidr;
  devPortRange = homolab.portRanges.dev;

  mkIpv4AcceptRule =
    port: cidr:
    "iptables -A INPUT -i ${interface} -p tcp -s ${cidr} --dport ${toString port} -j ACCEPT";

  mkIpv4DeleteRule =
    port: cidr:
    "iptables -D INPUT -i ${interface} -p tcp -s ${cidr} --dport ${toString port} -j ACCEPT || true";

  mkDropRule = port: "iptables -A INPUT -i ${interface} -p tcp --dport ${toString port} -j DROP";

  mkDeleteDropRule =
    port: "iptables -D INPUT -i ${interface} -p tcp --dport ${toString port} -j DROP || true";

  mkRangeDropRule =
    range:
    "iptables -A INPUT -i ${interface} -p tcp --dport ${toString range.from}:${toString range.to} -j DROP";

  mkDeleteRangeDropRule =
    range:
    "iptables -D INPUT -i ${interface} -p tcp --dport ${toString range.from}:${toString range.to} -j DROP || true";
in
{
  networking = {
    hostName = homolab.hostName;

    hosts = {
      "127.0.0.1" = [
        homolab.domains.auth
        homolab.domains.dns
        homolab.domains.omniroute
        homolab.domains.home
        homolab.domains.traefik
        homolab.domains.npu
      ];
    };

    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "8.8.8.8"
    ];
    defaultGateway = homolab.network.lan.gateway;
    useDHCP = false;

    networkmanager.enable = true;

    interfaces.${interface}.ipv4.addresses = [
      {
        address = homolab.network.lan.address;
        prefixLength = homolab.network.lan.prefixLength;
      }
    ];

    firewall = {
      allowedTCPPorts = [ ];

      extraCommands = ''
        # OmniRoute API: LAN only
        ${mkIpv4AcceptRule homolab.ports.omnirouteApi lanCidr}
        ${mkDropRule homolab.ports.omnirouteApi}

        # Development ports are blocked; routing goes through gateway Traefik.
        ${mkRangeDropRule devPortRange}

        # Explicit LAN DROP for loopback-only services.
        ${mkDropRule homolab.ports.omnirouteDashboard}
        ${mkDropRule homolab.ports.shimmy}
      '';

      extraStopCommands = ''
        ${mkIpv4DeleteRule homolab.ports.omnirouteApi lanCidr}
        ${mkDeleteDropRule homolab.ports.omnirouteApi}

        ${mkDeleteRangeDropRule devPortRange}

        ${mkDeleteDropRule homolab.ports.omnirouteDashboard}
        ${mkDeleteDropRule homolab.ports.shimmy}
      '';
    };
  };
}
