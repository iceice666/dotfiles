{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  pname = "claude-code-bin";
  version = "2.1.170";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-darwin-arm64.tar.gz";
      hash = "sha256-djU8RP0QapX0a7NWJ5QxRf1n3N4AP2/6/glRf4gGpLk=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-darwin-x64.tar.gz";
      hash = "sha256-r7n6LckktidF3fNDkCafP+nEZ8RudcLAs1u2+2XoOBA=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-linux-arm64.tar.gz";
      hash = "sha256-qrvisJGeg6+zUXJlV06vYLaJ3Rv37PM53WOIsaOpXsI=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-linux-x64.tar.gz";
      hash = "sha256-2u1pByAU8cYMqucLSmzSZqV6db0sT8Krd2Dm0r8o4PM=";
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
