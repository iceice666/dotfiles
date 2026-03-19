{ dotfiles, ... }:

{
  sops = {
    defaultSopsFormat = "yaml";

    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false;
    };

    secrets = {
      "forgejo-db-password" = {
        sopsFile = dotfiles + /secrets/hosts/server/forgejo.yaml;
        key = "dbPassword";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
      };

      "forgejo-secret-key" = {
        sopsFile = dotfiles + /secrets/hosts/server/forgejo.yaml;
        key = "secretKey";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
      };

      "forgejo-internal-token" = {
        sopsFile = dotfiles + /secrets/hosts/server/forgejo.yaml;
        key = "internalToken";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
      };

      "forgejo-oauth2-jwt-secret" = {
        sopsFile = dotfiles + /secrets/hosts/server/forgejo.yaml;
        key = "oauth2JwtSecret";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
      };

      "forgejo-lfs-jwt-secret" = {
        sopsFile = dotfiles + /secrets/hosts/server/forgejo.yaml;
        key = "lfsJwtSecret";
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
      };

      "cloudflare-ddns-key" = {
        sopsFile = dotfiles + /secrets/hosts/server/cloudflare-ddns.key;
        format = "binary";
        owner = "root";
        group = "root";
        mode = "0400";
      };

      "cloudflared-token" = {
        sopsFile = dotfiles + /secrets/hosts/server/cloudflared-token.key;
        format = "binary";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };
}
