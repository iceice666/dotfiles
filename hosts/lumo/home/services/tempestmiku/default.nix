{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/tempestmiku";
  sourceRev = "2cbc3119853f38945e1c6465f89fe79e70d5be81";
  image = "localhost/tempestmiku:${builtins.substring 0 12 sourceRev}";
  openaiBaseUrl = "http://127.0.0.1:${toString homolab.ports.cliproxyapi}/v1";

  replaceTemplate =
    source: replacements:
    let
      names = builtins.attrNames replacements;
    in
    builtins.replaceStrings (map (name: "@${name}@") names) (map (name: replacements.${name}) names) (
      builtins.readFile source
    );

  dockerfile = pkgs.writeText "tempestmiku-Dockerfile" (builtins.readFile ./Dockerfile);
  buildContext = pkgs.runCommand "tempestmiku-empty-build-context" { } ''
    mkdir -p "$out"
  '';
  pushKeyPath = config.sops.secrets.tempestmiku-push-encryption-key.path;
  sharedApiKeyPath = config.sops.secrets.cliproxyapi-shared-api-key.path;

  runner = pkgs.writeScript "lumo-tempestmiku-runner" (
    replaceTemplate ./runner {
      inherit dataDir image;
      podman = "${pkgs.podman}/bin/podman";
    }
  );

  openrcService = pkgs.writeText "lumo-tempestmiku" (
    replaceTemplate ./openrc-service {
      inherit
        dataDir
        image
        openaiBaseUrl
        pushKeyPath
        sharedApiKeyPath
        sourceRev
        ;
      buildContext = toString buildContext;
      dockerfile = toString dockerfile;
      podman = "${pkgs.podman}/bin/podman";
      port = toString homolab.ports.tempestmiku;
      postgresPort = toString homolab.ports.postgresql;
      publicUrl = homolab.urls.miku;
      pushOrigin = homolab.urls.push;
      runner = toString runner;
    }
  );
in
{
  home.packages = [ pkgs.podman ];

  sops.secrets.tempestmiku-push-encryption-key = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/tempestmiku.yaml;
    key = "push_encryption_key";
    mode = "0400";
  };

  sops.secrets.cliproxyapi-shared-api-key = {
    sopsFile = dotfiles + /sensitive/shared/cliproxyapi.yaml;
    key = "apiKey";
    mode = "0400";
  };

  home.activation.lumoTempestMiku =
    lib.hm.dag.entryAfter
      [
        "lumoDirectories"
        "sopsAlpine"
        "lumoDatabase"
        "lumoPodman"
        "lumoCliproxyapi"
        "lumoNtfy"
      ]
      ''
        if ! /usr/bin/getent group tempestmiku >/dev/null; then
          /usr/sbin/addgroup -g 10001 -S tempestmiku
        fi
        if ! /usr/bin/id tempestmiku >/dev/null 2>&1; then
          /usr/sbin/adduser -S -D -H -h ${dataDir} -s /sbin/nologin -G tempestmiku -u 10001 tempestmiku
        fi

        install -d -m 0750 -o tempestmiku -g tempestmiku ${dataDir}
        install -d -m 0700 -o tempestmiku -g tempestmiku ${dataDir}/artifacts
        install -d -m 0700 -o tempestmiku -g tempestmiku ${dataDir}/managed-skills
        install -d -m 0700 -o tempestmiku -g tempestmiku ${dataDir}/managed-mode-addenda

        if ! ${pkgs.util-linux}/bin/runuser -u postgres -- \
          ${pkgs.postgresql_17}/bin/psql -p ${toString homolab.ports.postgresql} -d postgres \
            -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'tempestmiku'" | ${pkgs.gnugrep}/bin/grep -qx 1; then
          ${pkgs.util-linux}/bin/runuser -u postgres -- \
            ${pkgs.postgresql_17}/bin/createuser -p ${toString homolab.ports.postgresql} tempestmiku
        fi
        if ! ${pkgs.util-linux}/bin/runuser -u postgres -- \
          ${pkgs.postgresql_17}/bin/psql -p ${toString homolab.ports.postgresql} -d postgres \
            -tAc "SELECT 1 FROM pg_database WHERE datname = 'tempestmiku'" | ${pkgs.gnugrep}/bin/grep -qx 1; then
          ${pkgs.util-linux}/bin/runuser -u postgres -- \
            ${pkgs.postgresql_17}/bin/createdb -p ${toString homolab.ports.postgresql} \
              --owner=tempestmiku tempestmiku
        fi

        install -Dm755 ${openrcService} /etc/init.d/lumo-tempestmiku
        /sbin/rc-update add lumo-tempestmiku default

        wait_for_tempestmiku_transition() {
          transition_waited=0
          while /sbin/rc-service lumo-tempestmiku status 2>&1 \
            | ${pkgs.gnugrep}/bin/grep -Eq \
              'starting|stopping|Call to flock failed|Resource temporarily unavailable'; do
            if [ "$transition_waited" -ge 1800 ]; then
              echo "timed out waiting for lumo-tempestmiku service transition" >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/sleep 2
            transition_waited=$((transition_waited + 2))
          done
        }

        wait_for_tempestmiku_transition
        if ! /sbin/rc-service --nodeps lumo-tempestmiku stop; then
          /sbin/rc-service lumo-tempestmiku zap
        fi
        wait_for_tempestmiku_transition
        /sbin/rc-service --nodeps lumo-tempestmiku start
      '';
}
