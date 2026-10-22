{ pkgs, ... }:

{
  nix.package = pkgs.lixPackageSets.stable.lix;
  nixpkgs.config.allowUnfree = true;
  security.pki.caCertificateBlacklist = import ../../lib/tls-ca-blacklist.nix;
  fonts.packages = with pkgs; [
    cascadia-code
    nerd-fonts.jetbrains-mono
    sarasa-gothic
  ];
  programs.fish.enable = true;
}
