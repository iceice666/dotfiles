{
  inputs,
  nixpkgs-unstable,
  dotfiles,
}:

final: prev:
(import ./lix.nix { } final prev)
// (import ./binaries.nix { inherit dotfiles; } final prev)
// (import ./linux-gui.nix { inherit inputs nixpkgs-unstable; } final prev)
// (import ./global-patches.nix { } final prev)
// (inputs.pirc.overlays.default final prev)
// {
  ghostty =
    if final.stdenv.hostPlatform.isDarwin then
      final.callPackage (dotfiles + /pkgs/ghostty-bin) { }
    else
      inputs.ghostty.packages.${final.stdenv.hostPlatform.system}.default;
}
