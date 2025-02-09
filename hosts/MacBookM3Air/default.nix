{...}: {
  imports = [
    ./homebrew.nix
    ./system.nix
    ./overlays.nix
    ./launchd.nix
  ];
}
