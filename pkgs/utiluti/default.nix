{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "utiluti";
  version = "1.5";
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/scriptingosx/utiluti/releases/download/v${version}/utiluti-${version}.pkg";
    hash = "sha256-cBhLUejsABesbi3q4jntgmWJAlgpgttXSRLKiIT+Bh8=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/man/man1"
    /usr/sbin/pkgutil --expand-full "$src" package

    cp package/utiluti.pkg/Payload/usr/local/bin/utiluti "$out/bin/utiluti"
    cp package/utiluti.pkg/Payload/usr/local/share/man/man1/utiluti.1 "$out/share/man/man1/utiluti.1"
    chmod +x "$out/bin/utiluti"

    runHook postInstall
  '';

  meta = {
    description = "Manage default macOS apps for URL schemes and file types";
    homepage = "https://github.com/scriptingosx/utiluti";
    changelog = "https://github.com/scriptingosx/utiluti/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "utiluti";
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
