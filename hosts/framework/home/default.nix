{
  pkgs,
  username,
  homeDirectory,
  dotfiles,
  ...
}:

let
  desktopWallpaper = dotfiles + /assets/mzen.png;
  sharedPackages = import (dotfiles + /common/configuration/packages.nix) { inherit pkgs; };
in
{
  imports = [
    (dotfiles + /common/home)
  ];

  _module.args = {
    inherit desktopWallpaper;
  };

  sops.age.sshKeyPaths = [ "${homeDirectory}/.ssh/id_ed25519" ];

  home.packages =
    sharedPackages
    ++ (with pkgs; [
      equibop-bin
      obs-studio
    ]);

  home.stateVersion = "25.11";

  programs.fish.interactiveShellInit = ''
    # Linux-specific environment variables
    set -gx HOSTNAME (uname -n)
    set -gx PNPM_HOME $HOME/.local/share/pnpm

    # Linux-specific PATH
    fish_add_path -p $PNPM_HOME
  '';
}
