{...}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    initExtra = ''
      export PATH="$HOME/.cargo/bin:$HOME/bin:$HOME/.local/bin:$PATH"
      source ${../conf/.zshrc}
    '';
  };

  home.shellAliases = {
    ".." = "cd ..";
    home = "cd $$HOME";
    l = "eza -almhF --time-style iso -s type --git-ignore";
    ll = "eza -almhF --time-style iso -s type";
    lt = "exa -almhF --time-style iso -s type --git-ignore --tree -L 3 -I .git";
    lg = "lazygit";
  };
}
