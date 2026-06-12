{ config, homolab, ... }:

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

      server.address = "tcp://127.0.0.1:${toString homolab.ports.authelia}/";

      log = {
        level = "info";
        format = "text";
      };

      authentication_backend.file.path = config.sops.templates."authelia-users-database.yml".path;

      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = homolab.domains.auth;
            policy = "bypass";
          }
          {
            domain = homolab.domains.dns;
            policy = "bypass";
          }
          {
            domain = homolab.domains.grafana;
            policy = "two_factor";
          }
          {
            domain = homolab.domains.home;
            policy = "two_factor";
          }
          {
            domain = homolab.domains.traefik;
            policy = "two_factor";
          }
        ];
      };

      session = {
        cookies = [
          {
            name = "authelia_session";
            domain = homolab.domains.root;
            authelia_url = homolab.urls.auth;
            default_redirection_url = homolab.urls.home;
            expiration = "12h";
            inactivity = "1h";
          }
        ];
      };

      # Postgres moved to lumo; Authelia uses a local SQLite database so that
      # authentication has no dependency on the apps plane.
      storage.local.path = "/var/lib/authelia-main/db.sqlite3";

      notifier = {
        # Resend reachability can flap briefly during switch; don't fail the service
        # startup on a transient DNS/SMTP check.
        disable_startup_check = true;

        smtp = {
          address = "submissions://smtp.resend.com:465";
          username = "resend";
          sender = "Authelia <${homolab.contact.noReplyEmail}>";
          identifier = homolab.domains.auth;
        };
      };

      webauthn = {
        display_name = "JustaSlime";
        timeout = "60 seconds";
        selection_criteria.user_verification = "preferred";
      };
    };
  };
}
