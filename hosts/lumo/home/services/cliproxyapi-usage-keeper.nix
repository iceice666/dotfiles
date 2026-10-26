{
  config,
  dotfiles,
  lab,
  lib,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/cliproxyapi-usage-keeper";
  envPath = "${dataDir}/keeper.env";
  # Digest-pinned so a re-tagged upstream release cannot change what runs.
  image = "ghcr.io/willxup/cpa-usage-keeper:v1.14.5@sha256:8c4c54ed9c7e88eba1ef33e211120244aa75778e34c554f32d93899b43eeb7a5";
  port = lab.ports.cliproxyapiUsageKeeper;

  managementKeyPath = config.sops.secrets.cliproxyapi-management-key.path;
  loginPasswordPath = config.sops.secrets.cliproxyapi-usage-keeper-login-password.path;

  keeperService = pkgs.writeText "lumo-cliproxyapi-usage-keeper" ''
    #!/sbin/openrc-run
    name="lumo-cliproxyapi-usage-keeper"
    description="Lumo CPA Usage Keeper analytics dashboard"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-cliproxyapi-usage-keeper --network=host --env-file=${envPath} --env=SSL_CERT_FILE=/etc/dotfiles-ca.crt --env=SSL_CERT_DIR=/etc/dotfiles-certs --volume=${pkgs.dotfiles-cacert}/etc/ssl/certs/ca-no-trust-rules-bundle.crt:/etc/dotfiles-ca.crt:ro --volume=${pkgs.dotfiles-cacert.hashed}/etc/ssl/certs:/etc/dotfiles-certs:ro -v ${dataDir}/data:/data ${image}"
    command_user="root"
    output_log="/var/log/lumo/cliproxyapi-usage-keeper.log"
    error_log="/var/log/lumo/cliproxyapi-usage-keeper.log"
    respawn_delay=10
    respawn_max=0

    depend() {
      need lumo-podman lumo-cliproxyapi
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/cliproxyapi-usage-keeper.log
      checkpath -d -m 0700 -o root:root ${dataDir}
      checkpath -d -m 0750 -o root:root ${dataDir}/data
      if ! ${pkgs.podman}/bin/podman image exists ${image}; then
        ${pkgs.podman}/bin/podman pull ${image} >&2
      fi
    }
  '';
in
{
  home.packages = [ pkgs.podman ];

  sops.secrets.cliproxyapi-management-key = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/cliproxyapi.yaml;
    key = "managementKey";
    mode = "0400";
  };

  sops.secrets.cliproxyapi-usage-keeper-login-password = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/cliproxyapi.yaml;
    key = "keeperLoginPassword";
    mode = "0400";
  };

  home.activation.lumoCliproxyapiUsageKeeper =
    lib.hm.dag.entryAfter [ "lumoDirectories" "sopsAlpine" "lumoPodman" "lumoCliproxyapi" ]
      ''
        install -d -m 0700 -o root -g root ${dataDir}
        install -d -m 0750 -o root -g root ${dataDir}/data

        management_key="$(cat '${managementKeyPath}')"
        login_password="$(cat '${loginPasswordPath}')"
        {
          printf 'CPA_BASE_URL=http://127.0.0.1:${toString lab.ports.cliproxyapi}\n'
          printf 'CPA_MANAGEMENT_KEY=%s\n' "$management_key"
          printf 'REDIS_QUEUE_ADDR=127.0.0.1:${toString lab.ports.cliproxyapi}\n'
          printf 'APP_HOST=127.0.0.1\n'
          printf 'APP_PORT=${toString port}\n'
          printf 'APP_BASE_PATH=/keeper\n'
          printf 'AUTH_ENABLED=true\n'
          printf 'LOGIN_PASSWORD=%s\n' "$login_password"
          printf 'TZ=Asia/Taipei\n'
          printf 'WORK_DIR=/data\n'
          printf 'TRUSTED_PROXY_CIDRS=127.0.0.1/32\n'
        } > ${envPath}
        chmod 0400 ${envPath}

        install -Dm755 ${keeperService} /etc/init.d/lumo-cliproxyapi-usage-keeper
        /sbin/rc-update add lumo-cliproxyapi-usage-keeper default
        /sbin/rc-service lumo-cliproxyapi-usage-keeper restart
      '';
}
