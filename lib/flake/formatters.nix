{
  self,
  treefmt-nix,
  unstablePkgsFor,
}:

let
  systems = [
    "aarch64-darwin"
    "x86_64-linux"
  ];

  treefmtEval = system: treefmt-nix.lib.evalModule (unstablePkgsFor system) (self + /treefmt.nix);
in
builtins.listToAttrs (
  map (system: {
    name = system;
    value = (treefmtEval system).config.build.wrapper;
  }) systems
)
