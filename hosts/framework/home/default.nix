{
  pkgs,
  lib,
  username,
  homeDirectory,
  ...
}:

let
  # Single source of truth — same list used by environment.systemPackages on other hosts.
  # On framework (standalone home-manager) these must be installed via XBPS instead.
  unmanaged = map lib.getName (import ../../../common/configuration/packages.nix { inherit pkgs; });
in
{
  imports = [
    ../../../common/home
    ../../../shared/home/zed.nix
    ../../../shared/home/cursor.nix
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
