{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation {
  pname = "ghostty-bin";
  version = "1a9d07c00fc7";

  src = fetchurl {
    url = "https://github.com/iceice666/ghostty/releases/download/fork-1a9d07c00fc7/ghostty-macos-arm64-1a9d07c00fc7.zip";
    hash = "sha256-T9Ix+k4EA+pkDpGzunOXMw5Np+OpYmears6T1DtN8wI=";
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
