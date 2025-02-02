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
    urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
    urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";
    ".." = "cd ..";
    home = "cd $$HOME";
    l = "eza -almhF --time-style iso -s type --git-ignore";
    ll = "eza -almhF --time-style iso -s type";
    lt = "exa -almhF --time-style iso -s type --git-ignore --tree -L 3 -I .git";
  };
}
