{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "codex-cli-bin";
  version = "0.141.0";
  tag = "rust-v${version}";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-aarch64-apple-darwin.tar.gz";
      hash = "sha256-q96tX+68JZ3squwzRlQju7eQSzBJ+ijpIgnLkkaTwPQ=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-x86_64-apple-darwin.tar.gz";
      hash = "sha256-jJ8xgR1ln8wXxfGiG8CXGYRGnJ46Y8Kzm2HMdpTzoQE=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-aarch64-unknown-linux-musl.tar.gz";
      hash = "sha256-e3OYuT3RajEjyHKG4xKnlCvjwT+WGfxYffwFVj/LyIg=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/openai/codex/releases/download/${tag}/codex-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-8eK/n6C6brghGdYhtrcbw47dM8BtwoZ7MaAnBSNYlX0=";
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
