{ pkgs, ... }:

{
  home.packages =
    with pkgs;
    [
      equibop-bin
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ helium-bin ];
}
