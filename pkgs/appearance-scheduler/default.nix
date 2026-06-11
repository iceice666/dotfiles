{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "appearance-scheduler";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Sunrise/sunset appearance switcher for macOS";
    homepage = "https://github.com/iceice666/dotfiles";
    license = lib.licenses.mit;
    mainProgram = "appearance-scheduler";
    platforms = lib.platforms.darwin;
  };
}
