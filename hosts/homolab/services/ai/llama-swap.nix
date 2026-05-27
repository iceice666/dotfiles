{
  config,
  homolab,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:

let
  llamaServer = lib.getExe' unstablePkgs.llama-cpp "llama-server";
  modelDir = "/run/llama-swap/models";

  models = {
    "qwen3.6-35b-a3b" = {
      source = "/mnt/storage/models/qwen3.6-35b-a3b/model.gguf";
      gpuLayers = 13;
    };
    "gemma-4-26b-a4b-it" = {
      source = "/mnt/storage/models/gemma-4-26b-a4b-it/model.gguf";
      gpuLayers = 10;
    };
  };
in
{
  nixpkgs.config.cudaSupport = true;

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
  };

  services.llama-swap = {
    enable = true;
    package = pkgs.llama-swap;
    port = homolab.ai.port;

    settings = {
      healthCheckTimeout = 300;
      logLevel = "info";

      models = lib.mapAttrs' (
        name: cfg:
        lib.nameValuePair name {
          cmd = "${llamaServer} --port \${PORT} --model ${modelDir}/${name}.gguf --gpu-layers ${toString cfg.gpuLayers} --ctx-size 8192 --flash-attn on --no-webui";
          checkEndpoint = "/health";
          ttl = 0;
        }
      ) models;
    };
  };

  systemd.services.llama-swap = {
    environment = {
      HOME = "/var/lib/llama-swap";
      XDG_CACHE_HOME = "/var/cache/llama-swap";
    };

    preStart = ''
      ${pkgs.coreutils}/bin/install -d -m755 ${lib.escapeShellArg modelDir}
      ${lib.concatMapStringsSep "\n" (
        name:
        "${pkgs.coreutils}/bin/ln -sf ${
          lib.escapeShellArg models.${name}.source
        } ${lib.escapeShellArg "${modelDir}/${name}.gguf"}"
      ) (builtins.attrNames models)}
    '';

    serviceConfig = {
      PrivateDevices = false;
      DynamicUser = lib.mkForce false;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      UMask = "0077";
      CacheDirectory = "llama-swap";
      RuntimeDirectory = "llama-swap";
      RuntimeDirectoryMode = "0755";
      StateDirectory = "llama-swap";
      ReadWritePaths = [
        "/mnt/storage/models"
      ];
    };
  };
}
