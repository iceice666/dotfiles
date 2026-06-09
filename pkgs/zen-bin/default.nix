{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
}:

let
  pname = "zen-bin";
  version = "1.20.2b";

  srcs = {
    "aarch64-darwin" = fetchurl {
      url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.macos-universal.dmg";
      hash = "sha256-T5YOjY7zU+kaSUM8AEUA+LmRWGHk8Ei6i9KWjgzFE8c=";
    };

    "x86_64-darwin" = fetchurl {
      url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.macos-universal.dmg";
      hash = "sha256-T5YOjY7zU+kaSUM8AEUA+LmRWGHk8Ei6i9KWjgzFE8c=";
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.linux-x86_64.tar.xz";
      hash = "sha256-Nq1ETAbCKw6h09HRUBPzK8nObqkHBwqyd/cA/eC8FnQ=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen.linux-aarch64.tar.xz";
      hash = "sha256-3Is7ZMikEIqgS7PooLJUoGrP1ke7+Pq16HWylKjo9Kw=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "zen-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");

  desktopItem = makeDesktopItem {
    name = "zen";
    desktopName = "Zen Browser";
    genericName = "Web Browser";
    exec = "zen %U";
    icon = "zen";
    startupWMClass = "zen";
    categories = [
      "Network"
      "WebBrowser"
    ];
    keywords = [
      "browser"
      "internet"
      "web"
      "zen"
    ];
    mimeTypes = [
      "text/html"
      "x-scheme-handler/about"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/unknown"
    ];
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;
  dontUnpack = stdenvNoCC.hostPlatform.isDarwin;

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ copyDesktopItems ];

  desktopItems = lib.optionals stdenvNoCC.hostPlatform.isLinux [ desktopItem ];

  installPhase =
    if stdenvNoCC.hostPlatform.isDarwin then
      ''
        runHook preInstall

        mountDir="$TMPDIR/zen-dmg"
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
          echo "zen-bin: expected a .app bundle in the DMG"
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
          echo "zen-bin: expected an executable in $app/Contents/MacOS"
          exit 1
        fi

        mkdir -p "$out/Applications" "$out/bin"
        cp -R "$app" "$out/Applications/"
        appName="$(basename "$app")"
        makeWrapper "$out/Applications/$appName/Contents/MacOS/$executableName" "$out/bin/zen"

        /usr/bin/hdiutil detach "$mountDir"
        trap - EXIT

        runHook postInstall
      ''
    else
      ''
        runHook preInstall

        mkdir -p "$out/opt/zen" "$out/bin" "$out/share/icons/hicolor/128x128/apps"
        cp -R . "$out/opt/zen/"
        chmod +x "$out/opt/zen/zen" "$out/opt/zen/zen-bin"
        install -Dm0644 browser/chrome/icons/default/default128.png \
          "$out/share/icons/hicolor/128x128/apps/zen.png"
        makeWrapper "$out/opt/zen/zen" "$out/bin/zen"

        runHook postInstall
      '';

  meta = {
    description = "Official prebuilt Zen Browser release binaries";
    homepage = "https://github.com/zen-browser/desktop";
    changelog = "https://github.com/zen-browser/desktop/releases/tag/${version}";
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "zen";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
