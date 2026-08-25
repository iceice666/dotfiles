{
  fetchzip,
  lib,
  stdenvNoCC,
}:

let
  pname = "cliproxyapi-usage-keeper-plugin";
  version = "0.1.0";

  srcs = {
    "aarch64-linux" = fetchzip {
      url = "https://github.com/Willxup/cpa-plugin-usage-keeper/releases/download/v${version}/keeper_${version}_linux_arm64.zip";
      hash = "sha256-xFS3ITiy5sLVKZgvAxj9ANuyGmuf/XsBbvXRrf14FUY=";
      stripRoot = false;
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "cliproxyapi-usage-keeper-plugin: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 keeper.so "$out/lib/cliproxyapi/plugins/keeper.so"

    runHook postInstall
  '';

  meta = {
    description = "CPA Usage Keeper sidebar plugin for CLIProxyAPI Management Center";
    homepage = "https://github.com/Willxup/cpa-plugin-usage-keeper";
    changelog = "https://github.com/Willxup/cpa-plugin-usage-keeper/releases/tag/v${version}";
    license = lib.licenses.mit;
    platforms = builtins.attrNames srcs;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
