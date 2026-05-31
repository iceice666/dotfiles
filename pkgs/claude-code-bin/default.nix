{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  pname = "claude-code-bin";
  version = "2.1.158";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-darwin-arm64.tar.gz";
      hash = "sha256-eQ4bmEzBtyzbHZikxH2PYfk56OpP+oDA7xrEUIN0PlY=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-darwin-x64.tar.gz";
      hash = "sha256-+xkQbtoNkF8OE4r0rVFXc44YBGUC8yHtNQetRKKlYr0=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-linux-arm64.tar.gz";
      hash = "sha256-Y5LcUgLp2+oG7TQQt+Tux1MMta4XQ3FfS3G3IwJBqTI=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-linux-x64.tar.gz";
      hash = "sha256-K6gVZmovBg7hSQ9SGO7O8Rx/9vovhTdzFiefz8ywQ0A=";
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
