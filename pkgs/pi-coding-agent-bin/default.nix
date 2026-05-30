{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  pname = "pi-coding-agent-bin";
  version = "0.78.0";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-aOu+T1ahNqHHus4zk+ykrQqh/Z8lO3l/03AFi9Of4HA=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256-ZgdLJxJgBoGZ9Hc4oXI5fx4LWjM0aX3SrOo1u9NHCxw=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256-SRVRc2gkc3INnez03uy+11T66Ekl7wA8C2aqwx1fkAU=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256-isAzQ9HhIoEG6BchV/Mta4goKeRrNP6vV38XGl8Th8w=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "pi-coding-agent-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");

in
stdenv.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/pi-coding-agent"
    cp -R . "$out/share/pi-coding-agent/"
    ln -s "$out/share/pi-coding-agent/pi" "$out/bin/pi"

    runHook postInstall
  '';

  meta = {
    description = "Official prebuilt Pi Coding Agent release binary";
    homepage = "https://github.com/earendil-works/pi";
    changelog = "https://github.com/earendil-works/pi/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = builtins.attrNames srcs;
  };
}
