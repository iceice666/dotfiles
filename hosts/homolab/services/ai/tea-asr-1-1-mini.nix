{
  config,
  homolab,
  pkgs,
  ...
}:

let
  containerName = "tea-asr-1-1-mini";
  image = "qwenllm/qwen3-asr:latest";
  cacheDir = "/mnt/storage/models/${containerName}/hf-cache";
  docker = config.virtualisation.docker.package;

  # qwenllm/qwen3-asr:latest bundles a transformers/qwen-asr version predating
  # the qwen3_asr architecture, so `vllm serve` can't parse the checkpoint's
  # config.json. qwen-asr's own Qwen3ASRModel loader works regardless (it
  # doesn't go through transformers' architecture registry), so this server
  # pins a known-good qwen-asr release and loads the model directly instead
  # of shelling out to vllm.
  serverScript = ./tea-asr-server.py;
  qwenAsrVersion = "0.0.6";

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
      --volume ${serverScript}:/app/server.py:ro \
      ${image} \
      bash -c 'pip install -q fastapi "uvicorn[standard]" python-multipart "qwen-asr==${qwenAsrVersion}" && exec python3 /app/server.py'
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
