{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/cliproxyapi-usage-keeper";
  envPath = "${dataDir}/keeper.env";
  image = "ghcr.io/willxup/cpa-usage-keeper:v1.14.5";
  port = homolab.ports.cliproxyapiUsageKeeper;

  managementKeyPath = config.sops.secrets.cliproxyapi-management-key.path;
  loginPasswordPath = config.sops.secrets.cliproxyapi-usage-keeper-login-password.path;

  keeperService = pkgs.writeText "lumo-cliproxyapi-usage-keeper" ''
    #!/sbin/openrc-run
    name="lumo-cliproxyapi-usage-keeper"
    description="Lumo CPA Usage Keeper analytics dashboard"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-cliproxyapi-usage-keeper --network=host --env-file=${envPath} -v ${dataDir}/data:/data ${image}"
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
          printf 'CPA_BASE_URL=http://127.0.0.1:${toString homolab.ports.cliproxyapi}\n'
          printf 'CPA_MANAGEMENT_KEY=%s\n' "$management_key"
          printf 'REDIS_QUEUE_ADDR=127.0.0.1:${toString homolab.ports.cliproxyapi}\n'
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
