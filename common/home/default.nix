{ pkgs, inputs, homeDirectory, lib, ... }:

{
  imports = [ ./fish ./user.nix ];

  home.activation.cloneNotes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${homeDirectory}/Notes/.git" ]; then
      ${pkgs.git}/bin/git clone ssh://git@justaslime.dev/justaslime/dotfiles.git "${homeDirectory}/Notes"
    fi
  '';

  home.packages = with pkgs; [
    cloudflared
    zulu21
  ];

  programs.git = {
    enable = true;
    settings = {
      user.name  = "Brian Duan";
      user.email = "iceice666@outlook.com";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.home-manager.enable = true;
}
