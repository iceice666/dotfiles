{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
}:

let
  pname = "zed-bin";
  version = "1.0.0";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/zed-industries/zed/releases/download/v${version}/Zed-aarch64.dmg";
      hash = "sha256-G4idPLwkQnX3xl2j9tPtwTDowjpo2yRWk47tQbx+bJU=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/zed-industries/zed/releases/download/v${version}/Zed-x86_64.dmg";
      hash = "sha256-ssmw5ErCS4J7d9B9mDe3sYvuYCXcSjFGhYsvcrVcMfs=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/zed-industries/zed/releases/download/v${version}/zed-linux-x86_64.tar.gz";
      hash = "sha256-Kq1LNUgb2w7QVf1rQC7b8hb/y4r2skQGnuxLBqMR1y8=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/zed-industries/zed/releases/download/v${version}/zed-linux-aarch64.tar.gz";
      hash = "sha256-a3Z4LVHLhTNXjRACQYeUjCzhtBczRunN1M2JsSs8EbA=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "zed-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  unpackPhase = ''
    runHook preUnpack
    ${if stdenvNoCC.hostPlatform.isDarwin then "" else ''tar -xzf "$src"''}
    runHook postUnpack
  '';

  installPhase =
    if stdenvNoCC.hostPlatform.isDarwin then
      ''
        runHook preInstall

        mountDir="$TMPDIR/zed-dmg"
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
          echo "zed-bin: expected a .app bundle in the DMG"
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
          echo "zed-bin: expected an executable in $app/Contents/MacOS"
          exit 1
        fi

        mkdir -p "$out/Applications" "$out/bin"
        cp -R "$app" "$out/Applications/"
        appName="$(basename "$app")"
        makeWrapper "$out/Applications/$appName/Contents/MacOS/$executableName" "$out/bin/zed"
        ln -s zed "$out/bin/zeditor"

        /usr/bin/hdiutil detach "$mountDir"
        trap - EXIT

        runHook postInstall
      ''
    else
      ''
        runHook preInstall

        app=""
        for candidate in *.app; do
          if [ -d "$candidate" ]; then
            app="$candidate"
            break
          fi
        done

        if [ -z "$app" ]; then
          echo "zed-bin: expected a .app directory in the tarball"
          exit 1
        fi

        mkdir -p "$out/bin"
        cp -R "$app"/. "$out/"
        chmod +x "$out/bin/zed" "$out/libexec/zed-editor"
        ln -s zed "$out/bin/zeditor"

        runHook postInstall
      '';

  meta = {
    description = "Official prebuilt Zed release binaries";
    homepage = "https://zed.dev";
    changelog = "https://github.com/zed-industries/zed/releases/tag/v${version}";
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "zed";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
