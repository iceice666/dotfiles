{ }:

final: prev: {
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
