{pkgs, ...}: {
  home.packages = with pkgs; [
    (lib.mkIf (!pkgs.stdenv.isDarwin) [
      obs-studio # Install OBS with HomeManager on Darwin is not supported currently.
    ])
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  programs.info.enable = false;
  programs.bash.enable = false;
}
