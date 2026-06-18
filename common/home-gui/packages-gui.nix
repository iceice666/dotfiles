{
  lib,
  pkgs,
  ...
}:

let
  stablePackages =
    with pkgs;
    [
      claude-code-bin
      codex-cli-bin
      oh-my-pi-bin
      equibop-bin
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ zen-bin ];
in
{
  home.packages = stablePackages;

  home.activation.claudeLocalBin = lib.hm.dag.entryAfter [ "claude-remove-self-install-shim" ] ''
    install -dm755 "$HOME/.local/bin"
    claude_link="$HOME/.local/bin/claude"
    claude_versions="$HOME/.local/share/claude/versions"

    ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
      /usr/bin/chflags -h nouchg "$claude_link" 2>/dev/null || true
    ''}

    rm -f "$claude_link"
    ln -s "${pkgs.claude-code-bin}/bin/claude" "$claude_link"

    ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
      /usr/bin/chflags -h uchg "$claude_link"
    ''}

    chmod u+w "$claude_versions" 2>/dev/null || true
    find "$claude_versions" -maxdepth 1 -mindepth 1 -delete 2>/dev/null || true
    mkdir -p "$claude_versions"
    chmod 555 "$claude_versions"
  '';
}
