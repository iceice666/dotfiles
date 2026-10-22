{
  inputs,
  nixpkgs-unstable,
  dotfiles,
}:

final: prev:
let
  pircOverlay = inputs.pirc.overlays.default final prev;
  # feat/pirc-harmony (ec46ce5d) ships a stale cargoHash; drop this once
  # upstream nix/package.nix is fixed.
  pircCargoHash =
    pkg:
    pkg.overrideAttrs (old: {
      cargoDeps = old.cargoDeps.overrideAttrs (_: {
        vendorStaging = old.cargoDeps.vendorStaging.overrideAttrs (_: {
          outputHash = "sha256-7EquFYt+t23tuPsJJ2ktOSSpy0NJMmAvGsjx6jqRkbo=";
        });
      });
    });
in
(import ./lix.nix { } final prev)
// (import ./binaries.nix { inherit dotfiles; } final prev)
// (import ./linux-gui.nix { inherit inputs nixpkgs-unstable; } final prev)
// (import ./global-patches.nix { } final prev)
// {
  pirc-gateway = pircCargoHash pircOverlay.pirc-gateway;
  pirc-node = pircCargoHash pircOverlay.pirc-node;
}
// {
  ghostty =
    if final.stdenv.hostPlatform.isDarwin then
      final.callPackage (dotfiles + /pkgs/ghostty-bin) { }
    else
      inputs.ghostty.packages.${final.stdenv.hostPlatform.system}.default;
}
