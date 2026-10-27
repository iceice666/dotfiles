{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeBinaryWrapper,
  python3,
  bash,
  cacert,
  nodejsSource,
  major,
}:

let
  releases = {
    "22" = {
      version = "22.23.4";
      sourceHash = "7b9adc82d612d0a2a863d96c46de2292552e250cee51956ebbe0146c42aacae9";
      hashes = {
        x86_64-linux = "1805bcd35e6815559bd2eb97db438d3fdb0eb3a5e6a977b7c1badca76337e9ce";
        aarch64-linux = "6287aa46b6c375d816e63ae66d024fbbfd70404825aabdfdf898a970871d2f4b";
        x86_64-darwin = "f42abca7aaac61efc57d49fb42ea84fc53bbeba9a749cb03a291ce6e4e7a69c1";
        aarch64-darwin = "037650d0839f457747396f052073fb48333d31bf5abd3c98b74da20d89ebb1ad";
      };
    };
    "24" = {
      version = "24.22.1";
      sourceHash = "4f5379796280cdaeb0c2f358fd04b6a16cc4fb7dfa83b5a8c91a9d963b435231";
      hashes = {
        x86_64-linux = "6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6";
        aarch64-linux = "dbabf7a1cbf947e6059ffad2c27b80041db97dea1e553b62afdee7f13fca336e";
        x86_64-darwin = "65e450f90a6eaacd5000f611861c4ce65fadc87f813795dc4ed0c0e5f2fca2d4";
        aarch64-darwin = "654ba79de6155647e22321932b45f2a1ccb705976cc337c9b8e278beb085a628";
      };
    };
  };
  release = releases.${major};
  inherit (release) version;
  platform = stdenvNoCC.hostPlatform;
  archivePlatform =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      x86_64-darwin = "darwin-x64";
      aarch64-darwin = "darwin-arm64";
    }
    .${platform.system} or (throw "Unsupported Node.js binary platform: ${platform.system}");
  binary = fetchurl {
    url = "https://nodejs.org/dist/v${version}/node-v${version}-${archivePlatform}.tar.xz";
    sha256 = release.hashes.${platform.system};
  };
in
assert lib.assertMsg (
  stdenvNoCC.buildPlatform == platform
) "nodejs-bin supports native builds only";
stdenvNoCC.mkDerivation {
  pname = "nodejs-slim";
  inherit version;
  # srcOnly/node-gyp need the full matching source tree, not the binary archive.
  src = fetchurl {
    url = "https://nodejs.org/dist/v${version}/node-v${version}.tar.xz";
    sha256 = release.sourceHash;
  };
  patches = [
    (nodejsSource + "/node-npm-build-npm-package-logic.patch")
  ]
  ++ lib.optionals platform.isDarwin [
    (nodejsSource + "/gyp-patches-set-fallback-value-for-CLT-darwin.patch")
  ];
  outputs = [
    "out"
    "npm"
    "corepack"
  ];
  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  # Reordering the official arm64 ELF sections makes Node crash at startup.
  patchelfFlags = lib.optionals platform.isLinux [ "--no-sort" ];
  # A compiled wrapper: Darwin rejects script interpreters in npm/corepack shebangs.
  nativeBuildInputs = [ makeBinaryWrapper ] ++ lib.optionals platform.isLinux [ autoPatchelfHook ];
  buildInputs = [ bash ] ++ lib.optionals platform.isLinux [ stdenv.cc.cc.lib ];
  setupHook = nodejsSource + "/setup-hook.sh";

  installPhase = ''
    runHook preInstall
    mkdir -p binary "$out/bin" "$out/libexec" "$out/empty-certs" "$npm/bin" "$npm/lib/node_modules" "$corepack/bin" "$corepack/lib/node_modules"
    tar -xJf ${binary} --strip-components=1 -C binary
    cp binary/bin/node "$out/libexec/node"
    cp -R binary/include binary/share "$out/"
    # Use the source's identical npm version with Nix's offline/node-gyp fixes.
    cp -R deps/npm "$npm/lib/node_modules/npm"
    cp -R deps/corepack "$corepack/lib/node_modules/corepack"
    makeWrapper "$out/libexec/node" "$out/bin/node" \
      --prefix NODE_OPTIONS " " "--use-openssl-ca" \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt \
      --set-default SSL_CERT_DIR "$out/empty-certs"
    ln -s ../lib/node_modules/npm/bin/npm-cli.js "$npm/bin/npm"
    ln -s ../lib/node_modules/npm/bin/npx-cli.js "$npm/bin/npx"
    # Match nixpkgs: do not shadow explicitly packaged pnpm/yarn with download shims.
    ln -s ../lib/node_modules/corepack/dist/corepack.js "$corepack/bin/corepack"
    runHook postInstall
  '';
  postFixup = ''
    HOST_PATH="$out/bin:${bash}/bin:$HOST_PATH" patchShebangs --host "$npm" "$corepack"
  '';
  doInstallCheck = stdenvNoCC.buildPlatform.canExecute platform;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/node" --version)" = "v${version}"
    "$out/bin/node" ${../../scripts/tests/test-nodejs-security.mjs} ${major}
    "$npm/bin/npm" --version
    "$corepack/bin/corepack" --version
    runHook postInstallCheck
  '';
  passthru = {
    python = python3;
    interpreterName = "nodejs";
    # Deliberately no libv8/dev compiler-generator outputs: archives lack them.
  };
  meta = {
    description = "Official Node.js ${major} binaries with Nix-compatible npm and explicit CA defaults";
    homepage = "https://nodejs.org/";
    changelog = "https://nodejs.org/en/blog/release/v${version}";
    license = lib.licenses.mit;
    mainProgram = "node";
    platforms = builtins.attrNames release.hashes;
  };
}
