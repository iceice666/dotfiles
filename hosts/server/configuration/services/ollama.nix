{ config, unstablePkgs, ... }:

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

  services.ollama = {
    enable = true;
    host = "192.168.1.127";
    port = 11434;
    package = unstablePkgs.ollama;
    loadModels = [ "qwen3.5:9b" ];
  };
}
