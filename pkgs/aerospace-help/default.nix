{
  lib,
  stdenv,
  rustPlatform,
  pkg-config,
  apple-sdk_15 ? null,
}:

rustPlatform.buildRustPackage {
  pname = "aerospace-help";
  version = "0.2.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin [
    apple-sdk_15
  ];

  meta = {
    description = "Keybinding help overlay for AeroSpace window manager";
    license = lib.licenses.mit;
    mainProgram = "aerospace-help";
    platforms = lib.platforms.unix;
  };
}
