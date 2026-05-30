{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "codex-cli-bin";
  version = "0.135.0";
  tag = "rust-v${version}";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-aarch64-apple-darwin.tar.gz";
      hash = "sha256-v+5SmujraFIUyKq2YdjWtDmzI2XSy/nVBSHNaZbUszw=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-x86_64-apple-darwin.tar.gz";
      hash = "sha256-fiavDEUU7mXG+DdJhLQrb+P3z2lzK2IwX4Xywny9xuU=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-aarch64-unknown-linux-musl.tar.gz";
      hash = "sha256-VovOHVk+8l/99VSTaahgYIVlIpRkalxJYVR6iU6i920=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-oV59rWV9pKDhIO7eKVVv7m1Q6MkZdZzC7Lo8mQmTY+I=";
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
    platforms = builtins.attrNames srcs;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
