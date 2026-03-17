{ config, pkgs, ... }:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = false;

    # Create the databases and users automatically on startup
    ensureDatabases = [
      "forgejo"
      "atcb"
    ];
    ensureUsers = [
      {
        name = "forgejo";
        ensureDBOwnership = true;
      }
      {
        name = "atcb";
        ensureDBOwnership = true;
      }
    ];

    # Socket-only access for local services on this host
    authentication = pkgs.lib.mkOverride 10 ''
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      local   all             all                                     trust
    '';
  };

  # Native Valkey (Redis-compatible)
  services.valkey = {
    enable = true;
    settings = {
      port = 6379;
      appendonly = "no";
    };
  };
}
