{ pkgs, unstablePkgs, ... }:

let
  stablePackages = with pkgs; [
    fzf
    neovim
    ripgrep
    fd
    bat
    eza
    btop
    jq
    ijq
    lazygit
    lazydocker
    fish
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
    codex-cli-bin
    equibop-bin
    gh
    git-lfs
    python3
    uv
    yq
    zen-bin
  ];

  unstablePackages = with unstablePkgs; [
    bun
    just
    sops
  ];
in
{
  home.packages = stablePackages ++ unstablePackages;
}
