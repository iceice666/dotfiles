{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  pname = "pi-coding-agent-bin";
  version = "0.79.1";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-djiU+eVgt+sw8oeyEVpSv/rj1vNFOm1RvlJYQFkfZXU=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256-fbE/6NPGWCPW77H5gTa/JiiYQsLmpm/Ik9IMM0wLu7M=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256-oZGgyNV6vxQkxWD1OYHCoHD3TShjpHp5WOsWxVbEvAQ=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256-3BnSsk0Vx2lR/kQKR6ghLO20N6JWluvyelVIEVbenoY=";
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
