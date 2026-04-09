{
  lib,
  stdenvNoCC,
  fetchurl,
  cpio,
  gzip,
  xar,
}:

let
  pname = "default-browser";
  version = "1.0.18";
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/macadmins/default-browser/releases/download/v${version}/default-browser.pkg";
    hash = "sha256-oVPAoLwHJibT3jAMe4LPLeVK49VYMJDf92wqTb4zAdg=";
  };

  nativeBuildInputs = [
    cpio
    gzip
    xar
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p package unpacked "$out/bin"

    cd package
    xar -xf "$src"

    cd ../unpacked
    gzip -dc ../package/Payload | cpio -id

    cp opt/macadmins/bin/default-browser "$out/bin/default-browser"
    chmod +x "$out/bin/default-browser"

    runHook postInstall
  '';

  meta = {
    description = "Set the default browser for the current macOS user";
    homepage = "https://github.com/macadmins/default-browser";
    changelog = "https://github.com/macadmins/default-browser/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "default-browser";
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
