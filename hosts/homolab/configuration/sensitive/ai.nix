{
  config,
  dotfiles,
  ...
}:

{
  sops = {
    secrets = {
      # valkey-requirepass moved to lumo's root Home Manager service configuration.

      "omniroute-jwt-secret" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/omniroute.yaml;
        key = "jwtSecret";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "omniroute.service" ];
      };

      "omniroute-api-key-secret" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/omniroute.yaml;
        key = "apiKeySecret";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "omniroute.service" ];
      };

      "omniroute-initial-password" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/omniroute.yaml;
        key = "initialPassword";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "omniroute.service" ];
      };

      "omniroute-storage-encryption-key" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/omniroute.yaml;
        key = "storageEncryptionKey";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "omniroute.service" ];
      };

      "omniroute-machine-id-salt" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/omniroute.yaml;
        key = "machineIdSalt";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "omniroute.service" ];
      };
    };

    templates = {
      "omniroute.env" = {
        content = ''
          JWT_SECRET=${config.sops.placeholder."omniroute-jwt-secret"}
          API_KEY_SECRET=${config.sops.placeholder."omniroute-api-key-secret"}
          INITIAL_PASSWORD=${config.sops.placeholder."omniroute-initial-password"}
          STORAGE_ENCRYPTION_KEY=${config.sops.placeholder."omniroute-storage-encryption-key"}
          MACHINE_ID_SALT=${config.sops.placeholder."omniroute-machine-id-salt"}
        '';
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };
}
