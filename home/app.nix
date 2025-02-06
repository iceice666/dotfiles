{pkgs, ...}: {
  home.packages = with pkgs; [
    zip
    xz
    unzip
    p7zip

    ripgrep
    jq
    ijq
    fzf

    eza

    lazygit

    (lib.mkIf (!pkgs.stdenv.isDarwin) [
        obs-studio # Install OBS with HomeManager on Darwin is not supported currently.
    ])
  ];
}
