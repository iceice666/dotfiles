{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  pname = "pi-coding-agent-bin";
  version = "0.79.0";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-fY6mXbv04e8PMJ+xfiF4DG1h4gM0xmE15VE86sIwWEo=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256-idYiVIjIVb/qzY8v6GRbEN79ka6r9/BCc+6VBmjo4u8=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256-kqn6tkKEf30iu1AUtfQKcWXXrNbh5QTkfKFCQrxIhbg=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256-DJLnOgzYwNQGDinb5ncHGRdGFwPt0sDoHqgMFMMqDao=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "pi-coding-agent-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");

in
stdenv.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/pi-coding-agent"
    cp -R . "$out/share/pi-coding-agent/"
    ln -s "$out/share/pi-coding-agent/pi" "$out/bin/pi"

    runHook postInstall
  '';

  meta = {
    description = "Official prebuilt Pi Coding Agent release binary";
    homepage = "https://github.com/earendil-works/pi";
    changelog = "https://github.com/earendil-works/pi/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = builtins.attrNames srcs;
  };
}
