{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchzip,
  makeWrapper,
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
  libnotify,
  libuuid,
  libxcb,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  wayland,
  xorg,
}:

let
  pname = "equibop-bin";
  version = "3.2.0";

  srcs = {
    "aarch64-darwin" = fetchzip {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/Equibop-${version}-universal-mac.zip";
      hash = "sha256-XqVTNHT3Ot9sOvFIbgMAm4GHdZTd1diX2F5YC/7x5Oc=";
      stripRoot = false;
    };

    "x86_64-darwin" = fetchzip {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/Equibop-${version}-universal-mac.zip";
      hash = "sha256-XqVTNHT3Ot9sOvFIbgMAm4GHdZTd1diX2F5YC/7x5Oc=";
      stripRoot = false;
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/equibop-${version}.tar.gz";
      hash = "sha256-/UyIGRfNjYGpwIjNJhmVisq0RThEdQZ5Dj5aLP+U9ww=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/equibop-${version}-arm64.tar.gz";
      hash = "sha256-cndZGf0TPRLYBbGAqHuuqUFGzJ4NeUqp2RfLmBp/7F8=";
    };
  };

  src =
    srcs.${stdenvNoCC.hostPlatform.system}
      or (throw "equibop-bin: unsupported platform ${stdenvNoCC.hostPlatform.system}");

in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];

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
    libnotify
    libuuid
    libxcb
    libxkbcommon
    mesa
    nspr
    nss
    pango
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
        makeWrapper "$out/opt/equibop/equibop" "$out/bin/equibop" \
          --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
        runHook postInstall
      '';

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
