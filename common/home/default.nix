{
  pkgs,
  homeDirectory,
  lib,
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
    nix-direnv.enable = true;
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.opencode = {
    enable = true;
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
    pkgs.devenv
    pkgs.codex-unstable
    pkgs.git-lfs
  ];
}
