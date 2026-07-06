{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:

let
  autheliaPackage = unstablePkgs.authelia;
  autheliaPort = homolab.ports.authelia;

  jwtSecretPath = config.sops.secrets.authelia-jwt-secret.path;
  storageKeyPath = config.sops.secrets.authelia-storage-encryption-key.path;
  userHashPath = config.sops.secrets.authelia-user-password-hash.path;
  smtpPasswordPath = config.sops.secrets.authelia-smtp-password.path;

  autheliaConfig = (pkgs.formats.yaml { }).generate "authelia.yml" {
    theme = "auto";
    default_2fa_method = "webauthn";

    server.address = "tcp://127.0.0.1:${toString autheliaPort}/";

    log = {
      level = "info";
      format = "text";
    };

    # Users database is staged to /run/lumo-authelia/ in start_pre.
    authentication_backend.file.path = "/run/lumo-authelia/users-database.yml";

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
        {
          domain = homolab.domains.analytics;
          policy = "two_factor";
        }
        {
          domain = homolab.domains.cliproxyapi;
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

    storage.local.path = "/var/lib/authelia/db.sqlite3";

    notifier = {
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

  # Authelia supports *_FILE env var variants for all secrets.
  autheliaService = pkgs.writeText "lumo-authelia" ''
    #!/sbin/openrc-run
    name="lumo-authelia"
    description="Lumo Authelia SSO"
    supervisor=supervise-daemon
    command="${autheliaPackage}/bin/authelia"
    command_args="--config ${autheliaConfig}"
    directory="/var/lib/authelia"
    output_log="/var/log/lumo/authelia.log"
    error_log="/var/log/lumo/authelia.log"
    respawn_delay=5
    respawn_max=0
    supervise_daemon_args="-e AUTHELIA_JWT_SECRET_FILE=${jwtSecretPath} -e AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE=${storageKeyPath} -e AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE=${smtpPasswordPath}"

    depend() {
      need net
    }

    start_pre() {
      checkpath -d -m 0755 -o root:root /var/log/lumo
      checkpath -d -m 0700 -o root:root /var/lib/authelia
      checkpath -f -m 0640 -o root:root /var/log/lumo/authelia.log
      checkpath -d -m 0755 -o root:root /run/lumo-authelia

      # Render users database with the hashed password from the sops secret.
      user_hash="$(cat '${userHashPath}')"
      printf 'users:\n  iceice666:\n    disabled: false\n    displayname: iceice666\n    password: '"'"'%s'"'"'\n    email: %s\n    groups:\n      - admins\n' \
        "$user_hash" "${homolab.contact.adminEmail}" > /run/lumo-authelia/users-database.yml
      chmod 0600 /run/lumo-authelia/users-database.yml
    }
  '';
in
{
  sops.secrets = {
    authelia-jwt-secret = {
      sopsFile = dotfiles + /sensitive/hosts/lumo/authelia.yaml;
      key = "jwtSecret";
      mode = "0400";
    };

    authelia-storage-encryption-key = {
      sopsFile = dotfiles + /sensitive/hosts/lumo/authelia.yaml;
      key = "storageEncryptionKey";
      mode = "0400";
    };

    authelia-user-password-hash = {
      sopsFile = dotfiles + /sensitive/hosts/lumo/authelia.yaml;
      key = "userPasswordHash";
      mode = "0400";
    };

    authelia-smtp-password = {
      sopsFile = dotfiles + /sensitive/hosts/lumo/resend.yaml;
      key = "apiKey";
      mode = "0400";
    };
  };

  home.activation.lumoAuthelia = lib.hm.dag.entryAfter [ "sopsAlpine" ] ''
    install -Dm755 ${autheliaService} /etc/init.d/lumo-authelia
    /sbin/rc-update add lumo-authelia default
    /sbin/rc-service lumo-authelia restart
  '';
}
