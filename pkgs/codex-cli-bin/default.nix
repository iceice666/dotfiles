{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "codex-cli-bin";
  version = "0.133.0";
  tag = "rust-v${version}";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-aarch64-apple-darwin.tar.gz";
      hash = "sha256-E8eDYr7/gUt93hbtdWN2I2d3Zphp3eRL0jJnNQDfaFM=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-x86_64-apple-darwin.tar.gz";
      hash = "sha256-K5G9VPBSDcmUtcMidpKA+U8cIn/bNd1V+STqyOIke5E=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-aarch64-unknown-linux-musl.tar.gz";
      hash = "sha256-Jov+jPgVSUD+olbfdc1EHFSgxx5sjM1Fqz92/yi6FBM=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-0GAZq5w10oG3jcLrsq5VwruX6hG/f0Urr+OQ7dsANO8=";
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
