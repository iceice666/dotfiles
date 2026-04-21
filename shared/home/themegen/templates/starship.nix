{ lib, pkgs }:

let
  theme = import ./lib.nix { inherit lib; };
  color = theme.color.dark;

  starshipPalette = pkgs.writeText "themegen-starship.toml" (
    theme.concatLines [
      ""
      "palette = 'colors'"
      ""
      "[palettes.colors]"
      "color1 = '${theme.placeholder color.primary_fixed_dim}'"
      "color2 = '${theme.placeholder color.on_primary}'"
      "color3 = '${theme.placeholder color.on_surface_variant}'"
      "color4 = '${theme.placeholder color.surface_container}'"
      "color5 = '${theme.placeholder color.on_primary}'"
      "color6 = '${theme.placeholder color.surface_dim}'"
      "color7 = '${theme.placeholder color.surface}'"
      "color8 = '${theme.placeholder color.primary}'"
      "color9 = '${theme.placeholder color.tertiary}'"
      "error = '${theme.placeholder color.error}'"
    ]
  );
in
{
  generated = [
    (theme.mkRenderedFile {
      template = starshipPalette;
      output = "starship.toml";
    })
  ];

  homeFiles = [
    (theme.mkHomeFile {
      target = ".config/starship.toml";
      source = "starship.toml";
    })
  ];
}
