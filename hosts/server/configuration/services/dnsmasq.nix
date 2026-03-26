{ ... }:

{
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = true;

    settings = {
      address = "/justaslime.dev/172.17.0.1";
      local = "/justaslime.dev/";
      bind-interfaces = true;
      listen-address = [
        "127.0.0.1"
        "172.17.0.1"
      ];
    };
  };
}
