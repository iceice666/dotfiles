{
  config,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:

{
  imports = [
    ./tailscale-bootstrap.nix
    ./user.nix
  ];

  networking = {
    hostName = "gce-dns";
    firewall = {
      enable = true;
      trustedInterfaces = [ config.services.tailscale.interfaceName ];
    };
  };

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  nixpkgs.config.allowUnfree = true;

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
      openFirewall = true;
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

  programs.fish.enable = true;

  time.timeZone = "Asia/Taipei";
  i18n.defaultLocale = "en_US.UTF-8";

  users = {
    allowNoPasswordLogin = true;
    mutableUsers = false;
  };

  system.stateVersion = "26.05";
}
