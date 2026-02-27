{
  lib,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation rec {
  pname = "aerospace-swipe";
  version = "0-unstable-2025-02-27";

  src = fetchFromGitHub {
    owner = "acsandmann";
    repo = "aerospace-swipe";
    rev = "976c3107f6ed9859149bdc130e3f8928f2ab6852";
    hash = "sha256-ARJfYiWXBCvXA5JlFl/s4VIQ9xuqBoU3gPfC8B2mkWI=";
  };

  buildInputs = [ ];

  makeFlags = [
    "CC=clang"
    "ARCH=-arch aarch64"
  ];

  buildPhase = ''
    runHook preBuild
    clang -std=c99 -O3 -flto -fomit-frame-pointer -funroll-loops \
      -Wall -Wextra \
      -Wno-pointer-integer-compare \
      -Wno-incompatible-pointer-types-discards-qualifiers \
      -Wno-absolute-value \
      -fobjc-arc \
      -arch arm64 \
      -o swipe \
      src/aerospace.c src/yyjson.c src/haptic.c src/event_tap.m src/main.m \
      -framework CoreFoundation \
      -framework IOKit \
      -F/System/Library/PrivateFrameworks \
      -framework MultitouchSupport \
      -framework ApplicationServices \
      -framework Cocoa \
      -ldl
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp swipe "$out/bin/aerospace-swipe"
    /usr/bin/codesign --entitlements accessibility.entitlements --sign - "$out/bin/aerospace-swipe"
    runHook postInstall
  '';

  meta = {
    description = "Switch AeroSpace workspaces with trackpad swipe gestures";
    homepage = "https://github.com/acsandmann/aerospace-swipe";
    license = lib.licenses.mit;
    mainProgram = "aerospace-swipe";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
}
