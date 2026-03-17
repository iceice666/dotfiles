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

  services.redis = {
    package = pkgs.valkey;

    servers."" = {
      enable = true;
      port = 6379;

      settings = {
        appendonly = "no";
      };
    };
  };
}
