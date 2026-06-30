{ lib, pkgs, ... }:

{
  home.packages =
    with pkgs;
    [
      claude-code-bin
      oh-my-pi-bin
      equibop-bin
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ zen-bin ];

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
