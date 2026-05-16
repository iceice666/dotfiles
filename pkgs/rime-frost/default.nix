{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "rime-frost";
  version = "1.0.4";
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/gaboolic/rime-frost/archive/refs/tags/${version}.tar.gz";
    hash = "sha256-804cf4Ep1T64wgE6UeKrBHG24XQGS14ly/q6+JSXLI4=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    rm -rf .github .gitignore README.md LICENSE

    mkdir -p "$out/share/rime-data"
    cp -R . "$out/share/rime-data/"

    runHook postInstall
  '';

  meta = {
    description = "Rime Frost pinyin schema and dictionaries";
    homepage = "https://github.com/gaboolic/rime-frost";
    changelog = "https://github.com/gaboolic/rime-frost/releases/tag/${version}";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}
