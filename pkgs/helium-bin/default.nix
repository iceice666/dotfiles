{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  appimageTools,
}:

let
  pname = "helium-bin";
  version = "0.14.7.1";
  system = stdenvNoCC.hostPlatform.system;

  darwinSrcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/${version}/helium_${version}_arm64-macos.dmg";
      hash = "sha256-ZwIhBInDTRRDkp1xuZtoBIZMJ1ir0CKX1O2H1E15TxY=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/imputnet/helium-macos/releases/download/${version}/helium_${version}_x86_64-macos.dmg";
      hash = "sha256-ZYoFax1jB4XuYdxR2h5dTnN0/K0b8am6n6e5r0FJchk=";
    };
  };

  appImageSrcs = {
    "x86_64-linux" = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
      hash = "sha256-JPsCvue71hlyS9woHsauX5xM/2PUJ+n8VEjOFquUDno=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-arm64.AppImage";
      hash = "sha256-v3XFlPgrjSLkGiTknH9GEB4n/Xck2q+RXO0isL5Spi0=";
    };
  };

  meta = {
    description = "Official prebuilt Helium Browser release binaries";
    homepage = "https://helium.computer";
    changelog = "https://github.com/imputnet/helium/releases/tag/${version}";
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "helium";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };

  darwinPackage = stdenvNoCC.mkDerivation {
    inherit pname version meta;

    src = darwinSrcs.${system} or (throw "helium-bin: unsupported platform ${system}");

    dontConfigure = true;
    dontBuild = true;
    dontUnpack = true;

    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      runHook preInstall

      mountDir="$TMPDIR/helium-dmg"
      mkdir -p "$mountDir"
      /usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$mountDir" "$src"
      trap '/usr/bin/hdiutil detach "$mountDir"' EXIT

      app=""
      for candidate in "$mountDir"/*.app; do
        if [ -d "$candidate" ]; then
          app="$candidate"
          break
        fi
      done

      if [ -z "$app" ]; then
        echo "helium-bin: expected a .app bundle in the DMG"
        exit 1
      fi

      executableName=""
      for candidate in "$app"/Contents/MacOS/*; do
        if [ -f "$candidate" ] && [ -x "$candidate" ]; then
          executableName="$(basename "$candidate")"
          break
        fi
      done

      if [ -z "$executableName" ]; then
        echo "helium-bin: expected an executable in $app/Contents/MacOS"
        exit 1
      fi

      mkdir -p "$out/Applications" "$out/bin"
      cp -R "$app" "$out/Applications/"
      appName="$(basename "$app")"
      makeWrapper "$out/Applications/$appName/Contents/MacOS/$executableName" "$out/bin/helium"

      /usr/bin/hdiutil detach "$mountDir"
      trap - EXIT

      runHook postInstall
    '';
  };

  linuxPackage =
    let
      src = appImageSrcs.${system} or (throw "helium-bin: unsupported platform ${system}");
      appimageContents = appimageTools.extractType2 {
        pname = "helium";
        inherit version src;
      };
    in
    appimageTools.wrapType2 {
      pname = "helium";
      inherit version src meta;

      extraInstallCommands = ''
        if compgen -G "${appimageContents}/*.desktop" > /dev/null; then
          install -Dm444 ${appimageContents}/*.desktop -t "$out/share/applications"
          sed -i -E 's|^Exec=.*|Exec=helium %U|; s|^TryExec=.*|TryExec=helium|' \
            "$out"/share/applications/*.desktop
        fi
        if [ -d "${appimageContents}/usr/share/icons" ]; then
          cp -r "${appimageContents}/usr/share/icons" "$out/share/"
        fi
      '';
    };
in
if stdenvNoCC.hostPlatform.isDarwin then darwinPackage else linuxPackage
