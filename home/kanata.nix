{...}: {
  imports = [
    ../derivation/kanata-bin-darwin.nix
  ];

  programs.kanata-bin-darwin = {
    enable = true;
  };
}
