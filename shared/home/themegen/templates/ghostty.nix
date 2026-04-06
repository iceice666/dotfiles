{ lib, pkgs }:

let
  t = import ./lib.nix { inherit lib; };

  mkGhostty =
    mode:
    let
      terminal = t.terminal mode;

      paletteLines = builtins.genList (
        index: "palette = ${toString index}=${builtins.elemAt terminal.ansi16 index}"
      ) 16;
    in
    pkgs.writeText "themegen-ghostty-${mode}" (
      t.concatLines (
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
  dark = mkGhostty "dark";
  light = mkGhostty "light";
}
