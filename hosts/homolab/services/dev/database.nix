{
  config,
  homolab,
  pkgs,
  ...
}:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = false;
    settings.port = homolab.ports.postgresql;

    # Create the databases and users automatically on startup
    ensureDatabases = [
      "authelia"
    ];
    ensureUsers = [
      {
        name = "authelia";
        ensureDBOwnership = true;
      }
    ];

    # Restrict socket auth to the service accounts that actually need it.
    authentication = pkgs.lib.mkForce ''
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      local   all             postgres                                peer map=postgres
      local   authelia        authelia                                peer map=authelia
      local   all             all                                     reject
    '';

    identMap = pkgs.lib.mkForce ''
      postgres postgres postgres
      authelia authelia-main authelia
    '';
  };

  services.redis = {
    package = pkgs.valkey;

    servers."" = {
      enable = true;
      port = 6379;

      requirePassFile = config.sops.secrets."valkey-requirepass".path;

      settings = {
        appendonly = "yes";
        bind = "127.0.0.1";
        rename-command = [
          "CONFIG \"\""
          "MODULE \"\""
          "SLAVEOF \"\""
          "DEBUG \"\""
        ];
      };
    };
  };
}
