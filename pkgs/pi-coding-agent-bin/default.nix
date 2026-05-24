{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  pname = "pi-coding-agent-bin";
  version = "0.75.5";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-648DnEHoexQxyCuql/gHxNORt31m7LQeCWJwrjb5Ni0=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256-JVbFFmtJW4OArlC1ntYc8ubE19IxwN8O0hTZ3kn0faw=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256-i1xm/Duu5f6kB39iMH95LWKTZgMVs85NCUDEk1O0X1A=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256-rGh6zXJwXavpZ/1A02Uxf2gFSHi+HLLArpoFkv0Qi10=";
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
