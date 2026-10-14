{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  glibc,
}:

let
  pname = "pi-bin";
  version = "1.2.0";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-q933aItLZ4HZET9jzVeOPAHc24fnH2bn7ByexsdheNE=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256-4Hn/AWrngnnPvWwbT//gchYvSnu4ea1hsE4uQ7zFNFU=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256-2Fl+46IFBZLTjmf2tgmrVROd7tfoIAINkQ2E8Xu3q9Y=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256-APw2z/3rzupaSCMNpizz+0YxePj+GFdmZS+WACokaEc=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "pi-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  # Rewriting or stripping Bun's standalone ELF can corrupt its embedded module graph.
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/pi"
    cp -R . "$out/libexec/pi/"

    ${
      if stdenvNoCC.hostPlatform.isLinux then
        ''
          # Pi needs glibc; its bundled clipboard addon also needs libgcc_s.
          # Invoke the Nix loader explicitly, including on musl hosts without nix-ld.
          makeWrapper "${stdenv.cc.bintools.dynamicLinker}" "$out/bin/pi" \
            --add-flags "--library-path ${
              lib.makeLibraryPath [
                glibc
                stdenv.cc.cc.lib
              ]
            } $out/libexec/pi/pi" \
            --set PI_PACKAGE_DIR "$out/libexec/pi"
        ''
      else
        ''
          makeWrapper "$out/libexec/pi/pi" "$out/bin/pi" \
            --set PI_PACKAGE_DIR "$out/libexec/pi"
        ''
    }

    runHook postInstall
  '';

  meta = {
    description = "Pi terminal coding agent";
    homepage = "https://github.com/earendil-works/pi";
    changelog = "https://github.com/earendil-works/pi/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = builtins.attrNames srcs;
  };
}
