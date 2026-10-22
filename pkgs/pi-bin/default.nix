{
  lib,
  buildNpmPackage,
  nodejs,
  makeWrapper,
  cacert,
  openssl,
  stdenv,
  autoPatchelfHook,
  libxcb,
}:

buildNpmPackage {
  pname = "pi-bin";
  version = "1.2.0";
  src = ./.;
  npmDepsHash = "sha256-d/KJcW8VNyaO3GIosgTA2VpDv2FtztjverFR2GO+Hy4=";
  dontNpmBuild = true;
  npmFlags = [ "--ignore-scripts" ];
  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libxcb ];
  nativeCheckInputs = [ openssl ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node trust.test.cjs ${cacert}/etc/ssl/certs/ca-no-trust-rules-bundle.crt
    runHook postCheck
  '';

  # Use the upstream Node distribution: the standalone Bun executable embeds a
  # separate CA store which SSL_CERT_FILE cannot replace.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec/pi" "$out/bin" "$out/empty-certs"
    cp -R node_modules "$out/libexec/pi/"
    package="$out/libexec/pi/node_modules/@earendil-works/pi-coding-agent"
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      # Only the host's native clipboard addon may be patched by autoPatchelf.
      native="$package/node_modules/@earendil-works/pi-tui/native"
      rm -rf "$native/darwin/prebuilds" "$native/win32/prebuilds"
      for prebuild in "$native/linux/prebuilds/"*; do
        if [ "$(basename "$prebuild")" != "linux-${
          if stdenv.hostPlatform.isAarch64 then "arm64" else "x64"
        }" ]; then
          rm -rf "$prebuild"
        fi
      done
    ''}
    makeWrapper ${nodejs}/bin/node "$out/bin/pi" \
      --add-flags "--use-openssl-ca $package/dist/bundle/cli.js" \
      --set PI_PACKAGE_DIR "$package" \
      --set NIX_SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-no-trust-rules-bundle.crt \
      --set SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-no-trust-rules-bundle.crt \
      --set SSL_CERT_DIR "$out/empty-certs" \
      --unset NODE_EXTRA_CA_CERTS \
      --unset NODE_USE_SYSTEM_CA
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/pi" --version)" = "$version"
    test -f "$out/libexec/pi/node_modules/@earendil-works/pi-coding-agent/docs/extensions.md"
    runHook postInstallCheck
  '';

  meta = {
    description = "Pi terminal coding agent using the system CA store";
    homepage = "https://github.com/earendil-works/pi";
    changelog = "https://github.com/earendil-works/pi/releases/tag/v1.2.0";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
