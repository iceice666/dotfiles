{
  config,
  dotfiles,
  lib,
  pkgs,
  ...
}:

let
  # Canonical source lives alongside this module under ./claude/
  # mkOutOfStoreSymlink keeps the targets writable so Claude Code can update
  # settings.json in place, and edits to dotfiles are reflected immediately.
  dotfilesHome = "${config.home.homeDirectory}/dotfiles/common/home-base/claude";

  apiKeyHelper = pkgs.writeShellScript "claude-cliproxyapi-api-key" ''
    exec ${pkgs.coreutils}/bin/cat ${config.sops.secrets.cliproxyapi_homonet_api_key.path}
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
  sops.secrets.cliproxyapi_homonet_api_key = {
    sopsFile = dotfiles + /sensitive/shared/cliproxyapi.yaml;
    key = "homonetApiKey";
    mode = "0400";
  };

  home.file = builtins.listToAttrs (map mkClaudeFile managedFiles) // {
    ".claude/cliproxyapi-api-key" = {
      source = apiKeyHelper;
      force = true;
    };
  };

  # Ensure statusline.sh is executable in the dotfiles source.
  home.activation.claude-statusline-executable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    chmod +x "${dotfilesHome}/statusline.sh" 2>/dev/null || true
  '';

  home.activation.claude-remove-managed-shim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claude_shim="${config.home.homeDirectory}/.local/bin/claude"
    claude_target="$(${pkgs.coreutils}/bin/readlink "$claude_shim" 2>/dev/null || true)"

    case "$claude_target" in
      /nix/store/*-claude-code-bin-*/bin/claude)
        ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
          /usr/bin/chflags -h nouchg "$claude_shim"
        ''}
        ${pkgs.coreutils}/bin/rm -f "$claude_shim"
        ;;
    esac
  '';
}
