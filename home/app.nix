{pkgs, ...}: {
  home.packages = with pkgs; [
    # thrid-party Discord client
    vesktop

    (lib.mkIf (!pkgs.stdenv.isDarwin) [
      obs-studio # Install OBS with HomeManager on Darwin is not supported currently.
    ])
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };
}
