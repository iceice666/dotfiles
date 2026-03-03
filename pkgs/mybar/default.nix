{
  fetchFromGitHub,
  lib,
  stdenv,
  rustPlatform,
  pkg-config,
  python3,
  curl,
  git,
  ninja,
  cacert,
  libxkbcommon,
  wayland,
  udev,
}:

let
  pname = "mybar";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "iceice666";
    repo = pname;
    rev = "92eb526b91ff163473aeae921b06771bed3d60d3";
    hash = "sha256-oktFmVd53v4rsXevBKPXuRwo1hamLWlR+NiPZwPxchY=";
  };
in
rustPlatform.buildRustPackage {
  inherit pname version src;

  cargoLock.lockFile = "${src}/Cargo.lock";

  nativeBuildInputs = [
    pkg-config
    python3
    curl
    git
  ];

  dontUseNinjaBuild = true;

  SKIA_NINJA_COMMAND = "${ninja}/bin/ninja";
  SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  CURL_CA_BUNDLE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
  NIX_SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libxkbcommon
    wayland
    udev
  ];

  meta = {
    description = "Custom status bar";
    homepage = "https://github.com/iceice666/mybar";
    license = lib.licenses.unfree;
    mainProgram = "mybar";
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
  };
}
