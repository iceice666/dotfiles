{
  lib,
  pkgs,
  unstablePkgs,
  ...
}:

let
  stablePackages =
    with pkgs;
    [
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
      pi-coding-agent-bin
      equibop-bin
      gh
      git-lfs
      python3
      uv
      yq
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
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
