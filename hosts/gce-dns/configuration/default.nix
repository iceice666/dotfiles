{
  config,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:

{
  imports = [
    ./blocky.nix
    ./tailscale-bootstrap.nix
    ./user.nix
  ];

  networking = {
    hostName = "gce-dns";
    firewall = {
      enable = true;
      interfaces.${config.services.tailscale.interfaceName} = {
        allowedTCPPorts = [
          53
          4000
        ];
        allowedUDPPorts = [ 53 ];
      };
    };
  };

  swapDevices = [
    {
      device = "/swapfile";
      size = 2048;
    }
  ];

  security.googleOsLogin.enable = lib.mkForce false;

  services = {
    openssh.enable = lib.mkForce false;
    tailscale = {
      enable = true;
      openFirewall = false;
      package = unstablePkgs.tailscale;
      authKeyFile = "/run/gce-dns/tailscale-auth-key";
      extraUpFlags = [
        "--ssh"
        "--hostname=gce-dns"
        "--accept-dns=false"
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    curl
    fish
    gitMinimal
    jq
    neovim
    ripgrep
  ];

  time.timeZone = "Asia/Taipei";
  i18n.defaultLocale = "en_US.UTF-8";

  users = {
    allowNoPasswordLogin = true;
    mutableUsers = false;
  };

  system.stateVersion = "26.05";
}
