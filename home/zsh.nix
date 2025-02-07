{...}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    zplug = {
      enable = true;
      plugins = [
        {name = "marlonrichert/zsh-edit";}
        {name = "marlonrichert/zsh-autocomplete";}
        {name = "hlissner/zsh-autopair";}
        {name = "djui/alias-tips";}
        {name = "ael-code/zsh-colored-man-pages";}
        {name = "Freed-Wu/zsh-command-not-found";}
        {
          name = "plugins/{sudo, extract, direnv}";
          tags = ["from:oh-my-zsh"];
        }
      ];
    };
    initExtra = ''
      export PATH="$HOME/.cargo/bin:$HOME/bin:$HOME/.local/bin:$PATH"
      source ${../conf/.zshrc}
    '';
  };
}
