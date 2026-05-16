{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation {
  pname = "rime-octagram-zh-hant-essay-bgw";
  version = "2026-05-16";

  src = fetchurl {
    url = "https://media.githubusercontent.com/media/rimeinn/octagram-data/master/models/essay/zh-hant-t-essay-bgw.gram";
    hash = "sha256-V0yZ0QD0InZsQzxgHtbv1kLogdaaMN+f/7bxaVvlUOM=";
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
