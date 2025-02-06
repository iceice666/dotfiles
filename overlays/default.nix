{
  lib,
  pkgs,
  inputs,
  ...
}: {
  nixpkgs.overlays = [
     # Always applied
      inputs.rust-overlay.overlays.default
    ] ++ lib.optionals pkgs.stdenv.isDarwin [
       # Applied on Darwin
      inputs.nixpkgs-firefox-darwin.overlay
    ];
}
