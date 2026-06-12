{ ... }:

{
  programs.fish.functions."homolab-wake" = {
    description = "Wake homolab and wait for it to be ready";
    body = ''
      set -l justfile $HOME/dotfiles/Justfile
      if not test -f $justfile
          echo "homolab-wake: $justfile not found" >&2
          return 1
      end
      # Pass through any extra args (e.g. HOMOLAB_WAKE_MODE=ssh) as env overrides.
      just --justfile $justfile homolab-wake $argv
    '';
  };
}
