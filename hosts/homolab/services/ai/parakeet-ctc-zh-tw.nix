{
  config,
  dotfiles,
  homolab,
  pkgs,
  ...
}:

let
  containerName = "parakeet-ctc-0.6b-zh-tw";
  image = "nvcr.io/nim/nvidia/${containerName}:latest";
  cacheDir = "/mnt/storage/models/${containerName}/nim-cache";
  docker = config.virtualisation.docker.package;

  start = pkgs.writeShellScript "parakeet-ctc-zh-tw-start" ''
    set -euo pipefail

    export DOCKER_CONFIG="$RUNTIME_DIRECTORY/docker"
    export NGC_API_KEY
    NGC_API_KEY="$(< "$CREDENTIALS_DIRECTORY/ngc-api-key")"

    ${pkgs.coreutils}/bin/install -d -m 0700 "$DOCKER_CONFIG"
    ${pkgs.coreutils}/bin/install -d -m 0777 ${cacheDir}
    printf '%s' "$NGC_API_KEY" \
      | ${docker}/bin/docker login nvcr.io --username '$oauthtoken' --password-stdin

    ${docker}/bin/docker pull ${image}
    ${docker}/bin/docker rm --force ${containerName} >/dev/null 2>&1 || true

    exec ${docker}/bin/docker run --rm \
      --name ${containerName} \
      --device nvidia.com/gpu=0 \
      --shm-size 8g \
      --publish 127.0.0.1:${toString homolab.ports.parakeetHttp}:9000 \
      --publish ${homolab.network.tailnet.address}:${toString homolab.ports.parakeetHttp}:9000 \
      --publish 127.0.0.1:${toString homolab.ports.parakeetGrpc}:50051 \
      --publish ${homolab.network.tailnet.address}:${toString homolab.ports.parakeetGrpc}:50051 \
      --env NGC_API_KEY \
      --env NIM_HTTP_API_PORT=9000 \
      --env NIM_GRPC_API_PORT=50051 \
      --env NIM_TAGS_SELECTOR=mode=str,vad=default,diarizer=disabled \
      --volume ${cacheDir}:/opt/nim/.cache \
      ${image}
  '';
in
{
  hardware.nvidia-container-toolkit.enable = true;

  virtualisation.docker = {
    enable = true;
    daemon.settings.data-root = "/mnt/storage/docker";
  };

  sops.secrets."homolab-ngc-api-key" = {
    sopsFile = dotfiles + /sensitive/hosts/homolab/ngc_api_key.key;
    format = "json";
    key = "data";
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ "parakeet-ctc-zh-tw.service" ];
  };

  systemd.tmpfiles.rules = [
    "d /mnt/storage/docker 0700 root root - -"
    "d /mnt/storage/models/${containerName} 0755 root root - -"
    "d ${cacheDir} 0777 root root - -"
  ];

  systemd.services.parakeet-ctc-zh-tw = {
    description = "NVIDIA Parakeet CTC 0.6B zh-TW Speech NIM";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    requires = [
      "docker.service"
      "nvidia-container-toolkit-cdi-generator.service"
    ];
    after = [
      "network-online.target"
      "docker.service"
      "nvidia-container-toolkit-cdi-generator.service"
      "tailscaled.service"
    ];

    serviceConfig = {
      Type = "simple";
      ExecStart = start;
      ExecStop = "${docker}/bin/docker stop --time 30 ${containerName}";
      Restart = "on-failure";
      RestartSec = 30;
      TimeoutStartSec = 0;
      TimeoutStopSec = 60;
      RuntimeDirectory = "parakeet-ctc-zh-tw";
      RuntimeDirectoryMode = "0700";
      LoadCredential = "ngc-api-key:${config.sops.secrets."homolab-ngc-api-key".path}";
    };
  };
}
