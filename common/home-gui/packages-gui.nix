{
  lib,
  pkgs,
  config,
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

  home.activation.claudeLocalBin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -dm755 "$HOME/.local/bin"
    ln -sf "${config.home.profileDirectory}/bin/claude" "$HOME/.local/bin/claude"
  '';
}
