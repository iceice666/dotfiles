status is-interactive; or return

set -l themegen_variant dark

# Match the shell palette to the current desktop appearance when possible.
switch (uname)
case Darwin
  if defaults read -g AppleInterfaceStyle 2>/dev/null | string match -qi 'dark'
    set themegen_variant dark
  else
    set themegen_variant light
  end
case Linux
  if type -q gsettings
    set -l color_scheme (gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | string trim -c "'")

    if test "$color_scheme" = prefer-dark
      set themegen_variant dark
    else if test -n "$color_scheme"
      set themegen_variant light
    else
      set -l gtk_theme (gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | string trim -c "'")

      if string match -qi '*dark*' -- $gtk_theme
        set themegen_variant dark
      else if test -n "$gtk_theme"
        set themegen_variant light
      end
    end
  end
end

switch $themegen_variant
case light
  printf '\e]4;0;{{color.light.on_surface}}\e\\'
  printf '\e]4;1;{{base16.light.base08}}\e\\'
  printf '\e]4;2;{{base16.light.base0B}}\e\\'
  printf '\e]4;3;{{base16.light.base0A}}\e\\'
  printf '\e]4;4;{{base16.light.base0D}}\e\\'
  printf '\e]4;5;{{base16.light.base0E}}\e\\'
  printf '\e]4;6;{{base16.light.base0C}}\e\\'
  printf '\e]4;7;{{color.light.surface_dim}}\e\\'
  printf '\e]4;8;{{color.light.on_surface}}\e\\'
  printf '\e]4;9;{{base16.light.base08}}\e\\'
  printf '\e]4;10;{{base16.light.base0B}}\e\\'
  printf '\e]4;11;{{base16.light.base0A}}\e\\'
  printf '\e]4;12;{{base16.light.base0D}}\e\\'
  printf '\e]4;13;{{base16.light.base0E}}\e\\'
  printf '\e]4;14;{{base16.light.base0C}}\e\\'
  printf '\e]4;15;{{color.light.surface_container_high}}\e\\'
  printf '\e]10;{{color.light.on_surface}}\e\\'
  printf '\e]11;{{color.light.surface_container_low}}\e\\'
  printf '\e]12;{{color.light.primary}}\e\\'
  printf '\e]17;{{color.light.secondary_container}}\e\\'
  printf '\e]19;{{color.light.on_secondary_container}}\e\\'
case '*'
  printf '\e]4;0;{{color.dark.surface_dim}}\e\\'
  printf '\e]4;1;{{base16.dark.base08}}\e\\'
  printf '\e]4;2;{{base16.dark.base0B}}\e\\'
  printf '\e]4;3;{{base16.dark.base0A}}\e\\'
  printf '\e]4;4;{{base16.dark.base0D}}\e\\'
  printf '\e]4;5;{{base16.dark.base0E}}\e\\'
  printf '\e]4;6;{{base16.dark.base0C}}\e\\'
  printf '\e]4;7;{{color.dark.on_surface}}\e\\'
  printf '\e]4;8;{{color.dark.surface_container_high}}\e\\'
  printf '\e]4;9;{{base16.dark.base08}}\e\\'
  printf '\e]4;10;{{base16.dark.base0B}}\e\\'
  printf '\e]4;11;{{base16.dark.base0A}}\e\\'
  printf '\e]4;12;{{base16.dark.base0D}}\e\\'
  printf '\e]4;13;{{base16.dark.base0E}}\e\\'
  printf '\e]4;14;{{base16.dark.base0C}}\e\\'
  printf '\e]4;15;{{color.dark.on_surface}}\e\\'
  printf '\e]10;{{color.dark.on_surface}}\e\\'
  printf '\e]11;{{color.dark.surface_container_low}}\e\\'
  printf '\e]12;{{color.dark.primary}}\e\\'
  printf '\e]17;{{color.dark.secondary_container}}\e\\'
  printf '\e]19;{{color.dark.on_secondary_container}}\e\\'
end
