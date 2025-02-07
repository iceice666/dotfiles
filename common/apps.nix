{
  pkgs,
  pkgs-unstable,
  ...
}: {
  environment.systemPackages = with pkgs; [
    devenv

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

    ### TUI
    ijq # interactive jq
    lazygit # A git TUI
  ];

  fonts.packages = with pkgs-unstable; [
    ### others
    nerd-fonts.caskaydia-cove # font
  ];
}
