{
  lib,
  stdenvNoCC,
  fetchzip,
}:

let
  pname = "mise-bin";
  version = "2026.3.10";

  srcs = {
    "aarch64-darwin" = fetchzip {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-macos-arm64.tar.gz";
      hash = "sha256-HetOYUq+WNpHdwJPczCOZFw1DwZd39PiEpC6sUE/D6w=";
      stripRoot = false;
    };

    "x86_64-linux" = fetchzip {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-linux-x64.tar.gz";
      hash = "sha256-nltNlUcJwzCv+L12D3agfiwjn5hYdM83ij+hyc2fNtM=";
      stripRoot = false;
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "mise-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R mise/. "$out/"
    chmod +x "$out/bin/mise"
    runHook postInstall
  '';

  meta = {
    description = "Upstream prebuilt mise binaries";
    homepage = "https://github.com/jdx/mise";
    changelog = "https://github.com/jdx/mise/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "mise";
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
