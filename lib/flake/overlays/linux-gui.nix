{ inputs, nixpkgs-unstable }:

final: prev:
prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
  niri-scratchpad-helper = final.callPackage (inputs."niri-scratchpad-helper" + /src/drv.nix) { };
  reimu-on-starlit-water =
    let
      unstablePkgs = import nixpkgs-unstable {
        system = prev.stdenv.hostPlatform.system;
        config = {
          allowUnfree = true;
          cudaSupport = true;
        };
      };
    in
    final.callPackage (inputs."reimu-on-starlit-water" + /nix/package.nix) {
      rustPlatform = final.makeRustPlatform {
        inherit (unstablePkgs) cargo rustc;
      };
    };
}
