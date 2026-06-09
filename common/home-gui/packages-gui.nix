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
      pi-coding-agent-bin
      equibop-bin
      ketch
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ zen-bin ];
in
{
  home.packages = stablePackages;

  home.activation.claudeLocalBin = lib.hm.dag.entryAfter [ "claude-remove-self-install-shim" ] ''
    install -dm755 "$HOME/.local/bin"
    claude_link="$HOME/.local/bin/claude"

    ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
      /usr/bin/chflags -h nouchg "$claude_link" 2>/dev/null || true
    ''}

    rm -f "$claude_link"
    ln -s "${pkgs.claude-code-bin}/bin/claude" "$claude_link"

    ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
      /usr/bin/chflags -h uchg "$claude_link"
    ''}
  '';
}
