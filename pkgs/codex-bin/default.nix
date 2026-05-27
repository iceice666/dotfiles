{
  lib,
  fetchurl,
  gnutar,
  gzip,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation rec {
  pname = "codex-bin";
  version = "0.133.0";

  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-0GAZq5w10oG3jcLrsq5VwruX6hG/f0Urr+OQ7dsANO8=";
  };

  nativeBuildInputs = [
    gnutar
    gzip
  ];

  dontUnpack = true;

  installPhase = ''
    install -d "$out/bin"
    tar -xzf "$src" -C "$TMPDIR"
    install -Dm755 "$TMPDIR/codex-x86_64-unknown-linux-musl" "$out/bin/codex"
  '';

  meta = {
    description = "OpenAI Codex command-line interface";
    homepage = "https://github.com/openai/codex";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
