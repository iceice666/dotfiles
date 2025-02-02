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

    glow
  ];

  programs = {
    eza = {
      enable = true;
      icons = "always";
      enableZshIntegration = true;
    };
  };
}
