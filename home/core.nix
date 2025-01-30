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

  programs.eza = {
    enable = true;
    icons = "auto";
  };

  programs.zed-editor = {
    enable = true;

    extensions = [
      "nix"
    ];

    userSettings = {
      languages = {
        Nix = {
          language_servers = [
            "nil"
            "!nixd"
          ];
          formatter = {
            external = {
              command = "nixfmt";
            };
          };
        };
      };
    };
  };
}
