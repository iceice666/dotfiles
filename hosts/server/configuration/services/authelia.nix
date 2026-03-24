{ config, ... }:

{
  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile = config.sops.secrets."authelia-jwt-secret".path;
      storageEncryptionKeyFile = config.sops.secrets."authelia-storage-encryption-key".path;
    };

    environmentVariables.AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE =
      config.sops.secrets."authelia-smtp-password".path;

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

      notifier.smtp = {
        address = "submissions://smtp.resend.com:465";
        username = "resend";
        sender = "Authelia <noreply@justaslime.dev>";
        identifier = "auth.justaslime.dev";
        startup_check_address = "iceice666@justaslime.dev";
      };

      webauthn = {
        display_name = "JustaSlime";
        timeout = "60 seconds";
        selection_criteria.user_verification = "preferred";
      };
    };
  };
}
