{ pkgs, unstablePkgs, ... }:

let
  stablePackages = with pkgs; [
    fzf
    ripgrep
    wakeonlan
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
    ssh-to-age
    ffmpeg
    nodejs_24
    gh
    git-lfs
    python3
    uv
    yq
    ast-grep
  ];

  unstablePackages = with unstablePkgs; [
    bitwarden-cli
    bun
    just
    sops
    zellij
  ];
in
{
  home.packages = stablePackages ++ unstablePackages;
}
