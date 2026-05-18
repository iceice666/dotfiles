{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "codex-cli-bin";
  version = "0.130.0";
  tag = "rust-v${version}";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-aarch64-apple-darwin.tar.gz";
      hash = "sha256-vFCkt/mgyMqZF5GJ5GWbYBEHgwdw4hVH3Awka85zNXc=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-x86_64-apple-darwin.tar.gz";
      hash = "sha256-/t2xFr2W19g/i7GbNPur5oQ8xkRhuvLknAF+EgatXmc=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-aarch64-unknown-linux-musl.tar.gz";
      hash = "sha256-HX4A8sIsMBa1vLccYQEJR7AiqQ4pAbxrqv6CJWSSx2c=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-Fneee3hXUIp2ijbX1OCE7sM27COUbtcKmwlIm4+GEZA=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "codex-cli-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack

    tar -xzf "$src"

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    install -Dm755 codex-* "$out/bin/codex"

    runHook postInstall
  '';

  meta = {
    description = "Official prebuilt OpenAI Codex CLI release binary";
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/openai/codex/releases/tag/${tag}";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
