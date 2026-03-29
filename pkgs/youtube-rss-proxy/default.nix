{
  lib,
  makeWrapper,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "youtube-rss-proxy";
  version = "0.1.0";

  src = ./.;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec"
    cp "$src/youtube-rss-proxy.py" "$out/libexec/youtube-rss-proxy.py"
    chmod +x "$out/libexec/youtube-rss-proxy.py"

    makeWrapper "${python3}/bin/python3" "$out/bin/youtube-rss-proxy" \
      --add-flags "$out/libexec/youtube-rss-proxy.py"

    runHook postInstall
  '';

  meta = {
    description = "Small YouTube RSS to JSON proxy for Homepage customapi widgets";
    homepage = "https://gethomepage.dev";
    license = lib.licenses.mit;
    mainProgram = "youtube-rss-proxy";
    platforms = lib.platforms.linux;
  };
}
