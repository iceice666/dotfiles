{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchzip,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  autoPatchelfHook,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libuuid,
  libxcb,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
  wayland,
  xorg,
}:

let
  pname = "equibop-bin";
  version = "3.2.1";

  srcs = {
    "aarch64-darwin" = fetchzip {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/Equibop-${version}-universal-mac.zip";
      hash = "sha256-UhTYfiEoEmpbKrpf15MXD6cI7u5tubuIx6bpNNni+po=";
      stripRoot = false;
    };

    "x86_64-darwin" = fetchzip {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/Equibop-${version}-universal-mac.zip";
      hash = "sha256-UhTYfiEoEmpbKrpf15MXD6cI7u5tubuIx6bpNNni+po=";
      stripRoot = false;
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/equibop-${version}.tar.gz";
      hash = "sha256-iJ2NuXYs8VxDXDIjfa77wjZMA5DpS3dOZtaNdz4PhJM=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/equibop-${version}-arm64.tar.gz";
      hash = "sha256-OEK3RIxFqyJK2RuVGUgAAuJgK9OuxBqLgENjYkIaMEs=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "equibop-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");

  sourceAssets = fetchzip {
    url = "https://github.com/Equicord/Equibop/archive/refs/tags/v${version}.tar.gz";
    hash = "sha256-WqfxrVAJvD6Y6ZjkhbvibL6Bps7PL2lx3JBY94Yd6kk=";
  };

in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
    autoPatchelfHook
    copyDesktopItems
  ];

  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libglvnd
    libnotify
    libpulseaudio
    libuuid
    libxcb
    libxkbcommon
    mesa
    nspr
    nss
    pango
    pipewire
    systemd
    wayland
    xorg.libX11
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXrender
    xorg.libXScrnSaver
    xorg.libXtst
    xorg.libxshmfence
  ];

  installPhase =
    if stdenvNoCC.hostPlatform.isDarwin then
      ''
        runHook preInstall
        mkdir -p "$out/Applications" "$out/bin"
        mv Equibop.app "$out/Applications/"
        makeWrapper "$out/Applications/Equibop.app/Contents/MacOS/Equibop" "$out/bin/equibop"
        runHook postInstall
      ''
    else
      ''
        runHook preInstall
        # Tarball unpacks to equibop-<version>/ — sourceRoot is that directory
        mkdir -p "$out/opt/equibop" "$out/bin"
        cp -r . "$out/opt/equibop/"
        chmod +x "$out/opt/equibop/equibop"
        install -Dm0644 "${sourceAssets}/build/icon.svg" "$out/share/icons/hicolor/scalable/apps/org.equicord.equibop.svg"
        makeWrapper "$out/opt/equibop/equibop" "$out/bin/equibop" \
          --prefix LD_LIBRARY_PATH : "${
            lib.makeLibraryPath [
              libglvnd
              libpulseaudio
              pipewire
            ]
          }:$out/opt/equibop" \
          --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations,WebRTCPipeWireCapturer --enable-webrtc-pipewire-capturer --enable-wayland-ime=true --disable-gpu-memory-buffer-video-frames}}"
        runHook postInstall
      '';

  desktopItems = lib.optionals stdenvNoCC.hostPlatform.isLinux [
    (makeDesktopItem {
      name = "org.equicord.equibop";
      desktopName = "Equibop";
      exec = "equibop %U";
      icon = "org.equicord.equibop";
      startupWMClass = "equibop";
      genericName = "Internet Messenger";
      mimeTypes = [ "x-scheme-handler/discord" ];
      keywords = [
        "discord"
        "vencord"
        "electron"
        "chat"
        "equibop"
      ];
      categories = [
        "Network"
        "InstantMessaging"
        "Chat"
      ];
    })
  ];

  meta = {
    description = "Custom Discord app with Equicord built-in (pre-built binary)";
    homepage = "https://github.com/Equicord/Equibop";
    changelog = "https://github.com/Equicord/Equibop/releases/tag/v${version}";
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "equibop";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
