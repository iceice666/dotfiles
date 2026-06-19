{ pkgs, ... }:

{
  home.packages =
    with pkgs;
    [
      oh-my-pi-bin
      equibop-bin
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ zen-bin ];
}
