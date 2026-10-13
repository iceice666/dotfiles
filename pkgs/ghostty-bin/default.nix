{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation {
  pname = "ghostty-bin";
  version = "905108bca070";

  src = fetchurl {
    url = "https://github.com/iceice666/ghostty/releases/download/fork-905108bca070/ghostty-macos-arm64-905108bca070.zip";
    hash = "sha256-1q/DdVq3vc8VBaxUhAuX5V+3uj8lgR70GA39pxv97PY=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R Ghostty.app "$out/Applications/"
    ln -s "$out/Applications/Ghostty.app/Contents/MacOS/ghostty" "$out/bin/ghostty"
    runHook postInstall
  '';

  meta = {
    description = "Personal Ghostty fork with vertical tabs (ad-hoc signed macOS build)";
    homepage = "https://github.com/iceice666/ghostty";
    license = lib.licenses.mit;
    mainProgram = "ghostty";
    platforms = [ "aarch64-darwin" ];
  };
}
