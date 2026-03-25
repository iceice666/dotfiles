{ config, pkgs, ... }:

let
  rustfsDataDir = "/mnt/storage/rustfs/data";
  rustfsPort = 9100;
  minioClient = "${pkgs.minio-client}/bin/mc";
in
{
  users = {
    groups.rustfs.gid = 10001;

    users.rustfs = {
      isSystemUser = true;
      uid = 10001;
      group = "rustfs";
    };
  };

  systemd.tmpfiles.rules = [
    "d '/mnt/storage/rustfs' 0750 rustfs rustfs - -"
    "d '${rustfsDataDir}' 0750 rustfs rustfs - -"
    "z '${rustfsDataDir}' 0750 rustfs rustfs - -"
  ];

  virtualisation.oci-containers = {
    backend = "docker";

    containers.rustfs = {
      serviceName = "rustfs";
      image = "rustfs/rustfs:1.0.0-alpha.89-glibc";
      cmd = [ "/data" ];
      environmentFiles = [ config.sops.templates."rustfs.env".path ];
      ports = [ "127.0.0.1:${toString rustfsPort}:9000" ];
      user = "10001:10001";
      volumes = [ "${rustfsDataDir}:/data" ];
    };
  };

  systemd.services.rustfs = {
    unitConfig.RequiresMountsFor = rustfsDataDir;
  };

  systemd.services.rustfs-init = {
    description = "Create Forgejo RustFS buckets";
    wantedBy = [ "multi-user.target" ];
    after = [ "rustfs.service" ];
    requires = [ "rustfs.service" ];

    path = [
      pkgs.getent
      pkgs.coreutils
      pkgs.bash
      pkgs.minio-client
    ];

    script = ''
      access_key="$(tr -d '\n' < '${config.sops.secrets."rustfs-access-key".path}')"
      secret_key="$(tr -d '\n' < '${config.sops.secrets."rustfs-secret-key".path}')"

      export MC_HOST_rustfs="http://$access_key:$secret_key@127.0.0.1:${toString rustfsPort}"

      for _ in $(seq 1 30); do
        if ${minioClient} ls rustfs >/dev/null 2>&1; then
          break
        fi

        sleep 2
      done

      ${minioClient} mb --ignore-existing rustfs/forgejo-lfs
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}
