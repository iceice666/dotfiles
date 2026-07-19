{
  inputs,
  pkgs,
  ...
}:

let
  tempestmiku = inputs.tempestmiku;
  tempestmikuPackages = tempestmiku.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ tempestmiku.nixosModules.m4Production ];

  services.tempestmikuM4 = {
    enable = true;
    package = tempestmikuPackages.tmServer;
    isolationRuntime = tempestmikuPackages.m4IsolationRuntime;
  };
}
