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
    ./opencode
    ./user.nix
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
    pkgs.zellij
    unstablePkgs.sops
  ];

  home.file.".config/zellij/config.kdl".text = ''
    default_shell "${pkgs.fish}/bin/fish"
    mouse_mode true
    pane_frames true
    simplified_ui false
    copy_on_select false
    scroll_buffer_size 10000
  '';
}
