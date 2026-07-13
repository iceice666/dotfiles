{
  homolab,
  lib,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/ntfy";
  ntfyImage = "docker.io/binwiederhier/ntfy:v2.23.0";
  ntfyEnv = pkgs.writeText "lumo-ntfy.env" ''
    NTFY_BASE_URL=${homolab.urls.push}
    NTFY_LISTEN_HTTP=127.0.0.1:${toString homolab.ports.ntfy}
    NTFY_CACHE_FILE=${dataDir}/cache.db
    NTFY_CACHE_DURATION=1h
    NTFY_AUTH_FILE=${dataDir}/auth.db
    NTFY_AUTH_DEFAULT_ACCESS=deny-all
    NTFY_AUTH_ACCESS=*:up*:rw
    NTFY_BEHIND_PROXY=true
    NTFY_ENABLE_LOGIN=false
  '';
  ntfyService = pkgs.writeText "lumo-ntfy" ''
    #!/sbin/openrc-run
    name="lumo-ntfy"
    description="Lumo ntfy UnifiedPush server"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-ntfy --network=host --env-file=${ntfyEnv} -v ${dataDir}:${dataDir} ${ntfyImage} serve"
    command_user="root"
    output_log="/var/log/lumo/ntfy.log"
    error_log="/var/log/lumo/ntfy.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need lumo-podman
      after networking
    }

    start_pre() {
      checkpath -d -m 0755 -o root:root /var/log/lumo
      checkpath -d -m 0700 -o root:root ${dataDir}
      checkpath -f -m 0640 -o root:root /var/log/lumo/ntfy.log
      if ! ${pkgs.podman}/bin/podman image exists ${ntfyImage}; then
        ${pkgs.podman}/bin/podman pull ${ntfyImage} >&2
      fi
    }
  '';
in
{
  home.packages = [ pkgs.podman ];

  home.activation.lumoNtfy = lib.hm.dag.entryAfter [ "lumoDirectories" "lumoPodman" ] ''
    install -Dm755 ${ntfyService} /etc/init.d/lumo-ntfy
    /sbin/rc-update add lumo-ntfy default
    /sbin/rc-service lumo-ntfy restart
  '';
}
