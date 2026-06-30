{ config, lib, ... }:

let
  # Canonical source lives alongside this module under ./claude/
  # mkOutOfStoreSymlink keeps the targets writable so Claude Code can update
  # settings.json in place, and edits to dotfiles are reflected immediately.
  dotfilesHome = "${config.home.homeDirectory}/dotfiles/common/home-base/claude";

  managedFiles = [
    "settings.json"
    "statusline.sh"
  ];

  mkClaudeFile = file: {
    name = ".claude/${file}";
    value = {
      source = config.lib.file.mkOutOfStoreSymlink "${dotfilesHome}/${file}";
      force = true;
    };
  };
in
{
  home.file = builtins.listToAttrs (map mkClaudeFile managedFiles);

  # Ensure statusline.sh is executable in the dotfiles source.
  home.activation.claude-statusline-executable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    chmod +x "${dotfilesHome}/statusline.sh" 2>/dev/null || true
  '';

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
