{
  pkgs,
  unstablePkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./filesystems.nix
    ./system.nix
    ./networking.nix
    ./sensitive
    ./user.nix
    ../services
  ];

  environment.systemPackages = with pkgs; [
    lsof
    bubblewrap
    unstablePkgs.agent-browser
    unstablePkgs.vulnix
    unstablePkgs.trivy
    unstablePkgs.statix
    unstablePkgs.deadnix
  ];

  system.stateVersion = "25.11";
}
