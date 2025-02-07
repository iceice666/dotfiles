{...}: {
  environment.shellAliases = {
    ".." = "cd ..";
    "~" = "cd ~";
    l = "eza -almhF --time-style iso -s type --git-ignore";
    ll = "eza -almhF --time-style iso -s type";
    lt = "eza -almhF --time-style iso -s type --git-ignore --tree -L 3 -I .git";
    llt = "eza -almhF --time-style iso -s type --tree -L 3 ";
    lg = "lazygit";
    cat = "bat";
  };
}
