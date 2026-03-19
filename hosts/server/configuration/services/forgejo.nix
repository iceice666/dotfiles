{ lib, pkgs, ... }:

{
  systemd.mounts = [
    {
      what = "/mnt/storage/forgejo/forgejo_data";
      where = "/var/lib/forgejo";
      options = "bind";
      wantedBy = [ "multi-user.target" ];
    }
  ];

  systemd.services.forgejo = {
    unitConfig.RequiresMountsFor = "/var/lib/forgejo";
  };

  systemd.services.forgejo-secrets.script = lib.mkForce ''
    for path in \
      /run/keys/forgejo-secret-key \
      /run/keys/forgejo-internal-token \
      /run/keys/forgejo-oauth2-jwt-secret \
      /run/keys/forgejo-lfs-jwt-secret
    do
      if [ ! -s "$path" ]; then
        echo "missing Forgejo secret: $path" >&2
        exit 1
      fi
    done
  '';

  systemd.services.forgejo-secrets.serviceConfig = {
    User = lib.mkForce "root";
    Group = lib.mkForce "root";
    ReadWritePaths = lib.mkForce [ ];
  };

  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;
    useWizard = false;

    lfs.enable = true;

    stateDir = "/var/lib/forgejo";

    database = {
      type = "postgres";
      createDatabase = false;
      socket = "/run/postgresql";
      name = "forgejo";
      user = "forgejo";
      passwordFile = "/run/keys/forgejo-db-password";
    };

    settings = {
      DEFAULT = {
        APP_NAME = "Forgejo";
        RUN_MODE = "prod";
        APP_SLOGAN = "Beyond coding. We Forge.";
        RUN_USER = "forgejo";
        WORK_PATH = "/var/lib/forgejo";
      };

      repository.ROOT = "/var/lib/forgejo/repositories";

      "repository.local".LOCAL_COPY_PATH = "/var/lib/forgejo/data/tmp/local-repo";

      "repository.upload".TEMP_PATH = "/var/lib/forgejo/data/uploads";

      server = {
        APP_DATA_PATH = "/var/lib/forgejo/data";
        DOMAIN = "code.justaslime.dev";
        SSH_DOMAIN = "justaslime.dev";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3000;
        ROOT_URL = "https://code.justaslime.dev/";
        DISABLE_SSH = false;
        SSH_PORT = 22;
        SSH_LISTEN_PORT = 22;
        LFS_START_SERVER = true;
        OFFLINE_MODE = false;
      };

      database = {
        LOG_SQL = false;
      };

      indexer.ISSUE_INDEXER_PATH = "/var/lib/forgejo/data/indexers/issues.bleve";

      session = {
        PROVIDER_CONFIG = "/var/lib/forgejo/data/sessions";
        PROVIDER = "file";
      };

      picture = {
        AVATAR_UPLOAD_PATH = "/var/lib/forgejo/data/avatars";
        REPOSITORY_AVATAR_UPLOAD_PATH = "/var/lib/forgejo/data/repo-avatars";
      };

      attachment.PATH = "/var/lib/forgejo/data/attachments";

      log = {
        MODE = "console";
        LEVEL = "Info";
        ROOT_PATH = "/var/lib/forgejo/data/log";
      };

      security = {
        INSTALL_LOCK = true;
        REVERSE_PROXY_LIMIT = 1;
        REVERSE_PROXY_TRUSTED_PROXIES = "*";
        PASSWORD_HASH_ALGO = "pbkdf2_hi";
      };

      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
        REGISTER_EMAIL_CONFIRM = false;
        ENABLE_NOTIFY_MAIL = false;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
        ENABLE_CAPTCHA = false;
        DEFAULT_KEEP_EMAIL_PRIVATE = false;
        DEFAULT_ALLOW_CREATE_ORGANIZATION = true;
        DEFAULT_ENABLE_TIMETRACKING = true;
        NO_REPLY_ADDRESS = "noreply.localhost";
      };

      lfs.PATH = "/var/lib/forgejo/data/lfs";

      mailer.ENABLED = false;

      openid = {
        ENABLE_OPENID_SIGNIN = true;
        ENABLE_OPENID_SIGNUP = true;
      };

      "cron.update_checker".ENABLED = true;

      "repository.pull-request".DEFAULT_MERGE_STYLE = "merge";

      "repository.signing".DEFAULT_TRUST_MODEL = "committer";
    };

    secrets = {
      server.LFS_JWT_SECRET = lib.mkForce "/run/keys/forgejo-lfs-jwt-secret";

      security = {
        INTERNAL_TOKEN = lib.mkForce "/run/keys/forgejo-internal-token";
        SECRET_KEY = lib.mkForce "/run/keys/forgejo-secret-key";
      };

      oauth2.JWT_SECRET = lib.mkForce "/run/keys/forgejo-oauth2-jwt-secret";
    };
  };
}
