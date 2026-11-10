{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "cliproxyapi-bin";
  version = "8.0.63";

  srcs = {
    "aarch64-linux" = fetchurl {
      url = "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${version}/CLIProxyAPI_${version}_linux_aarch64.tar.gz";
      hash = "sha256-8yCRoigb6RcIYeyBu3DzVBtcHIZZ8QuqcNAV4cGpOu0=";
    };

    "aarch64-darwin" = fetchurl {
      url = "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${version}/CLIProxyAPI_${version}_darwin_aarch64.tar.gz";
      hash = "sha256-EzYplTAILWVfvf2uhmg20HCu7JN5p37xxcwlxDK2ZTo=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${version}/CLIProxyAPI_${version}_linux_amd64.tar.gz";
      hash = "sha256-vOIOfrP5hfnwO3K+IdmfBCfCUkckjU5hRJPtV85x6eU=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "cliproxyapi-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 cli-proxy-api "$out/bin/cli-proxy-api"
    install -Dm644 LICENSE "$out/share/licenses/${pname}/LICENSE"
    install -Dm644 README.md "$out/share/doc/${pname}/README.md"
    install -Dm644 config.example.yaml "$out/share/doc/${pname}/config.example.yaml"

    runHook postInstall
  '';

  meta = {
    description = "Official prebuilt CLIProxyAPI release binary";
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    changelog = "https://github.com/router-for-me/CLIProxyAPI/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "cli-proxy-api";
    platforms = builtins.attrNames srcs;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
