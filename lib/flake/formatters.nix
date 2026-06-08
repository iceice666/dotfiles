{
  self,
  treefmt-nix,
  unstablePkgsFor,
  systems,
}:

let
  treefmtEval = system: treefmt-nix.lib.evalModule (unstablePkgsFor system) (self + /treefmt.nix);
in
builtins.listToAttrs (
  map (system: {
    name = system;
    value = (treefmtEval system).config.build.wrapper;
  }) systems
)
