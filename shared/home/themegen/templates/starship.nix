{ lib, pkgs }:

let
  t = import ./lib.nix { inherit lib; };
  color = t.color.dark;
in
pkgs.writeText "themegen-starship.toml" (
  t.concatLines [
    ""
    "palette = 'colors'"
    ""
    "[palettes.colors]"
    "color1 = '${t.render color.primary_fixed_dim}'"
    "color2 = '${t.render color.on_primary}'"
    "color3 = '${t.render color.on_surface_variant}'"
    "color4 = '${t.render color.surface_container}'"
    "color5 = '${t.render color.on_primary}'"
    "color6 = '${t.render color.surface_dim}'"
    "color7 = '${t.render color.surface}'"
    "color8 = '${t.render color.primary}'"
    "color9 = '${t.render color.tertiary}'"
    "error = '${t.render color.error}'"
  ]
)
