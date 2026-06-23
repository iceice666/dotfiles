{
  lib,
  pkgs,
  ...
}:

let
  storageConfig = pkgs.writeText "storage.conf" ''
    [storage]
    driver = "overlay"
    graphroot = "/var/lib/containers/storage"
    runroot = "/run/containers/storage"
  '';

  registriesConfig = pkgs.writeText "registries.conf" ''
    unqualified-search-registries = ["docker.io"]

    [[registry]]
    location = "docker.io"
  '';

  podmanService = pkgs.writeText "lumo-podman" ''
    #!/sbin/openrc-run
    name="lumo-podman"
    description="Lumo Podman API"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="system service --time=0 unix:///run/podman/podman.sock"
    output_log="/var/log/lumo/podman.log"
    error_log="/var/log/lumo/podman.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need cgroups localmount
      after networking
    }

    start_pre() {
      checkpath -d -m 0700 -o root:root /run/podman
      checkpath -d -m 0700 -o root:root /run/containers
      checkpath -d -m 0700 -o root:root /run/containers/storage
      checkpath -d -m 0700 -o root:root /var/lib/containers
      checkpath -d -m 0700 -o root:root /var/lib/containers/storage
    }
  '';
in
{
  home.packages = [ pkgs.podman ];

  home.activation.lumoPodman = lib.hm.dag.entryAfter [ "lumoDirectories" ] ''
    install -d -m 0755 /etc/containers
    install -Dm644 ${storageConfig} /etc/containers/storage.conf
    install -Dm644 ${registriesConfig} /etc/containers/registries.conf
    install -Dm755 ${podmanService} /etc/init.d/lumo-podman
    /sbin/rc-update add lumo-podman default
    /sbin/rc-service lumo-podman restart
  '';
}
