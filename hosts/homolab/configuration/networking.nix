{ pkgs, homolab, ... }:

let
  inherit (homolab.network) interface;
  lanCidr = homolab.network.lan.cidr;
  devPortRange = homolab.portRanges.dev;
  ipset = "${pkgs.ipset}/bin/ipset";

  mkIpv4AcceptRule =
    port: cidr:
    "iptables -A INPUT -i ${interface} -p tcp -s ${cidr} --dport ${toString port} -j ACCEPT";

  mkIpv4DeleteRule =
    port: cidr:
    "iptables -D INPUT -i ${interface} -p tcp -s ${cidr} --dport ${toString port} -j ACCEPT || true";

  mkIpv4RangeAcceptRule =
    range: cidr:
    "iptables -A INPUT -i ${interface} -p tcp -s ${cidr} --dport ${toString range.from}:${toString range.to} -j ACCEPT";

  mkIpv4RangeDeleteRule =
    range: cidr:
    "iptables -D INPUT -i ${interface} -p tcp -s ${cidr} --dport ${toString range.from}:${toString range.to} -j ACCEPT || true";

  mkIpv4SetAcceptRule =
    port:
    "iptables -A INPUT -i ${interface} -p tcp -m set --match-set cloudflare-v4 src --dport ${toString port} -j ACCEPT";

  mkIpv4SetDeleteRule =
    port:
    "iptables -D INPUT -i ${interface} -p tcp -m set --match-set cloudflare-v4 src --dport ${toString port} -j ACCEPT || true";

  mkIpv6SetAcceptRule =
    port:
    "ip6tables -A INPUT -i ${interface} -p tcp -m set --match-set cloudflare-v6 src --dport ${toString port} -j ACCEPT";

  mkIpv6SetDeleteRule =
    port:
    "ip6tables -D INPUT -i ${interface} -p tcp -m set --match-set cloudflare-v6 src --dport ${toString port} -j ACCEPT || true";

  mkDropRule = port: "iptables -A INPUT -i ${interface} -p tcp --dport ${toString port} -j DROP";

  mkDeleteDropRule =
    port: "iptables -D INPUT -i ${interface} -p tcp --dport ${toString port} -j DROP || true";

  mkRangeDropRule =
    range:
    "iptables -A INPUT -i ${interface} -p tcp --dport ${toString range.from}:${toString range.to} -j DROP";

  mkDeleteRangeDropRule =
    range:
    "iptables -D INPUT -i ${interface} -p tcp --dport ${toString range.from}:${toString range.to} -j DROP || true";

  mkTailscaleAcceptRule =
    port: "iptables -A INPUT -i tailscale0 -p tcp --dport ${toString port} -j ACCEPT";

  mkTailscaleDeleteRule =
    port: "iptables -D INPUT -i tailscale0 -p tcp --dport ${toString port} -j ACCEPT || true";

  mkTailscaleRangeAcceptRule =
    range:
    "iptables -A INPUT -i tailscale0 -p tcp --dport ${toString range.from}:${toString range.to} -j ACCEPT";

  mkTailscaleRangeDeleteRule =
    range:
    "iptables -D INPUT -i tailscale0 -p tcp --dport ${toString range.from}:${toString range.to} -j ACCEPT || true";
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
        ${ipset} create cloudflare-v4 hash:net family inet -exist
        ${ipset} create cloudflare-v6 hash:net family inet6 -exist

        # DNS: LAN only
        iptables -A INPUT -i ${interface} -p udp -s ${lanCidr} --dport 53 -j ACCEPT
        iptables -A INPUT -i ${interface} -p tcp -s ${lanCidr} --dport 53 -j ACCEPT
        iptables -A INPUT -i ${interface} -p udp --dport 53 -j DROP
        iptables -A INPUT -i ${interface} -p tcp --dport 53 -j DROP

        # SSH: LAN only
        ${mkIpv4AcceptRule homolab.ports.ssh lanCidr}
        iptables -A INPUT -i ${interface} -p tcp --dport ${toString homolab.ports.ssh} -j DROP

        # HTTP/HTTPS: LAN + Cloudflare only
        ${mkIpv4AcceptRule 80 lanCidr}
        ${mkIpv4AcceptRule 443 lanCidr}
        ${mkIpv4SetAcceptRule 80}
        ${mkIpv4SetAcceptRule 443}
        iptables -A INPUT -i ${interface} -p tcp --dport 80 -j DROP
        iptables -A INPUT -i ${interface} -p tcp --dport 443 -j DROP

        # OmniRoute API: LAN only
        ${mkIpv4AcceptRule homolab.ports.omnirouteApi lanCidr}
        ${mkDropRule homolab.ports.omnirouteApi}

        # Development ports are exposed via Traefik HTTPS only (no direct ingress on raw ports).
        ${mkRangeDropRule devPortRange}

        # Explicit DROP for loopback-only services (defense in depth)
        ${mkDropRule homolab.ports.authelia}
        ${mkDropRule homolab.ports.omnirouteDashboard}
        ${mkDropRule homolab.ports.shimmy}
        ${mkDropRule homolab.ports.technitium}
        ${mkDropRule homolab.ports.technitiumDoh}
        ${mkDropRule homolab.ports.dynacat}
        ${mkDropRule homolab.ports.devPortProxy}
        ${mkDropRule homolab.ports.traefikPing}
        ${mkDropRule homolab.ports.traefikMetrics}
        ${mkDropRule homolab.ports.prometheus}
        ${mkDropRule homolab.ports.grafana}

        # Tailscale: document selected admin and dev paths. The tailnet
        # interface itself is trusted in services/edge/tailscale.nix.
        ${mkTailscaleAcceptRule 80}
        ${mkTailscaleAcceptRule 443}
        # Development ports are intentionally not exposed on tailscale by raw port.

        ${mkIpv6SetAcceptRule 80}
        ${mkIpv6SetAcceptRule 443}
        ip6tables -A INPUT -i ${interface} -p tcp --dport 80 -j DROP
        ip6tables -A INPUT -i ${interface} -p tcp --dport 443 -j DROP
      '';

      extraStopCommands = ''
        iptables -D INPUT -i ${interface} -p udp -s ${lanCidr} --dport 53 -j ACCEPT || true
        iptables -D INPUT -i ${interface} -p tcp -s ${lanCidr} --dport 53 -j ACCEPT || true
        iptables -D INPUT -i ${interface} -p udp --dport 53 -j DROP || true
        iptables -D INPUT -i ${interface} -p tcp --dport 53 -j DROP || true

        ${mkIpv4DeleteRule homolab.ports.ssh lanCidr}
        iptables -D INPUT -i ${interface} -p tcp --dport ${toString homolab.ports.ssh} -j DROP || true

        ${mkIpv4DeleteRule 80 lanCidr}
        ${mkIpv4DeleteRule 443 lanCidr}
        ${mkIpv4SetDeleteRule 80}
        ${mkIpv4SetDeleteRule 443}
        iptables -D INPUT -i ${interface} -p tcp --dport 80 -j DROP || true
        iptables -D INPUT -i ${interface} -p tcp --dport 443 -j DROP || true

        ${mkIpv4DeleteRule homolab.ports.omnirouteApi lanCidr}
        ${mkDeleteDropRule homolab.ports.omnirouteApi}

        ${mkDeleteRangeDropRule devPortRange}

        ${mkDeleteDropRule homolab.ports.authelia}
        ${mkDeleteDropRule homolab.ports.omnirouteDashboard}
        ${mkDeleteDropRule homolab.ports.shimmy}
        ${mkDeleteDropRule homolab.ports.technitium}
        ${mkDeleteDropRule homolab.ports.technitiumDoh}
        ${mkDeleteDropRule homolab.ports.dynacat}
        ${mkDeleteDropRule homolab.ports.devPortProxy}
        ${mkDeleteDropRule homolab.ports.traefikPing}
        ${mkDeleteDropRule homolab.ports.traefikMetrics}
        ${mkDeleteDropRule homolab.ports.prometheus}
        ${mkDeleteDropRule homolab.ports.grafana}

        ${mkTailscaleDeleteRule 80}
        ${mkTailscaleDeleteRule 443}
        # Development ports remain blocked by default; only Traefik HTTPS path-based routing remains enabled.

        ${mkIpv6SetDeleteRule 80}
        ${mkIpv6SetDeleteRule 443}
        ip6tables -D INPUT -i ${interface} -p tcp --dport 80 -j DROP || true
        ip6tables -D INPUT -i ${interface} -p tcp --dport 443 -j DROP || true

        ${ipset} destroy cloudflare-v4 || true
        ${ipset} destroy cloudflare-v6 || true
      '';
    };
  };
}
