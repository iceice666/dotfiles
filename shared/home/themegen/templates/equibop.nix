{ lib, pkgs }:

let
  t = import ./lib.nix { inherit lib; };

  colorRef = mode: name: "color.${mode}.${name}";
  render = mode: name: t.render (colorRef mode name);

  mkThemeBlock =
    mode:
    t.concatLines [
      ".theme-${mode}:not(.custom-user-profile-theme) {"
      "  --text-0: ${render mode "background"};"
      "  --text-1: ${render mode "on_background"};"
      "  --text-2: ${render mode "on_surface"};"
      "  --text-3: ${render mode "on_surface_variant"};"
      "  --text-4: ${render mode "outline"};"
      "  --text-5: ${render mode "outline"};"
      ""
      "  --bg-1: ${render mode "surface_container_lowest"};"
      "  --bg-2: ${render mode "surface_container_low"};"
      "  --bg-3: ${render mode "surface_container"};"
      "  --bg-4: ${render mode "surface"};"
      "  --hover: ${render mode "surface_container_high"};"
      "  --active: ${render mode "surface_container_highest"};"
      "  --active-2: ${render mode "surface"};"
      "  --message-hover: ${render mode "surface_container"};"
      ""
      "  --accent-1: ${render mode "primary"};"
      "  --accent-2: ${render mode "surface_tint"};"
      "  --accent-3: ${render mode "secondary"};"
      "  --accent-4: ${render mode "secondary_container"};"
      "  --accent-5: ${render mode "tertiary"};"
      "  --accent-new: ${render mode "error"};"
      "  --mention: linear-gradient("
      "    to right,"
      "    color-mix(in hsl, ${render mode "primary_container"}, transparent 70%) 60%,"
      "    transparent"
      "  );"
      "  --mention-hover: linear-gradient("
      "    to right,"
      "    color-mix(in hsl, ${render mode "primary_container"}, transparent 75%) 60%,"
      "    transparent"
      "  );"
      "  --reply: linear-gradient("
      "    to right,"
      "    color-mix(in hsl, ${render mode "tertiary_container"}, transparent 70%) 60%,"
      "    transparent"
      "  );"
      "  --reply-hover: linear-gradient("
      "    to right,"
      "    color-mix(in hsl, ${render mode "tertiary_container"}, transparent 75%) 60%,"
      "    transparent"
      "  );"
      ""
      "  --online: ${render mode "primary"};"
      "  --dnd: ${render mode "error"};"
      "  --idle: ${render mode "tertiary"};"
      "  --streaming: ${render mode "secondary"};"
      "  --offline: ${render mode "outline"};"
      ""
      "  --border-light: ${render mode "surface_container_high"};"
      "  --border: ${render mode "surface_container_highest"};"
      "  --button-border: ${render mode "surface_container_high"};"
      "}"
    ];
in
pkgs.writeText "themegen-equibop.theme.css" ''
  /**
   * @name Themegen Midnight
   * @description Wallpaper-derived Midnight Discord theme for Equibop with automatic light and dark mode support.
   * @author iceice666
   */

  @import url("https://refact0r.github.io/midnight-discord/build/midnight.css");

  :root {
    --colors: on;
  }

  ${mkThemeBlock "dark"}

  ${mkThemeBlock "light"}
''
