{ inputs, dotfiles }:

let
  hostsDir = dotfiles + /hosts;
  entries = builtins.readDir hostsDir;
  hostNames = builtins.filter (
    n: entries.${n} == "directory" && builtins.pathExists (hostsDir + "/${n}/host.nix")
  ) (builtins.attrNames entries);
in
map (name: import (hostsDir + "/${name}/host.nix") { inherit inputs dotfiles name; }) hostNames
