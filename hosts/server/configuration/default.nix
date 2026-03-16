{
  config,
  pkgs,
  inputs,
  self,
  username,
  homeDirectory,
  dotfiles,
  ...
}:

{
  imports = [
    /etc/nixos/hardware-configuration.nix
    (dotfiles + /common/configuration)
  ];

  nix.settings = {
    experimental-features = "nix-command flakes";
    substituters = [ "https://cache.nixos-cuda.org" ];
    trusted-public-keys = [ "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" ];
  };

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  networking = {
    hostName = "homolab";
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "8.8.8.8"
    ];
    defaultGateway = "192.168.1.1";
    useDHCP = false;

    networkmanager.enable = true;

    interfaces.enp7s0.ipv4.addresses = [
      {
        address = "192.168.1.127";
        prefixLength = 24;
      }
    ];

    firewall.allowedTCPPorts = [ 2222 ];
  };

  time.timeZone = "Asia/Taipei";

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

  virtualisation.docker.enable = true;

  programs.fish.enable = true;

  users.users.${username} = {
    isNormalUser = true;
    home = homeDirectory;
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "docker"
    ];
  };

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };

  systemd.services.cloudflared-tunnel = {
    description = "Cloudflare Tunnel";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "root";
      Restart = "always";
      RestartSec = "5s";
      ExecStart = "${pkgs.bash}/bin/bash -lc 'exec ${pkgs.cloudflared}/bin/cloudflared tunnel run --token \"$(< /var/lib/secrets/cloudflared-token)\"'";
    };
  };

  services.openssh = {
    enable = true;
    ports = [ 2222 ];
    settings = {
      PermitRootLogin = "no";
      AllowUsers = [ username ];
      PasswordAuthentication = false;
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit
        inputs
        self
        username
        homeDirectory
        dotfiles
        ;
    };
    users.${username} = {
      imports = [ ../home ];
    };
  };

  system.stateVersion = "25.11";
}
