{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  pname = "claude-code-bin";
  version = "2.1.169";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-darwin-arm64.tar.gz";
      hash = "sha256-j5ubTiHg/IIiphH4tGdhIdNXw49ZPV/c4CP42kRSsEs=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-darwin-x64.tar.gz";
      hash = "sha256-EnEWz8FjVlen7x7BQJbd0En3Kw75Ad/pyvg3K2wjDRo=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-linux-arm64.tar.gz";
      hash = "sha256-ovnNmoIXsIaD9WHTYwYqHnWruXSOeAZft8fwevcyWg0=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-linux-x64.tar.gz";
      hash = "sha256-Xy93ikYII1BZR7P+yTJXWQe2FPZ9yPE01dJz5vklKZU=";
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
