{pkgs, ...}:{
  environment.systemPackages = with pkgs; [
    devenv

    ### (de)compress tools
    zip
    xz
    unzip
    p7zip

    ripgrep # grep replacemnet
    jq # JSON parser
    ijq # interactive jq
    fzf # fuzzy finder

    eza # ls replacement

    lazygit # A git TUI
  ];
}
