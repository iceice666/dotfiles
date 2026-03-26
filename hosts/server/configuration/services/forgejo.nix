{
  config,
  lib,
  pkgs,
  ...
}:

let
  rustfsEndpoint = "127.0.0.1:9100";
in
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
    after = [
      "rustfs.service"
      "rustfs-init.service"
    ];
    requires = [
      "rustfs.service"
      "rustfs-init.service"
    ];

    serviceConfig = {
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
      # PrivateUsers breaks CAP_NET_BIND_SERVICE for low ports.
      PrivateUsers = lib.mkForce false;
    };
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
      passwordFile = config.sops.secrets."forgejo-db-password".path;
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
        SSH_DOMAIN = "git.justaslime.dev";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3000;
        ROOT_URL = "https://code.justaslime.dev/";
        START_SSH_SERVER = true;
        DISABLE_SSH = false;
        SSH_PORT = 22;
        SSH_LISTEN_PORT = 22;
        LFS_HTTP_AUTH_EXPIRY = "180m";
        LFS_START_SERVER = true;
        OFFLINE_MODE = false;
      };

      database = {
        LOG_SQL = false;
      };

      api.MAX_RESPONSE_ITEMS = 50;

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

      webhook.ALLOWED_HOST_LIST = "external,loopback";

      security = {
        INSTALL_LOCK = true;
        REVERSE_PROXY_LIMIT = 1;
        REVERSE_PROXY_TRUSTED_PROXIES = "127.0.0.0/8,::1/128";
        PASSWORD_HASH_ALGO = "pbkdf2_hi";
      };

      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
        REGISTER_EMAIL_CONFIRM = false;
        ENABLE_NOTIFY_MAIL = true;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
        ENABLE_CAPTCHA = false;
        DEFAULT_KEEP_EMAIL_PRIVATE = false;
        DEFAULT_ALLOW_CREATE_ORGANIZATION = true;
        DEFAULT_ENABLE_TIMETRACKING = true;
        NO_REPLY_ADDRESS = "noreply.justaslime.dev";
      };

      lfs = {
        STORAGE_TYPE = "minio";
        MINIO_ENDPOINT = rustfsEndpoint;
        MINIO_BUCKET = "forgejo-lfs";
        MINIO_BUCKET_LOOKUP = "path";
        MINIO_LOCATION = "us-east-1";
        MINIO_USE_SSL = false;
        SERVE_DIRECT = false;
      };

      mailer = {
        ENABLED = true;
        PROTOCOL = "smtps";
        SMTP_ADDR = "smtp.resend.com";
        SMTP_PORT = 465;
        FROM = "Forgejo <noreply@justaslime.dev>";
        USER = "resend";
      };

      openid = {
        ENABLE_OPENID_SIGNIN = true;
        ENABLE_OPENID_SIGNUP = true;
      };

      packages.ENABLED = true;

      "cron.update_checker".ENABLED = true;

      "repository.pull-request".DEFAULT_MERGE_STYLE = "merge";

      "repository.signing".DEFAULT_TRUST_MODEL = "committer";
    };

    secrets = {
      server.LFS_JWT_SECRET = lib.mkForce config.sops.secrets."forgejo-lfs-jwt-secret".path;

      lfs = {
        MINIO_ACCESS_KEY_ID = lib.mkForce config.sops.secrets."rustfs-access-key".path;
        MINIO_SECRET_ACCESS_KEY = lib.mkForce config.sops.secrets."rustfs-secret-key".path;
      };

      security = {
        INTERNAL_TOKEN = lib.mkForce config.sops.secrets."forgejo-internal-token".path;
        SECRET_KEY = lib.mkForce config.sops.secrets."forgejo-secret-key".path;
      };

      mailer.PASSWD = lib.mkForce config.sops.secrets."forgejo-mailer-password".path;

      oauth2.JWT_SECRET = lib.mkForce config.sops.secrets."forgejo-oauth2-jwt-secret".path;
    };
  };
}
