{
  pkgs,
  homeDirectory,
  ...
}:

{
  imports = [
    ./app-defaults.nix
    ./agent-skills.nix
    ./claude.nix
    ./dev-env.nix
    ./fish
    ./ghostty.nix
    ./packages.nix
    ./pi.nix
    ./rime
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

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withPython3 = true;
    withRuby = true;
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    options = [
      "--cmd"
      "cd"
    ];
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.home-manager.enable = true;

  sops.age.sshKeyPaths = [ "${homeDirectory}/.ssh/id_ed25519" ];

  # Derive the native age identity from the SSH key so the sops CLI can
  # decrypt files. sops only auto-tries id_rsa; ed25519 must be converted
  # explicitly. SOPS_AGE_SSH_PRIVATE_KEY_FILE uses the SSH identity type
  # which cannot decrypt native age1… recipients — SOPS_AGE_KEY_CMD is the
  # correct hook (sops runs it and treats stdout as the raw AGE-SECRET-KEY-…).
  home.sessionVariables.SOPS_AGE_KEY_CMD = "ssh-to-age -private-key -i ${homeDirectory}/.ssh/id_ed25519";

  home.stateVersion = "25.11";

  programs.fish.interactiveShellInit = ''
    set -gx HOSTNAME (uname -n)
  '';

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
