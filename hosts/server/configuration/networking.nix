{ ... }:

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

    firewall.allowedTCPPorts = [ 2222 ];
  };
}
