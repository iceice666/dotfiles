{
  lib,
  stdenvNoCC,
  runtimeShell,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  elfutils,
  expat,
  ffmpeg,
  flac,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gsettings-desktop-schemas,
  gtk3,
  harfbuzz,
  hunspell,
  jsoncpp,
  krb5,
  lcms2,
  libcap,
  libdrm,
  libevent,
  libexif,
  libgbm,
  libgcrypt,
  libGL,
  libGLU,
  libjpeg,
  libopus,
  libpng,
  libpulseaudio,
  libusb1,
  libva,
  libvpx,
  libwebp,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxscrnsaver,
  libxml2,
  libxslt,
  libxt,
  libxtst,
  libxcb,
  mesa,
  minizip,
  nspr,
  nss,
  openjpeg,
  pango,
  patchelf,
  pciutils,
  pipewire,
  qt5,
  qt6,
  re2,
  snappy,
  speechd,
  stdenv,
  systemd,
  wayland,
  zlib,
  src,
}:

let
  versionFile = src + /version;
  version =
    if builtins.pathExists versionFile then
      lib.removeSuffix "\n" (builtins.readFile versionFile)
    else
      "0-unstable";

  runtimeLibraryPath = lib.makeLibraryPath [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    elfutils
    expat
    ffmpeg
    flac
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gsettings-desktop-schemas
    gtk3
    harfbuzz
    hunspell
    jsoncpp
    krb5
    lcms2
    libcap
    libdrm
    libevent
    libexif
    libgbm
    libgcrypt
    libGL
    libGLU
    libjpeg
    libopus
    libpng
    libpulseaudio
    libusb1
    libva
    libvpx
    libwebp
    libxkbcommon
    libxml2
    libxslt
    mesa
    minizip
    nspr
    nss
    openjpeg
    pango
    pciutils
    pipewire
    qt5.qtbase
    qt6.qtbase
    re2
    snappy
    speechd
    stdenv.cc.cc.lib
    systemd
    wayland
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxscrnsaver
    libxt
    libxtst
    libxcb
    zlib
  ];
