{ ... }:

{
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = true;

    settings = {
      address = "/justaslime.dev/127.0.0.1";
      bind-interfaces = true;
      listen-address = "127.0.0.1";
    };
  };
}
