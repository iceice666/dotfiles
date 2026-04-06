{ lib, pkgs }:

let
  t = import ./lib.nix { inherit lib; };
in
pkgs.writeText "themegen-starship.toml" (
  t.concatLines [
    ""
    "palette = 'colors'"
    ""
    "[palettes.colors]"
    "color1 = '${t.render (t.colorExpr "dark" "primary_fixed_dim")}'"
    "color2 = '${t.render (t.colorExpr "dark" "on_primary")}'"
    "color3 = '${t.render (t.colorExpr "dark" "on_surface_variant")}'"
    "color4 = '${t.render (t.colorExpr "dark" "surface_container")}'"
    "color5 = '${t.render (t.colorExpr "dark" "on_primary")}'"
    "color6 = '${t.render (t.colorExpr "dark" "surface_dim")}'"
    "color7 = '${t.render (t.colorExpr "dark" "surface")}'"
    "color8 = '${t.render (t.colorExpr "dark" "primary")}'"
    "color9 = '${t.render (t.colorExpr "dark" "tertiary")}'"
    "error = '${t.render (t.colorExpr "dark" "error")}'"
  ]
)
