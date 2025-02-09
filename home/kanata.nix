{...}: {
  imports = [
    ../derivation/kanata-bin-darwin.nix
  ];

  programs.kanata-bin-darwin = {
    enable = true;
    configFile.source = ../config/kanata.kbd;
  };
}
