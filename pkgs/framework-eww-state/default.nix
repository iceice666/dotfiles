{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "framework-eww-state";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "State daemon and action helper for the Framework Eww bar";
    homepage = "https://github.com/iceice666/dotfiles";
    license = lib.licenses.mit;
    mainProgram = "framework-eww-state";
    platforms = lib.platforms.linux;
  };
}
