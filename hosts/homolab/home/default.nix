{
  config,
  dotfiles,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:

{
  imports = [
    (dotfiles + /common/home-gui/zed.nix)
    ./fish-pj.nix
    ./desktop.nix
  ];

  # System activation mirrors /var/lib/sops-nix/key.txt into this user-owned
  # path (see hosts/homolab/configuration/sensitive). Using the SSH-derived age
  # identity from common/home-base is impossible here: the homolab user has no
  # SSH key.
  sops.age = {
    keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    sshKeyPaths = lib.mkForce [ ];
  };

  home.sessionVariables = {
    SOPS_AGE_KEY_CMD = lib.mkForce "cat ${config.home.homeDirectory}/.config/sops/age/keys.txt";
    SOPS_AGE_KEY_FILE = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
  };

  home.packages = [
    (if pkgs.stdenv.hostPlatform.isLinux then pkgs.mise else unstablePkgs.mise-bin)
  ];
}
