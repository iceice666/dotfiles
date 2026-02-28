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
  version = "3.1.9";

  srcs = {
    "aarch64-darwin" = fetchzip {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/Equibop-${version}-universal-mac.zip";
      hash = "sha256-2DAM5sb4tGn7BlgNF5AtZ1o0uiBqb0h+GPDuXUKr4MY=";
      stripRoot = false;
    };

    "x86_64-darwin" = fetchzip {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/Equibop-${version}-universal-mac.zip";
      hash = "sha256-2DAM5sb4tGn7BlgNF5AtZ1o0uiBqb0h+GPDuXUKr4MY=";
      stripRoot = false;
    };

    "x86_64-linux" = fetchurl {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/equibop-${version}.tar.gz";
      hash = "sha256-40SUavhqhcYLxOfMnvv8OsP+58QWNLzhdEu0GmwLRp8=";
    };

    "aarch64-linux" = fetchurl {
      url = "https://github.com/Equicord/Equibop/releases/download/v${version}/equibop-${version}-arm64.tar.gz";
      hash = "sha256-1suu4k9tCeeRfaMaw3Q+WNL17nxaJkIGodac1uhK1nU=";
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
