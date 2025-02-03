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
  ];

  programs = {

  };
}
