{ pkgs, ... }:

let
  bsolSource = pkgs.fetchFromGitHub {
    owner = "harishnkr";
    repo = "bsol";
    rev = "afcc66069d104e4c02bc962e6bebd9c453c0f163";
    hash = "sha256-cj8yfdnR0n814piUZowUKEB2n9CWlsC97DScqxn7Cto=";
  };

  bsolTheme = pkgs.runCommandLocal "grub-bsol-theme" { } ''
    mkdir -p "$out"
    cp -R ${bsolSource}/bsol/. "$out/"
    chmod -R u+w "$out"
  '';
in
{
  boot.loader.grub.theme = bsolTheme;
}
