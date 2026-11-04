{
  config,
  dotfiles,
  lab,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:

let
  autheliaPackage = unstablePkgs.authelia;
  autheliaPort = lab.ports.authelia;

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
          domain = lab.domains.auth;
          policy = "bypass";
        }
        {
          domain = lab.domains.dns;
          policy = "bypass";
        }
        {
          domain = lab.domains.home;
          policy = "two_factor";
        }
        {
          domain = lab.domains.pirc;
          policy = "two_factor";
        }
        {
          domain = lab.domains.traefik;
          policy = "two_factor";
        }
        {
          domain = lab.domains.analytics;
          policy = "two_factor";
        }
        {
          domain = lab.domains.cliproxyapi;
          policy = "two_factor";
        }
        {
          domain = lab.domains.learnharness;
          policy = "two_factor";
        }
      ];
    };

    # The portal is reachable from the public internet (bypass policy on the
    # auth domain); this is the only brute-force limiter in front of it.
    regulation = {
      max_retries = 3;
      find_time = "2m";
      ban_time = "10m";
    };

    session = {
      cookies = [
        {
          name = "authelia_session";
          domain = lab.domains.root;
          authelia_url = lab.urls.auth;
          default_redirection_url = lab.urls.home;
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
        sender = "Authelia <${lab.contact.noReplyEmail}>";
        identifier = lab.domains.auth;
      };
    };

    webauthn = {
      display_name = "JustaSlime";
      timeout = "60 seconds";
      selection_criteria.user_verification = "preferred";
    };
  };

  # Authelia runs as the unprivileged `authelia` account. The sops secrets
  # under /run/secrets stay root-only (the standalone HM sops module has no
  # per-secret owner), so start_pre (root) stages 0400 copies into the
  # service's private runtime directory and Authelia reads them via *_FILE.
  runDir = "/run/lumo-authelia";
  autheliaService = pkgs.writeText "lumo-authelia" ''
    #!/sbin/openrc-run
    name="lumo-authelia"
    description="Lumo Authelia SSO"
    supervisor=supervise-daemon
    command="${autheliaPackage}/bin/authelia"
    command_args="--config ${autheliaConfig}"
    command_user="authelia:authelia"
    directory="/var/lib/authelia"
    output_log="/var/log/lumo/authelia.log"
    error_log="/var/log/lumo/authelia.log"
    respawn_delay=5
    respawn_max=0
    supervise_daemon_args="-e AUTHELIA_JWT_SECRET_FILE=${runDir}/jwt-secret -e AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE=${runDir}/storage-encryption-key -e AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE=${runDir}/smtp-password"

    depend() {
      need net
    }

    start_pre() {
      checkpath -d -m 0755 -o root:root /var/log/lumo
      checkpath -d -m 0700 -o authelia:authelia /var/lib/authelia
      # Migrate state written by earlier root-run generations.
      chown -R authelia:authelia /var/lib/authelia
      checkpath -f -m 0640 -o authelia:authelia /var/log/lumo/authelia.log
      checkpath -d -m 0700 -o authelia:authelia ${runDir}

      install -m 0400 -o authelia -g authelia '${jwtSecretPath}' ${runDir}/jwt-secret
      install -m 0400 -o authelia -g authelia '${storageKeyPath}' ${runDir}/storage-encryption-key
      install -m 0400 -o authelia -g authelia '${smtpPasswordPath}' ${runDir}/smtp-password

      # Render users database with the hashed password from the sops secret.
      user_hash="$(cat '${userHashPath}')"
      printf 'users:\n  iceice666:\n    disabled: false\n    displayname: iceice666\n    password: '"'"'%s'"'"'\n    email: %s\n    groups:\n      - admins\n' \
        "$user_hash" "${lab.contact.adminEmail}" > ${runDir}/users-database.yml
      chown authelia:authelia ${runDir}/users-database.yml
      chmod 0400 ${runDir}/users-database.yml
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
    if ! /usr/bin/getent group authelia >/dev/null; then
      /usr/sbin/addgroup -S authelia
    fi
    if ! /usr/bin/id authelia >/dev/null 2>&1; then
      /usr/sbin/adduser -S -D -H -h /var/lib/authelia -s /sbin/nologin -G authelia authelia
    fi

    install -Dm755 ${autheliaService} /etc/init.d/lumo-authelia
    /sbin/rc-update add lumo-authelia default
    /sbin/rc-service lumo-authelia restart
  '';
}
