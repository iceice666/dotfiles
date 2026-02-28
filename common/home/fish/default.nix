{ pkgs, ... }:

{
  imports = map (f: ./functions/${f}) (
    builtins.filter (f: builtins.match ".*\\.nix" f != null) (
      builtins.attrNames (builtins.readDir ./functions)
    )
  );

  programs.fish = {
    enable = true;

    plugins = [
      {
        name = "autopair";
        src = pkgs.fishPlugins.autopair.src;
      }
      {
        name = "plugin-sudope";
        src = pkgs.fishPlugins.plugin-sudope.src;
      }
    ];

    shellAliases = {
      l = "eza -almhgF --time-style iso -s type --git-ignore";
      ll = "eza -almhgF --time-style iso -s type";
      lt = "eza -almhgF --time-style iso -s type --git-ignore --tree -L 2 -I .git";
      llt = "eza -almhgF --time-style iso -s type --tree -L 2";
      lg = "lazygit";
      cat = "bat";
      ccat = "command cat";
      plz = "sudo";
    };

    shellAbbrs = {
      cp = "cp -r";
      mkdir = "mkdir -p";
      "/reload" = "source ~/.config/fish/config.fish";
      "/h" = "history";
      "/c" = "clear";
      "/clear" = "clear";
    };

    interactiveShellInit = ''
      # Environment variables
      set -gx ProjectDir ~/Project
      set -gx EDITOR nvim

      # # ZVM
      # set -gx ZVM_INSTALL "$HOME/.zvm/self"

      # # Haskell GHC
      # set -q GHCUP_INSTALL_BASE_PREFIX[1]; or set GHCUP_INSTALL_BASE_PREFIX $HOME

      # # PATH
      # fish_add_path -p ~/go/bin
      # fish_add_path -p $BUN_INSTALL/bin
      # fish_add_path -p ~/.cargo/bin
      # fish_add_path -p $HOME/.local/bin
      # fish_add_path -p ~/bin
      # fish_add_path -p $HOME/.dotnet/tools/
      # fish_add_path -p $HOME/.cabal/bin
      # fish_add_path -p $HOME/.zvm/bin
      # fish_add_path -p $ZVM_INSTALL/

      # Better directory colors for ls/eza
      if type -q dircolors
          eval (dircolors -c ~/.dircolors 2>/dev/null; or dircolors -c)
      end

      # FZF integration
      if type -q fzf
          set -gx FZF_DEFAULT_OPTS '--height 40% --layout=reverse --border'
      end

      # Dotdot abbreviation (requires function defined above)
      abbr --add dotdot --regex '^\.\.+$' --function __fish_multicd

      # Disable greeting
      set -g fish_greeting ""

      # Tab completion: expand tilde prefix
      bind tab '__expand_tilde_prefix'
    '';
  };
}
