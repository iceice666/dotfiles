{
  pkgs,
  pkgs-unstable,
  ...
}: {
  environment.systemPackages = with pkgs; [
    # The best shell
    nushell

    ffmpeg

    ### (de)compress tools
    zip
    xz
    unzip
    p7zip

    ### utils
    ripgrep # grep replacemnet
    jq # JSON parser
    fzf # fuzzy finder
    bat # A cat replacement comes with pager
    eza # ls replacement
    just # script runner like gnu make

    ### TUI
    ijq # interactive jq
    lazygit # A git TUI
    btop # A top replacement
  ];

  fonts.packages = with pkgs-unstable; [
    cascadia-code
  ];
}
