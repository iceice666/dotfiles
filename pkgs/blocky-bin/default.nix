{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  pname = "blocky-bin";
  version = "0.32.1";

  srcs = {
    "x86_64-linux" = fetchurl {
      url = "https://github.com/0xERR0R/blocky/releases/download/v${version}/blocky_v${version}_Linux_x86_64.tar.gz";
      hash = "sha256-H08f4bcwUi4DfFVPUaDvQ0mIWAEaa2ewxdpI2lruDi8=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "blocky-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 blocky "$out/bin/blocky"

    runHook postInstall
  '';

  meta = {
    description = "Official prebuilt Blocky DNS proxy release binary";
    homepage = "https://github.com/0xERR0R/blocky";
    changelog = "https://github.com/0xERR0R/blocky/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "blocky";
    platforms = builtins.attrNames srcs;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
