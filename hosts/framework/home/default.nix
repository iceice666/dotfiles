{
  pkgs,
  lib,
  username,
  homeDirectory,
  dotfiles,
  ...
}:

let
  unmanaged = map lib.getName (
    import (dotfiles + /common/configuration/packages.nix) { inherit pkgs; }
  );
in
{
  imports = [
    (dotfiles + /common/home)
    (dotfiles + /shared/home/zed.nix)
    (dotfiles + /shared/home/themegen.nix)
    # (dotfiles + /shared/home/vscodium.nix)
  ];

  warnings = [
    ''
      [framework] The following tools from common/configuration/packages.nix are NOT managed
      by home-manager because this host uses a standalone home-manager configuration and
      environment.systemPackages is unavailable here:

        ${lib.concatStringsSep ", " unmanaged}

      Install them via XBPS, e.g.:
        sudo xbps-install -S ${lib.concatStringsSep " " unmanaged}
    ''
  ];

  home.packages = with pkgs; [
    equibop-bin
  ];

  home.stateVersion = "25.11";

  programs.fish.interactiveShellInit = ''
    # Linux-specific environment variables
    set -gx HOSTNAME (hostname)
    set -gx PNPM_HOME $HOME/.local/share/pnpm

    # Linux-specific PATH
    fish_add_path -p $PNPM_HOME
  '';
}
