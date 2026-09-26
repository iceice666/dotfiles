{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "framework-shell-state";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "JSON state stream and action helper for the Framework desktop shell";
    homepage = "https://github.com/iceice666/dotfiles";
    license = lib.licenses.mit;
    mainProgram = "framework-shell-state";
    platforms = lib.platforms.linux;
  };
}
