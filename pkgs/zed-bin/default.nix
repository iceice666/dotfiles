{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
}:

let
  pname = "zed-bin";
  version = "1.9.0";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/zed-industries/zed/releases/download/v${version}/Zed-aarch64.dmg";
      hash = "sha256-Dcir+ZSOqj4+Xnb/db9TfZO7bx0qV/vaL3zHO/jSgFU=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/zed-industries/zed/releases/download/v1.8.2/Zed-x86_64.dmg";
      hash = "sha256-JYB68tRbtq16e3bX2Xf9DvmAe7FF+NpeVSR2oezp/X8=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/zed-industries/zed/releases/download/v${version}/zed-linux-x86_64.tar.gz";
      hash = "sha256-OeVTzjoA/ut46rY6XLcjfLRg88lZaxsZBSzre56OxN0=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/zed-industries/zed/releases/download/v1.8.2/zed-linux-aarch64.tar.gz";
      hash = "sha256-ouer4UqVyIeOW2tHWMsb4DHvM2VJ/mzIAT9tF6c9sdA=";
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
