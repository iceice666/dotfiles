{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "cliproxyapi-bin";
  version = "7.2.131";

  srcs = {
    "aarch64-linux" = fetchurl {
      url = "https://github.com/router-for-me/CLIProxyAPI/releases/download/v7.2.101/CLIProxyAPI_7.2.101_linux_aarch64.tar.gz";
      hash = "sha256-cICN1x7xJIBTH8Qns8KO94p8VrF2RQQnk3OCrS+yG3o=";
    };

    "aarch64-darwin" = fetchurl {
      url = "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${version}/CLIProxyAPI_${version}_darwin_aarch64.tar.gz";
      hash = "sha256-7GOk+Z2gKe0E2Dc8FxUidNhfUkySwbLaNrnHDLrdCv4=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${version}/CLIProxyAPI_${version}_linux_amd64.tar.gz";
      hash = "sha256-iqC1/r9Tx+8qJZi3FufzJqLs95I+q7TNAFYXGwYjvco=";
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
