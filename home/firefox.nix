{pkgs, ...}: {
  programs.firefox = {
    enable = true;
    package =
      if pkgs.stdenv.isDarwin
      then pkgs.firefox-bin
      else pkgs.firefox;
  };
}
