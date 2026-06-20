{
  lib,
  rustPlatform,
  pkg-config,
  makeWrapper,
  wayland,
  libxkbcommon,
  vulkan-loader,
  fontconfig,
  freetype,
}:

rustPlatform.buildRustPackage {
  pname = "framework-bar";
  version = "0.1.0";

  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    wayland
    libxkbcommon
    vulkan-loader
    fontconfig
    freetype
  ];

  postFixup = ''
    wrapProgram $out/bin/framework-bar \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          wayland
          libxkbcommon
          vulkan-loader
          fontconfig
          freetype
        ]
      }
  '';

  meta = {
    description = "Native iced status bar and action helper for Framework";
    homepage = "https://github.com/iceice666/dotfiles";
    license = lib.licenses.mit;
    mainProgram = "framework-bar";
    platforms = lib.platforms.linux;
  };
}
