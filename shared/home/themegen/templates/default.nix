{ lib, pkgs }:

let
  ghostty = import ./ghostty.nix { inherit lib pkgs; };
in
{
  ghosttyDark = ghostty.dark;
  ghosttyLight = ghostty.light;
  opencodeColors = import ./opencode.nix { inherit lib pkgs; };
  starship = import ./starship.nix { inherit lib pkgs; };
  terminalSequences = import ./terminal-sequences.nix { inherit lib pkgs; };
  zedThemes = import ./zed.nix { inherit lib pkgs; };
}
