{
  imports = [
    ../../derivation/kanata-bin-darwin.nix
  ];

  # Conditionally set attributes inside the same attribute set
  programs.kanata-bin-darwin = {
    enable = true;
    configFile.source = ../../config/kanata.kbd;
    setupLaunchd = true;
  };
}
