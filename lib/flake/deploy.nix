{
  inputs,
  nixosConfigurations,
  hosts,
}:

let
  deployableHosts = builtins.filter (
    host: host.kind == "nixos" && (host.deploy.enable or false)
  ) hosts;

  deployNode =
    host:
    let
      deploy = host.deploy;
    in
    {
      name = host.name;
      value =
        builtins.removeAttrs deploy [
          "enable"
          "profileUser"
        ]
        // {
          profiles.system = {
            user = deploy.profileUser or "root";
            path = inputs.deploy-rs.lib.${host.system}.activate.nixos nixosConfigurations.${host.name};
          };
        };
    };
in
{
  nodes = builtins.listToAttrs (map deployNode deployableHosts);
}
