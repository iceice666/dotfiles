{
  inputs,
  hostConfigurations,
  hosts,
}:

let
  deployableHosts = builtins.filter (host: host.deploy.enable or false) hosts;

  deployNode =
    host:
    let
      deploy = host.deploy;
      profileName = if host.kind == "home-manager" then "home" else "system";
      activation =
        if host.kind == "nixos" then
          inputs.deploy-rs.lib.${host.system}.activate.nixos hostConfigurations.${host.name}
        else if host.kind == "home-manager" then
          inputs.deploy-rs.lib.${host.system}.activate.home-manager hostConfigurations.${host.name}
        else
          throw "deploy-rs does not support host kind ${host.kind}";
    in
    {
      name = host.name;
      value =
        builtins.removeAttrs deploy [
          "enable"
          "profileUser"
        ]
        // {
          profiles.${profileName} = {
            user = deploy.profileUser or "root";
            path = activation;
          };
        };
    };
in
{
  nodes = builtins.listToAttrs (map deployNode deployableHosts);
}