in
stdenvNoCC.mkDerivation {
  pname = "kaguya-bin";
  inherit version src;

  dontUnpack = true;

  nativeBuildInputs = [ patchelf ];

  installPhase = ''
        runHook preInstall

        mkdir -p "$out/bin" "$out/share/applications" "$out/share/icons/hicolor/256x256/apps"

        if [ ! -d "$src/app" ]; then
          cat > "$out/bin/kaguya" <<'EOF'
    #!@runtimeShell@
    echo "kaguya-bin cache is empty." >&2
    echo "Run: just kaguya" >&2
    echo "Then build/switch with the kaguya-cache flake input override." >&2
    exit 1
    EOF
          substituteInPlace "$out/bin/kaguya" \
            --replace-fail '@runtimeShell@' '${runtimeShell}'
          chmod +x "$out/bin/kaguya"

          cat > "$out/share/applications/kaguya.desktop" <<'EOF'
    [Desktop Entry]
    Type=Application
    Name=Kaguya
    GenericName=Web Browser
    Exec=kaguya %U
    Terminal=false
    Icon=kaguya
    Categories=Network;WebBrowser;
    MimeType=text/html;text/xml;application/xhtml+xml;application/xml;x-scheme-handler/http;x-scheme-handler/https;
    EOF

          runHook postInstall
          exit 0
        fi

        mkdir -p "$out/opt/kaguya"
        cp -R "$src/app"/. "$out/opt/kaguya/"
        chmod -R u+w "$out/opt/kaguya"

        if [ -f "$src/binary-name" ]; then
          binary="$(tr -d '\n' < "$src/binary-name")"
        elif [ -x "$out/opt/kaguya/kaguya" ]; then
          binary=kaguya
        elif [ -x "$out/opt/kaguya/helium" ]; then
          binary=helium
        else
          echo "kaguya-bin: no kaguya or helium executable found in $src/app" >&2
          exit 1
        fi

        if [ ! -x "$out/opt/kaguya/$binary" ]; then
          echo "kaguya-bin: recorded executable is not executable: $binary" >&2
          exit 1
        fi

        runtimeRpath='$ORIGIN:$ORIGIN/lib:$ORIGIN/lib.target:${runtimeLibraryPath}'
        while IFS= read -r -d $'\0' file; do
          if ! patchelf --print-needed "$file" >/dev/null 2>&1; then
            continue
          fi

          currentRpath="$(patchelf --print-rpath "$file" 2>/dev/null || true)"
          if [ -n "$currentRpath" ]; then
            patchelf --force-rpath --set-rpath "$currentRpath:$runtimeRpath" "$file"
          else
            patchelf --force-rpath --set-rpath "$runtimeRpath" "$file"
          fi

          if patchelf --print-interpreter "$file" >/dev/null 2>&1; then
            patchelf --set-interpreter '${stdenv.cc.bintools.dynamicLinker}' "$file"
          fi
        done < <(find "$out/opt/kaguya" -maxdepth 1 -type f -print0)

        cat > "$out/bin/kaguya" <<'EOF'
    #!@runtimeShell@
    if [ -d /run/opengl-driver/lib/dri ]; then
      export LIBGL_DRIVERS_PATH="/run/opengl-driver/lib/dri''${LIBGL_DRIVERS_PATH:+:''${LIBGL_DRIVERS_PATH}}"
    fi
    if [ -d /run/opengl-driver/lib/gbm ]; then
      export GBM_BACKENDS_PATH="/run/opengl-driver/lib/gbm''${GBM_BACKENDS_PATH:+:''${GBM_BACKENDS_PATH}}"
    fi
    if [ -d /run/opengl-driver/share/glvnd/egl_vendor.d ]; then
      export __EGL_VENDOR_LIBRARY_DIRS="/run/opengl-driver/share/glvnd/egl_vendor.d''${__EGL_VENDOR_LIBRARY_DIRS:+:''${__EGL_VENDOR_LIBRARY_DIRS}}"
    fi
    if [ -d /run/opengl-driver/lib ]; then
      export LD_LIBRARY_PATH="/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:''${LD_LIBRARY_PATH}}"
    fi
    export CHROME_WRAPPER="@out@/bin/kaguya"
    export CHROME_DESKTOP="kaguya.desktop"
    export CHROME_VERSION_EXTRA="nix"
    export LD_LIBRARY_PATH="@out@/opt/kaguya:@out@/opt/kaguya/lib:@out@/opt/kaguya/lib.target:@runtimeLibraryPath@''${LD_LIBRARY_PATH:+:''${LD_LIBRARY_PATH}}"
    exec "@out@/opt/kaguya/@binary@" "$@"
    EOF
        substituteInPlace "$out/bin/kaguya" \
          --replace-fail '@runtimeShell@' '${runtimeShell}' \
          --replace-fail '@out@' "$out" \
          --replace-fail '@runtimeLibraryPath@' '${runtimeLibraryPath}' \
          --replace-fail '@binary@' "$binary"
        chmod +x "$out/bin/kaguya"
        ln -s kaguya "$out/bin/kaguya-wrapper"

        if [ -f "$src/package/kaguya.desktop" ]; then
          install -Dm0644 "$src/package/kaguya.desktop" "$out/share/applications/kaguya.desktop"
          substituteInPlace "$out/share/applications/kaguya.desktop" \
            --replace 'Exec=kaguya-wrapper' 'Exec=kaguya'
        else
          cat > "$out/share/applications/kaguya.desktop" <<'EOF'
    [Desktop Entry]
    Type=Application
    Name=Kaguya
    GenericName=Web Browser
    Exec=kaguya %U
    Terminal=false
    Icon=kaguya
    StartupWMClass=kaguya
    Categories=Network;WebBrowser;
    MimeType=text/html;text/xml;application/xhtml+xml;application/xml;x-scheme-handler/http;x-scheme-handler/https;
    EOF
        fi

        if [ -f "$out/opt/kaguya/product_logo_256.png" ]; then
          install -Dm0644 "$out/opt/kaguya/product_logo_256.png" \
            "$out/share/icons/hicolor/256x256/apps/kaguya.png"
        fi

        runHook postInstall
  '';

  meta = {
    description = "Kaguya browser binary copied from the homolab build tree";
    homepage = "https://github.com/iceice666/kaguya-linux";
    license = lib.licenses.gpl3Only;
    mainProgram = "kaguya";
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
