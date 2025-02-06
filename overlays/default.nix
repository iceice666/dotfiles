{lib, pkgs, ...} : {
  imports = [
    ./common.nix

    (lib.mkIf (pkgs.stdenv.isDarwin) [
      ./darwin.nix
    ])

    (lib.mkIf (pkgs.stdenv.isLinux)[
      ./linux.nix
    ])

  ];
}
