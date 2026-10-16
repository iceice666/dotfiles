{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation {
  pname = "ghostty-bin";
  version = "4df2074389ca";

  src = fetchurl {
    url = "https://github.com/iceice666/ghostty/releases/download/fork-4df2074389ca/ghostty-macos-arm64-4df2074389ca.zip";
    hash = "sha256-NbKo55c7Crb8w85lt14HQmY7OeQuY20GB4Y0d0rPuYc=";
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
