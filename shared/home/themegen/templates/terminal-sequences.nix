{ lib, pkgs }:

let
  theme = import ./lib.nix { inherit lib; };

  mkAnsiLines =
    mode:
    let
      terminal = theme.terminal mode;
      prefix = "  printf '\\e]";
      suffix = "\\e\\\\'";
    in
    (builtins.genList (
      index: "${prefix}4;${toString index};${builtins.elemAt terminal.ansi16 index}${suffix}"
    ) 16)
    ++ [
      "${prefix}10;${terminal.foreground}${suffix}"
      "${prefix}11;${terminal.background}${suffix}"
      "${prefix}12;${terminal.cursor}${suffix}"
      "${prefix}17;${terminal.selectionBackground}${suffix}"
      "${prefix}19;${terminal.selectionForeground}${suffix}"
    ];

  terminalSequences = pkgs.writeText "themegen-terminal-sequences.fish" (
    theme.concatLines (
      [
        "status is-interactive; or return"
        ""
        "set -l themegen_variant dark"
        ""
        "# Match the shell palette to the current desktop appearance when possible."
        "switch (uname)"
        "case Darwin"
        "  if defaults read -g AppleInterfaceStyle 2>/dev/null | string match -qi 'dark'"
        "    set themegen_variant dark"
        "  else"
        "    set themegen_variant light"
        "  end"
        "case Linux"
        "  if type -q gsettings"
        "    set -l color_scheme (gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | string trim -c \"'\")"
        ""
        "    if test \"$color_scheme\" = prefer-dark"
        "      set themegen_variant dark"
        "    else if test -n \"$color_scheme\""
        "      set themegen_variant light"
        "    else"
        "      set -l gtk_theme (gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | string trim -c \"'\")"
        ""
        "      if string match -qi '*dark*' -- $gtk_theme"
        "        set themegen_variant dark"
        "      else if test -n \"$gtk_theme\""
        "        set themegen_variant light"
        "      end"
        "    end"
        "  end"
        "end"
        ""
        "switch $themegen_variant"
        "case light"
      ]
      ++ mkAnsiLines "light"
      ++ [ "case '*'" ]
      ++ mkAnsiLines "dark"
      ++ [ "end" ]
    )
  );
in
{
  generated = [
    (theme.mkRenderedFile {
      template = terminalSequences;
      output = "fish/conf.d/themegen-terminal-sequences.fish";
    })
  ];

  homeFiles = [
    (theme.mkHomeFile {
      target = ".config/fish/conf.d/themegen-terminal-sequences.fish";
      source = "fish/conf.d/themegen-terminal-sequences.fish";
    })
  ];
}
