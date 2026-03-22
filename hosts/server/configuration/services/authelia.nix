{ config, ... }:

{
  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile = config.sops.secrets."authelia-jwt-secret".path;
      storageEncryptionKeyFile = config.sops.secrets."authelia-storage-encryption-key".path;
    };

    settings = {
      theme = "auto";
      default_2fa_method = "webauthn";

      server.address = "tcp://127.0.0.1:9091/";

      log = {
        level = "info";
        format = "text";
      };

      authentication_backend.file.path = config.sops.templates."authelia-users-database.yml".path;

      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = "auth.justaslime.dev";
            policy = "bypass";
          }
          {
            domain = "code.justaslime.dev";
            policy = "two_factor";
          }
          {
            domain = "ci.justaslime.dev";
            policy = "two_factor";
          }
        ];
      };

      session = {
        cookies = [
          {
            name = "authelia_session";
            domain = "justaslime.dev";
            authelia_url = "https://auth.justaslime.dev";
            default_redirection_url = "https://code.justaslime.dev";
            expiration = "12h";
            inactivity = "1h";
          }
        ];
      };

      storage.postgres = {
        address = "unix:///run/postgresql";
        database = "authelia";
        username = "authelia";
      };

      notifier.filesystem.filename = "/var/lib/authelia-main/notifications.txt";

      webauthn = {
        display_name = "JustaSlime";
        timeout = "60 seconds";
        selection_criteria.user_verification = "preferred";
      };
    };
  };
}
