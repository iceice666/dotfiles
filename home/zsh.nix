{...}: {
    environment.pathsToLink = [ "/share/zsh" ];

  programs.zsh = {
    enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
    initExtra = ''
      export PATH="$HOME/.cargo/bin:$HOME/bin:$HOME/.local/bin:$PATH"
      source ${../conf/.zshrc}
    '';
  };

  home.shellAliases = {
    ".." = "cd ..";
    home = "cd $HOME";
    l = "eza -almhF --time-style iso -s type --git-ignore";
    ll = "eza -almhF --time-style iso -s type";
    lt = "eza -almhF --time-style iso -s type --git-ignore --tree -L 3 -I .git";
    llt = "eza -almhF --time-style iso -s type --tree -L 3 ";
    lg = "lazygit";
  };
}
