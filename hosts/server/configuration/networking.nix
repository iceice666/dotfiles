{ pkgs, ... }:

let
  lanCidr = "192.168.1.0/24";
  ipset = "${pkgs.ipset}/bin/ipset";

  mkIpv4AcceptRule =
    port: cidr: "iptables -A INPUT -i enp7s0 -p tcp -s ${cidr} --dport ${toString port} -j ACCEPT";

  mkIpv4DeleteRule =
    port: cidr:
    "iptables -D INPUT -i enp7s0 -p tcp -s ${cidr} --dport ${toString port} -j ACCEPT || true";

  mkIpv4SetAcceptRule =
    port:
    "iptables -A INPUT -i enp7s0 -p tcp -m set --match-set cloudflare-v4 src --dport ${toString port} -j ACCEPT";

  mkIpv4SetDeleteRule =
    port:
    "iptables -D INPUT -i enp7s0 -p tcp -m set --match-set cloudflare-v4 src --dport ${toString port} -j ACCEPT || true";

  mkIpv6SetAcceptRule =
    port:
    "ip6tables -A INPUT -i enp7s0 -p tcp -m set --match-set cloudflare-v6 src --dport ${toString port} -j ACCEPT";

  mkIpv6SetDeleteRule =
    port:
    "ip6tables -D INPUT -i enp7s0 -p tcp -m set --match-set cloudflare-v6 src --dport ${toString port} -j ACCEPT || true";
in
{
  networking = {
    hostName = "homolab";
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "8.8.8.8"
    ];
    defaultGateway = "192.168.1.1";
    useDHCP = false;

    networkmanager.enable = true;

    interfaces.enp7s0.ipv4.addresses = [
      {
        address = "192.168.1.127";
        prefixLength = 24;
      }
    ];

    firewall = {
      allowedTCPPorts = [ ];

      extraCommands = ''
        ${ipset} create cloudflare-v4 hash:net family inet -exist
        ${ipset} create cloudflare-v6 hash:net family inet6 -exist

        # Docker bridge: allow local DNS + HTTPS to host services.
        iptables -A INPUT -i docker0 -p udp --dport 53 -j ACCEPT
        iptables -A INPUT -i docker0 -p tcp --dport 53 -j ACCEPT
        iptables -A INPUT -i docker0 -p tcp --dport 443 -j ACCEPT

        # SSH: LAN only
        ${mkIpv4AcceptRule 2222 lanCidr}
        iptables -A INPUT -i enp7s0 -p tcp --dport 2222 -j DROP

        # Forgejo SSH: public
        iptables -A INPUT -i enp7s0 -p tcp --dport 22 -j ACCEPT

        # HTTP/HTTPS: LAN + Cloudflare only
        ${mkIpv4AcceptRule 80 lanCidr}
        ${mkIpv4AcceptRule 443 lanCidr}
        ${mkIpv4SetAcceptRule 80}
        ${mkIpv4SetAcceptRule 443}
        iptables -A INPUT -i enp7s0 -p tcp --dport 80 -j DROP
        iptables -A INPUT -i enp7s0 -p tcp --dport 443 -j DROP

        ${mkIpv6SetAcceptRule 80}
        ${mkIpv6SetAcceptRule 443}
        ip6tables -A INPUT -i enp7s0 -p tcp --dport 80 -j DROP
        ip6tables -A INPUT -i enp7s0 -p tcp --dport 443 -j DROP
      '';

      extraStopCommands = ''
        iptables -D INPUT -i docker0 -p udp --dport 53 -j ACCEPT || true
        iptables -D INPUT -i docker0 -p tcp --dport 53 -j ACCEPT || true
        iptables -D INPUT -i docker0 -p tcp --dport 443 -j ACCEPT || true

        ${mkIpv4DeleteRule 2222 lanCidr}
        iptables -D INPUT -i enp7s0 -p tcp --dport 2222 -j DROP || true

        iptables -D INPUT -i enp7s0 -p tcp --dport 22 -j ACCEPT || true

        ${mkIpv4DeleteRule 80 lanCidr}
        ${mkIpv4DeleteRule 443 lanCidr}
        ${mkIpv4SetDeleteRule 80}
        ${mkIpv4SetDeleteRule 443}
        iptables -D INPUT -i enp7s0 -p tcp --dport 80 -j DROP || true
        iptables -D INPUT -i enp7s0 -p tcp --dport 443 -j DROP || true

        ${mkIpv6SetDeleteRule 80}
        ${mkIpv6SetDeleteRule 443}
        ip6tables -D INPUT -i enp7s0 -p tcp --dport 80 -j DROP || true
        ip6tables -D INPUT -i enp7s0 -p tcp --dport 443 -j DROP || true

        ${ipset} destroy cloudflare-v4 || true
        ${ipset} destroy cloudflare-v6 || true
      '';
    };
  };
}
