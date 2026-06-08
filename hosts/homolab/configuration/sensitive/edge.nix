{
  config,
  dotfiles,
  homolab,
  ...
}:

{
  sops = {
    secrets = {
      "cloudflare-ddns-key" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/cloudflare-ddns.key;
        format = "binary";
        owner = "root";
        group = "traefik";
        mode = "0440";
        restartUnits = [
          "cloudflare-dyndns.service"
          "traefik.service"
        ];
      };

      "authelia-jwt-secret" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/authelia.yaml;
        key = "jwtSecret";
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
        restartUnits = [ "authelia-main.service" ];
      };

      "authelia-storage-encryption-key" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/authelia.yaml;
        key = "storageEncryptionKey";
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
        restartUnits = [ "authelia-main.service" ];
      };

      "authelia-user-password-hash" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/authelia.yaml;
        key = "userPasswordHash";
        owner = "root";
        group = "root";
        mode = "0400";
      };

      "authelia-smtp-password" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/resend.yaml;
        key = "apiKey";
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
        restartUnits = [ "authelia-main.service" ];
      };

      "grafana-secret-key" = {
        sopsFile = dotfiles + /sensitive/hosts/homolab/grafana.yaml;
        key = "secretKey";
        owner = "grafana";
        group = "grafana";
        mode = "0400";
        restartUnits = [ "grafana.service" ];
      };

    };

    templates = {
      "authelia-users-database.yml" = {
        content = ''
          users:
            iceice666:
              disabled: false
              displayname: iceice666
              password: ${config.sops.placeholder."authelia-user-password-hash"}
              email: ${homolab.contact.adminEmail}
              groups:
                - admins
        '';
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };

    };
  };
}
