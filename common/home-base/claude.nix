{
  config,
  dotfiles,
  lab,
  lib,
  pkgs,
  ...
}:

let
  agentModel = import ./agent-model.nix { inherit dotfiles lab; };

  # Canonical source lives alongside this module under ./claude/
  # mkOutOfStoreSymlink keeps the targets writable so Claude Code can update
  # settings.json in place, and edits to dotfiles are reflected immediately.
  dotfilesHome = "${config.home.homeDirectory}/dotfiles/common/home-base/claude";

  apiKeyHelper = pkgs.writeShellScript "claude-cliproxyapi-api-key" ''
    exec ${pkgs.coreutils}/bin/cat ${config.sops.secrets.${agentModel.secretName}.path}
  '';

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
  sops.secrets.${agentModel.secretName} = agentModel.secret;

  home.packages = [ pkgs.claude-code-bin ];

  home.file = builtins.listToAttrs (map mkClaudeFile managedFiles) // {
    ".claude/cliproxyapi-api-key" = {
      source = apiKeyHelper;
      force = true;
    };
    ".claude/CLAUDE.md" = {
      source = ./agent-instructions.md;
      force = true;
    };
  };

  # Ensure statusline.sh is executable in the dotfiles source.
  home.activation.claude-statusline-executable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    chmod +x "${dotfilesHome}/statusline.sh" 2>/dev/null || true
  '';

  # Drop launchers left by Claude Code's native self-installer or earlier
  # generations so the Nix-managed binary on PATH is the only `claude`.
  home.activation.claude-remove-managed-shim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claude_shim="${config.home.homeDirectory}/.local/bin/claude"
    claude_target="$(${pkgs.coreutils}/bin/readlink "$claude_shim" 2>/dev/null || true)"

    case "$claude_target" in
      /nix/store/*-claude-code-bin-*/bin/claude|"${config.home.homeDirectory}/.local/share/claude/"*)
        ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
          /usr/bin/chflags -h nouchg "$claude_shim"
        ''}
        ${pkgs.coreutils}/bin/rm -f "$claude_shim"
        ;;
    esac
  '';
}
