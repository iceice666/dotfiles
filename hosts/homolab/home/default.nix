{
  pkgs,
  unstablePkgs,
  ...
}:

{
  imports = [
    ./fish-pj.nix
  ];

  home.packages = [
    (if pkgs.stdenv.hostPlatform.isLinux then pkgs.mise else unstablePkgs.mise-bin)
  ];
}
