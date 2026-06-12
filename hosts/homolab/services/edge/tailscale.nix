{
  config,
  unstablePkgs,
  ...
}:

{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    package = unstablePkgs.tailscale;
    permitCertUid = "traefik";

    # Keep any previously advertised subnet routes cleared declaratively.
    # Enable Tailscale SSH in place of the regular OpenSSH daemon.
    extraSetFlags = [
      "--advertise-routes="
      "--ssh"
    ];
  };

  # Treat the tailnet as a LAN-equivalent management network. The lower-level
  # iptables rules document selected admin ports, but this NixOS firewall trust
  # rule intentionally accepts traffic from tailscale0 broadly.
  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
}
