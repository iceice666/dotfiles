{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "rime-octagram-zh-hant-essay-bgw";
  version = "2026-07-12";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/lotem/rime-octagram-data/97bf55046aad163c3d1881abae5312040b1bbed9/zh-hant-t-essay-bgw.gram";
    hash = "sha256-BIjr1miPkAo5IA8reU8vmby/Ho/CcoCuSiMksIsVWcE=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm644 "$src" "$out/share/rime-data/zh-hant-t-essay-bgw.gram"

    runHook postInstall
  '';

  meta = {
    description = "Traditional Chinese essay grammar model for Rime octagram";
    homepage = "https://github.com/rimeinn/octagram-data";
    license = lib.licenses.unfreeRedistributable;
    platforms = lib.platforms.all;
  };
}
