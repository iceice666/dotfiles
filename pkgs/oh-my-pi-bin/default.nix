{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "oh-my-pi-bin";
  version = "16.1.1";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-darwin-arm64";
      hash = "sha256-GElIjKPVlGM6/dub25yRP1png42X7V1pckwoIAbBiWI=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-darwin-x64";
      hash = "sha256-zN4/fHGe4gGDiWrF0rhLZqnuqPKHgXFL9hil/rZvhQc=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-arm64";
      hash = "sha256-XRuVHuNLMoymTeOygyu25cBkoHd58ueu0cwZMWKZxKw=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-x64";
      hash = "sha256-SL5wBZk1YEfclCyr5WdWd4rdKpAjLa44d7TUBAiUY5A=";
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
