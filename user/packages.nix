{ pkgs, ... }:

{
  home.packages = with pkgs; [
    fzf
    neovim
    git
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
    just
    nixfmt
    devenv
  ];
}
