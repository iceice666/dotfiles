{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "oh-my-pi-bin";
  version = "16.2.2";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-darwin-arm64";
      hash = "sha256-T+lFgCo6c+SDfGKhglviVVEKL1KePsPx9jdg8DG4X+I=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-darwin-x64";
      hash = "sha256-9h0kdlcai0FX7C25erm4YOFe6lYxCd40QxoRoAyvI0Y=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-arm64";
      hash = "sha256-QLV9X06Y3047n+KeBYNKaM87014L/OUhL/qyd6J3kMI=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-x64";
      hash = "sha256-XP34rq0x71OVlrils/GukcKwx/aqGJ+sJPc8auN/L/s=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "oh-my-pi-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");

in
stdenv.mkDerivation {
  inherit pname version src;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  # Any ELF rewriting (patchelf --set-interpreter, --shrink-rpath) or strip
  # operation corrupts Bun's standalone executable by zeroing the BUN_COMPILED
  # section header that points to the embedded module graph. The binary works
  # unpatched because nix-ld provides /lib64/ld-linux-x86-64.so.2.
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/bin/omp"

    runHook postInstall
  '';

  meta = {
    description = "oh-my-pi (omp): feature-rich terminal coding agent forked from Pi";
    homepage = "https://github.com/can1357/oh-my-pi";
    changelog = "https://github.com/can1357/oh-my-pi/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "omp";
    platforms = builtins.attrNames srcs;
  };
}
