{
  config,
  dotfiles,
  ...
}:
{
  sops = {
    defaultSopsFormat = "yaml";

    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false;
    };

    secrets = {
      "forgejo-db-password" = {
        sopsFile = dotfiles + /sensitive/hosts/server/forgejo.yaml;
        key = "dbPassword";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
        restartUnits = [ "forgejo.service" ];
      };

      "forgejo-secret-key" = {
        sopsFile = dotfiles + /sensitive/hosts/server/forgejo.yaml;
        key = "secretKey";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
        restartUnits = [ "forgejo.service" ];
      };

      "forgejo-internal-token" = {
        sopsFile = dotfiles + /sensitive/hosts/server/forgejo.yaml;
        key = "internalToken";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
        restartUnits = [ "forgejo.service" ];
      };

      "forgejo-oauth2-jwt-secret" = {
        sopsFile = dotfiles + /sensitive/hosts/server/forgejo.yaml;
        key = "oauth2JwtSecret";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
        restartUnits = [ "forgejo.service" ];
      };

      "forgejo-lfs-jwt-secret" = {
        sopsFile = dotfiles + /sensitive/hosts/server/forgejo.yaml;
        key = "lfsJwtSecret";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
        restartUnits = [ "forgejo.service" ];
      };

      "forgejo-mailer-password" = {
        sopsFile = dotfiles + /sensitive/hosts/server/resend.yaml;
        key = "apiKey";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
        restartUnits = [ "forgejo.service" ];
      };

      "rustfs-access-key" = {
        sopsFile = dotfiles + /sensitive/hosts/server/rustfs.yaml;
        key = "accessKey";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
        restartUnits = [
          "forgejo.service"
          "rustfs.service"
          "rustfs-init.service"
        ];
      };

      "rustfs-secret-key" = {
        sopsFile = dotfiles + /sensitive/hosts/server/rustfs.yaml;
        key = "secretKey";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
        restartUnits = [
          "forgejo.service"
          "rustfs.service"
          "rustfs-init.service"
        ];
      };

      "woodpecker-grpc-secret" = {
        sopsFile = dotfiles + /sensitive/hosts/server/woodpecker.yaml;
        key = "woodpeckerGrpcSecret";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [
          "woodpecker-server.service"
          "woodpecker-agent-docker.service"
        ];
      };

      "woodpecker-forgejo-client" = {
        sopsFile = dotfiles + /sensitive/hosts/server/woodpecker.yaml;
        key = "woodpeckerForgejoClient";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "woodpecker-server.service" ];
      };

      "woodpecker-forgejo-secret" = {
        sopsFile = dotfiles + /sensitive/hosts/server/woodpecker.yaml;
        key = "woodpeckerForgejoSecret";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "woodpecker-server.service" ];
      };

      "cloudflare-ddns-key" = {
        sopsFile = dotfiles + /sensitive/hosts/server/cloudflare-ddns.key;
        format = "binary";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "cloudflare-dyndns.service" ];
      };

      "cloudflared-token" = {
        sopsFile = dotfiles + /sensitive/hosts/server/cloudflared-token.key;
        format = "binary";
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "cloudflared-tunnel.service" ];
      };

      "cloudflare-origin-ca-key" = {
        sopsFile = dotfiles + /sensitive/hosts/server/cloudflare-origin-ca/key.pem;
        format = "binary";
        owner = "traefik";
        group = "traefik";
        mode = "0400";
        restartUnits = [ "traefik.service" ];
      };

      "authelia-jwt-secret" = {
        sopsFile = dotfiles + /sensitive/hosts/server/authelia.yaml;
        key = "jwtSecret";
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
        restartUnits = [ "authelia-main.service" ];
      };

      "authelia-storage-encryption-key" = {
        sopsFile = dotfiles + /sensitive/hosts/server/authelia.yaml;
        key = "storageEncryptionKey";
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
        restartUnits = [ "authelia-main.service" ];
      };

      "authelia-user-password-hash" = {
        sopsFile = dotfiles + /sensitive/hosts/server/authelia.yaml;
        key = "userPasswordHash";
        owner = "root";
        group = "root";
        mode = "0400";
      };

      "authelia-smtp-password" = {
        sopsFile = dotfiles + /sensitive/hosts/server/resend.yaml;
        key = "apiKey";
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
        restartUnits = [ "authelia-main.service" ];
      };
    };

    templates = {
      "woodpecker-server.env" = {
        content = ''
          WOODPECKER_AGENT_SECRET="${config.sops.placeholder."woodpecker-grpc-secret"}"
          WOODPECKER_GRPC_SECRET="${config.sops.placeholder."woodpecker-grpc-secret"}"
          WOODPECKER_FORGEJO_CLIENT="${config.sops.placeholder."woodpecker-forgejo-client"}"
          WOODPECKER_FORGEJO_SECRET="${config.sops.placeholder."woodpecker-forgejo-secret"}"
        '';
        owner = "root";
        group = "root";
        mode = "0400";
      };

      "woodpecker-agent.env" = {
        content = ''
          WOODPECKER_AGENT_SECRET="${config.sops.placeholder."woodpecker-grpc-secret"}"
        '';
        owner = "root";
        group = "root";
        mode = "0400";
      };

      "rustfs.env" = {
        content = ''
          RUSTFS_ACCESS_KEY=${config.sops.placeholder."rustfs-access-key"}
          RUSTFS_SECRET_KEY=${config.sops.placeholder."rustfs-secret-key"}
        '';
        owner = "root";
        group = "root";
        mode = "0400";
      };

      "authelia-users-database.yml" = {
        content = ''
          users:
            iceice666:
              disabled: false
              displayname: iceice666
              password: ${config.sops.placeholder."authelia-user-password-hash"}
              email: iceice666@justaslime.dev
              groups:
                - admins
        '';
        owner = "authelia-main";
        group = "authelia-main";
        mode = "0400";
      };
    };
  };

  security.pki.certificateFiles = [
    (dotfiles + /sensitive/hosts/server/cloudflare-origin-ca/root-rsa-cert.pem)
  ];
}
