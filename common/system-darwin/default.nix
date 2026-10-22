{ pkgs, dotfiles, ... }:

{
  nix.settings.experimental-features = "nix-command flakes";

  system.activationScripts.postActivation.text = ''
    ${pkgs.python3}/bin/python3 ${dotfiles + /scripts/tls-trust-macos.py} \
      --security /usr/bin/security \
      --roots ${./tls-distrust-roots.pem}
  '';
}
