{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "themegen";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Generate Material You and Base16 palettes from an image";
    homepage = "https://github.com/iceice666/dotfiles";
    license = lib.licenses.mit;
    mainProgram = "themegen";
    platforms = lib.platforms.unix;
  };
}
