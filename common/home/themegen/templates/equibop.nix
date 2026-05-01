{ lib, pkgs }:

let
  theme = import ./lib.nix { inherit lib; };

  colorRef = mode: name: "color.${mode}.${name}";
  placeholder = mode: name: theme.placeholder (colorRef mode name);

  mkThemeBlock =
    mode:
    theme.concatLines [
      ".theme-${mode}:not(.custom-user-profile-theme) {"
      "  --text-0: ${placeholder mode "background"};"
      "  --text-1: ${placeholder mode "on_background"};"
      "  --text-2: ${placeholder mode "on_surface"};"
      "  --text-3: ${placeholder mode "on_surface_variant"};"
      "  --text-4: ${placeholder mode "outline"};"
      "  --text-5: ${placeholder mode "outline"};"
      ""
      "  --bg-1: ${placeholder mode "surface_container_lowest"};"
      "  --bg-2: ${placeholder mode "surface_container_low"};"
      "  --bg-3: ${placeholder mode "surface_container"};"
      "  --bg-4: ${placeholder mode "surface"};"
      "  --hover: ${placeholder mode "surface_container_high"};"
      "  --active: ${placeholder mode "surface_container_highest"};"
      "  --active-2: ${placeholder mode "surface"};"
      "  --message-hover: ${placeholder mode "surface_container"};"
      ""
      "  --accent-1: ${placeholder mode "primary"};"
      "  --accent-2: ${placeholder mode "surface_tint"};"
      "  --accent-3: ${placeholder mode "secondary"};"
      "  --accent-4: ${placeholder mode "secondary_container"};"
      "  --accent-5: ${placeholder mode "tertiary"};"
      "  --accent-new: ${placeholder mode "error"};"
      "  --mention: linear-gradient("
      "    to right,"
      "    color-mix(in hsl, ${placeholder mode "primary_container"}, transparent 70%) 60%,"
      "    transparent"
      "  );"
      "  --mention-hover: linear-gradient("
      "    to right,"
      "    color-mix(in hsl, ${placeholder mode "primary_container"}, transparent 75%) 60%,"
      "    transparent"
      "  );"
      "  --reply: linear-gradient("
      "    to right,"
      "    color-mix(in hsl, ${placeholder mode "tertiary_container"}, transparent 70%) 60%,"
      "    transparent"
      "  );"
      "  --reply-hover: linear-gradient("
      "    to right,"
      "    color-mix(in hsl, ${placeholder mode "tertiary_container"}, transparent 75%) 60%,"
      "    transparent"
      "  );"
      ""
      "  --online: ${placeholder mode "primary"};"
      "  --dnd: ${placeholder mode "error"};"
      "  --idle: ${placeholder mode "tertiary"};"
      "  --streaming: ${placeholder mode "secondary"};"
      "  --offline: ${placeholder mode "outline"};"
      ""
      "  --border-light: ${placeholder mode "surface_container_high"};"
      "  --border: ${placeholder mode "surface_container_highest"};"
      "  --button-border: ${placeholder mode "surface_container_high"};"
      "}"
    ];

  cssTheme = pkgs.writeText "themegen-equibop.theme.css" ''
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
  '';
in
{
  generated = [
    (theme.mkRenderedFile {
      template = cssTheme;
      output = "equibop/themes/themegen-midnight.theme.css";
    })
  ];

  homeFiles = [
    (theme.mkHomeFile {
      target = "Library/Application Support/equibop/themes/themegen-midnight.theme.css";
      source = "equibop/themes/themegen-midnight.theme.css";
      platforms = [ "darwin" ];
    })
  ];
}
