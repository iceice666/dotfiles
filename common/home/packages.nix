{
  lib,
  pkgs,
  config,
  unstablePkgs,
  ...
}:

let
  stablePackages =
    with pkgs;
    [
      fzf
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
      ssh-to-age
      ffmpeg
      nodejs_24
      claude-code-bin
      codex-cli-bin
      ketch
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
    bitwarden-cli
    bun
    just
    sops
  ];
in
{
  home.packages = stablePackages ++ unstablePackages;

  home.activation.claudeLocalBin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -dm755 "$HOME/.local/bin"
    ln -sf "${config.home.profileDirectory}/bin/claude" "$HOME/.local/bin/claude"
  '';
}
