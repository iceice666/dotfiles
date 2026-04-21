{ lib, pkgs }:

let
  theme = import ./lib.nix { inherit lib; };

  mkGhostty =
    mode:
    let
      terminal = theme.terminal mode;

      paletteLines = builtins.genList (
        index: "palette = ${toString index}=${builtins.elemAt terminal.ansi16 index}"
      ) 16;
    in
    pkgs.writeText "themegen-ghostty-${mode}" (
      theme.concatLines (
        [
          "background = ${terminal.background}"
          "foreground = ${terminal.foreground}"
          "cursor-color = ${terminal.cursor}"
          "cursor-text = ${terminal.cursorText}"
          "selection-background = ${terminal.selectionBackground}"
          "selection-foreground = ${terminal.selectionForeground}"
        ]
        ++ paletteLines
      )
    );
in
{
  generated = [
    (theme.mkRenderedFile {
      template = mkGhostty "dark";
      output = "ghostty/themes/themegen-dark";
    })
    (theme.mkRenderedFile {
      template = mkGhostty "light";
      output = "ghostty/themes/themegen-light";
    })
  ];

  homeFiles = [
    (theme.mkHomeFile {
      target = ".config/ghostty/themes/themegen-dark";
      source = "ghostty/themes/themegen-dark";
    })
    (theme.mkHomeFile {
      target = ".config/ghostty/themes/themegen-light";
      source = "ghostty/themes/themegen-light";
    })
  ];
}
