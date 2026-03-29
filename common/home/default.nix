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

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.opencode = {
    enable = true;
    package = unstablePkgs.opencode;
    settings = {
      plugin = [ "@tarquinen/opencode-dcp@latest" ];
      provider.ollama = {
        models."qwen3.5:9b" = {
          _launch = true;
          name = "qwen3.5:9b";
        };
        name = "Ollama";
        npm = "@ai-sdk/openai-compatible";
        options.baseURL = "http://192.168.1.127:11434/v1";
      };
    };
  };

  programs.home-manager.enable = true;

  home.packages = [
    pkgs.matugen
    unstablePkgs.mise-bin
    pkgs.git-lfs
    pkgs.python3
    pkgs.uv
    pkgs.yq
    pkgs.zellij
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
