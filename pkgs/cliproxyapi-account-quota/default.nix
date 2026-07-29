{
  buildGoModule,
  lib,
}:

buildGoModule {
  pname = "cliproxyapi-account-quota";
  version = "0.2.0";

  src = ./.;

  vendorHash = "sha256-g+yaVIx4jxpAQ/+WrGKxhVeliYx7nLQe/zsGpxV4Fn4=";

  buildPhase = ''
    runHook preBuild

    go build -buildmode=c-shared -trimpath -ldflags="-s -w" -o account-quota.so .

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 account-quota.so $out/lib/cliproxyapi/plugins/account-quota.so

    runHook postInstall
  '';

  meta = {
    description = "Five-hour upstream account quota reserve plugin for CLIProxyAPI";
    homepage = "https://github.com/iceice666/dotfiles";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
