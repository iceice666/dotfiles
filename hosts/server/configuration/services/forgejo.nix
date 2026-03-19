{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [ ];

  systemd.mounts = [
    {
      what = "/mnt/storage/forgejo/forgejo_data/app.ini";
      where = "/etc/forgejo/app.ini";
      options = "bind";
      wantedBy = [ "multi-user.target" ];
    }
    {
      what = "/mnt/storage/forgejo/forgejo_data";
      where = "/var/lib/forgejo";
      options = "bind";
      wantedBy = [ "multi-user.target" ];
    }
    {
      what = "/mnt/storage/forgejo/runner_data";
      where = "/var/lib/forgejo-runner";
      options = "bind";
      wantedBy = [ "multi-user.target" ];
    }
  ];

  systemd.services = {
    "forgejo" = {
      unitConfig.RequiresMountsFor = "/etc/forgejo/app.ini";
    };

    "forgejo-secrets" = {
      unitConfig.RequiresMountsFor = "/var/lib/forgejo";
    };
  };

  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;

    lfs = {
      enable = true;
    };

    settings = {
      server = {
        DOMAIN = "code.justaslime.dev";
        ROOT_URL = "https://code.justaslime.dev/";
        HTTP_ADDR = "192.168.1.127";
        HTTP_PORT = 3080;
        SSH_PORT = 2244;
        DISABLE_SSH = false;
      };
      database = {
        DB_TYPE = lib.mkForce "postgres";
        HOST = "/run/postgresql";
        NAME = "forgejo";
        USER = "forgejo";
      };
      security = {
        INSTALL_LOCK = true;
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
      "repository.pull-request" = {
        DEFAULT_MERGE_STYLE = "merge";
      };

      "repository.signing" = {
        DEFAULT_TRUST_MODEL = "committer";
      };

      openid = {
        ENABLE_OPENID_SIGNIN = true;
        ENABLE_OPENID_SIGNUP = true;
      };

      "cron.update_checker" = {
        ENABLED = true;
      };

      log = {
        LEVEL = "Info";
      };
    };

    useWizard = false;
    stateDir = "/var/lib/forgejo";
  };

  users.users.forgejo = {
    isSystemUser = true;
    group = "forgejo";
    description = "Forgejo Git Service";
  };

  users.groups.forgejo = { };

  environment.systemPackages = [
  ];
}
