{ config, lib, ... }:

let
  managedFiles = [
    "settings.json"
    "statusline.sh"
  ];

  mkClaudeFile = file: {
    name = ".claude/${file}";
    value = {
      source = ./claude + "/${file}";
      force = true;
    };
  };
in
{
  home.file = builtins.listToAttrs (map mkClaudeFile managedFiles);

  home.activation.claude-remove-self-install-shim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claude_shim="${config.home.homeDirectory}/.local/bin/claude"
    claude_target="$(readlink "$claude_shim" 2>/dev/null || true)"

    case "$claude_target" in
      "${config.home.homeDirectory}/.local/share/claude/"*)
        rm -f "$claude_shim"
        ;;
    esac
  '';
}
