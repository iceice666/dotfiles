{ ... }:

{
  programs.fish.functions.__expand_tilde_prefix = {
    description = "Expand tilde prefix";
    body = ''
      set -l token (commandline -t)
      if string match -q -r '~[a-zA-Z0-9_.-]' -- $token
          commandline -t (string replace -r '^~' "~/" -- $token)
          commandline -f repaint
      else
          commandline -f complete
      end
    '';
  };
}
