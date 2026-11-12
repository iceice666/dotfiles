{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  pname = "claude-code-bin";
  version = "2.1.322";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-darwin-arm64.tar.gz";
      hash = "sha256-D/OJ8aMT9Qd4wkcsL4WILKgsEBVjmMaM/DwzIARpRkY=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-darwin-x64.tar.gz";
      hash = "sha256-enKRxa4ByPjpHcJjbaQ/kFvTy1KxFwIphQ+D8/7xlOE=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-linux-arm64.tar.gz";
      hash = "sha256-ZcGtNegE70Y/NFhdDAgK/Uvy6QGMe60fKe+4306cN1A=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-linux-x64.tar.gz";
      hash = "sha256-PSvFrlTU1M1jUQ6fzKW21I0rGIBnCN+Mj2kapIbF3Kg=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "claude-code-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");

in
stdenv.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack

    tar -xzf "$src"

    runHook postUnpack
  '';

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 claude "$out/bin/claude"

    runHook postInstall
  '';

  meta = {
    description = "Official prebuilt Anthropic Claude Code CLI release binary";
    homepage = "https://github.com/anthropics/claude-code";
    changelog = "https://github.com/anthropics/claude-code/releases/tag/v${version}";
    license = lib.licenses.unfree;
    mainProgram = "claude";
    platforms = builtins.attrNames srcs;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
