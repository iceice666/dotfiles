{
  pkgs,
  homeDirectory,
  lib,
  unstablePkgs,
  ...
}:

{
  imports = [
    ./fish
    ./ghostty.nix
    ./opencode
    ./themegen
    ./user.nix
    ./vscodium.nix
    ./zed.nix
  ];

  programs.git = {
    enable = true;
    settings = {
      user.name = "Brian Duan";
      user.email = "iceice666@outlook.com";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.direnv = {
    enable = true;
    package = pkgs.direnv;
    nix-direnv.enable = true;
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.home-manager.enable = true;

  home.packages = [
    unstablePkgs.bun
    pkgs.gh
    pkgs.git-lfs
    pkgs.python3
    pkgs.uv
    pkgs.yq
    unstablePkgs.sops
  ];

  # Keep npm global installs out of the read-only Nix store. Pi's
  # package installer uses npm for npm: Pi packages.
  home.file.".npmrc".text = ''
    prefix=''${HOME}/.npm-global
  '';

  home.file.".config/zellij/config.kdl".text = ''
    default_shell "${pkgs.fish}/bin/fish"
    mouse_mode true
    pane_frames true
    simplified_ui false
    copy_on_select false
    scroll_buffer_size 10000
  '';
}
