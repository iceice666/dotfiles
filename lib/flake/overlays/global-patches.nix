{ }:

final: prev: {
  # Explicit consumers use this bundle without rebuilding the entire package set.
  dotfiles-cacert = prev.cacert.override {
    blacklist = import ../../tls-ca-blacklist.nix prev.cacert.version;
  };

  # Temporary official canary pin until a stable Bun includes the CA revocations.
  # The rolling URL is hash-pinned: a replaced asset fails closed.
  bun = prev.bun.overrideAttrs (old: {
    version = "1.4.4-canary.1-963452075";
    src =
      let
        sources = {
          aarch64-darwin = {
            file = "bun-darwin-aarch64.zip";
            hash = "sha256-F5ZU0l5klMX3kA0sLK9hhahX7l5MlwahS5WeLDao6Zc=";
          };
          aarch64-linux = {
            file = "bun-linux-aarch64.zip";
            hash = "sha256-c0HDsVcsTBx/NyNgtaFzExgMrBHdZw4KL2o67BzkDQU=";
          };
          x86_64-linux = {
            file = "bun-linux-x64-baseline.zip";
            hash = "sha256-Tse7kHXZVEL69rfLyNlwd2GOdJ1o81FOdutERKhqfMY=";
          };
          x86_64-darwin = {
            file = "bun-darwin-x64-baseline.zip";
            hash = "sha256-XqSi8lDWGRrXsLlMJw9dehBVfGEQbGXgb1X//ADpabg=";
          };
        };
        source = sources.${final.stdenv.hostPlatform.system};
      in
      final.fetchurl {
        url = "https://github.com/oven-sh/bun/releases/download/canary/${source.file}";
        inherit (source) hash;
      };
    meta = old.meta // {
      changelog = "https://github.com/oven-sh/bun/pull/46159";
    };
  });

  # Strips -linkmode=external from the Makefile — build fix for direnv on macOS.
  direnv = prev.direnv.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      for makefile in Makefile GNUmakefile; do
        if [ -f "$makefile" ]; then
          substituteInPlace "$makefile" --replace "-linkmode=external" ""
        fi
      done
    '';
  });
}
