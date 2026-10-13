{ name, ... }:

{
  inherit name;
  kind = "nixos";
  system = "x86_64-linux";
  username = "nixos";
  homeDirectory = "/home/nixos";
  modules = [ ./configuration.nix ];
  features = { };
}
