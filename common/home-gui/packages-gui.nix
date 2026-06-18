{ pkgs, ... }:

{
  home.packages =
    with pkgs;
    [
      codex-cli-bin
      oh-my-pi-bin
      equibop-bin
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ zen-bin ];
}
