{
  config,
  dotfiles,
  homolab,
  inputs,
  pkgs,
  ...
}:

let
  tempestmiku = inputs.tempestmiku;
  tempestmikuPackages = tempestmiku.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ tempestmiku.nixosModules.m4Worker ];

  sops.secrets.tempestmiku-worker-signing-key = {
    sopsFile = dotfiles + /sensitive/shared/tempestmiku-worker.key;
    format = "binary";
    mode = "0400";
    owner = "root";
    group = "root";
  };

  services.tempestmikuM4Worker = {
    enable = true;
    package = tempestmikuPackages.tmWorker;
    isolationRuntime = tempestmikuPackages.m4IsolationRuntime;
    signingKeyFile = config.sops.secrets.tempestmiku-worker-signing-key.path;
    listenAddress = "${homolab.network.tailnet.address}:${toString homolab.ports.tempestmikuWorker}";
    workerId = "homolab-m4";
  };
}
