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

    rm -f "$out"/*.pf2
    ${pkgs.grub2}/bin/grub-mkfont \
      --name "Victor Mono" \
      --size 20 \
      --output "$out/victor-mono-regular-20.pf2" \
      ${pkgs.victor-mono}/share/fonts/opentype/VictorMono-Regular.otf
    ${pkgs.grub2}/bin/grub-mkfont \
      --name "Victor Mono" \
      --size 24 \
      --output "$out/victor-mono-bold-24.pf2" \
      ${pkgs.victor-mono}/share/fonts/opentype/VictorMono-Bold.otf
    ${pkgs.grub2}/bin/grub-mkfont \
      --name "Victor Mono" \
      --size 28 \
      --output "$out/victor-mono-bold-28.pf2" \
      ${pkgs.victor-mono}/share/fonts/opentype/VictorMono-Bold.otf

    substituteInPlace "$out/theme.txt" \
      --replace-fail "Victor Mono Italic 20" "Victor Mono Regular 20" \
      --replace-fail "Victor Mono Bold Italic 24" "Victor Mono Bold 24" \
      --replace-fail "Victor Mono Bold Italic 28" "Victor Mono Bold 28"
  '';
in
{
  boot.loader.grub.theme = bsolTheme;
}
