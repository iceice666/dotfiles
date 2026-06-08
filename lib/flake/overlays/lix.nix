{ }:

final: prev: {
  inherit (prev.lixPackageSets.stable)
    nix-eval-jobs
    nix-fast-build
    nixpkgs-review
    ;
}
