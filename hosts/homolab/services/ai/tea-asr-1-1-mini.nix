{
  config,
  homolab,
  pkgs,
  ...
}:

let
  containerName = "tea-asr-1-1-mini";
  image = "qwenllm/qwen3-asr:latest";
  modelId = "JacobLinCool/TEA-ASR-1.1-mini";
  cacheDir = "/mnt/storage/models/${containerName}/hf-cache";
  docker = config.virtualisation.docker.package;

  start = pkgs.writeShellScript "tea-asr-1-1-mini-start" ''
    set -euo pipefail

    ${pkgs.coreutils}/bin/install -d -m 0777 ${cacheDir}

    ${docker}/bin/docker pull ${image}
    ${docker}/bin/docker rm --force ${containerName} >/dev/null 2>&1 || true

    exec ${docker}/bin/docker run --rm \
      --name ${containerName} \
      --device nvidia.com/gpu=0 \
      --shm-size 4g \
      --publish 127.0.0.1:${toString homolab.ports.teaAsrHttp}:8000 \
      --publish ${homolab.network.tailnet.address}:${toString homolab.ports.teaAsrHttp}:8000 \
      --env HF_HOME=/cache \
      --volume ${cacheDir}:/cache \
      ${image} \
      vllm serve ${modelId} \
        --host 0.0.0.0 \
        --port 8000 \
        --served-model-name tea-asr-1.1-mini \
        --gpu-memory-utilization 0.25
  '';
in
{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };

    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      open = true;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    nvidia-container-toolkit.enable = true;
  };

  virtualisation.docker = {
    enable = true;
    daemon.settings.data-root = "/mnt/storage/docker";
  };

  systemd.tmpfiles.rules = [
    "d /mnt/storage/docker 0700 root root - -"
    "d /mnt/storage/models/${containerName} 0755 root root - -"
    "d ${cacheDir} 0777 root root - -"
  ];

  systemd.services.tea-asr-1-1-mini = {
    description = "TEA-ASR 1.1 mini Taiwan Mandarin ASR (Qwen3-ASR based)";
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
    };
  };
}
