{
  dotfiles,
  pkgs,
  unstablePkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./system.nix
    ./networking.nix
    ./sensitive
    ./user.nix
    ../services
  ];

  environment.systemPackages = with pkgs; [
    fzf
    neovim
    ripgrep
    fd
    bat
    eza
    btop
    lsof
    jq
    ijq
    lazygit
    lazydocker
    fish
    just
    xz
    zstd
    unrar
    p7zip
    gnutar
    ncompress
    nil
    nixfmt
    tldr
    zulu21
    age
    ffmpeg
    nodejs_24
    bubblewrap

    pkgs."codex-bin"
    unstablePkgs.agent-browser
    unstablePkgs.vulnix
    unstablePkgs.trivy
    unstablePkgs.statix
    unstablePkgs.deadnix
  ];

  fonts.packages = with pkgs; [ cascadia-code ];

  system.stateVersion = "25.11";
}
