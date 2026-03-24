{ config, pkgs, ... }:
{
  services.woodpecker-server = {
    enable = true;
    package = pkgs.woodpecker-server-unstable;

    environment = {
      WOODPECKER_HOST = "https://ci.justaslime.dev";
      WOODPECKER_SERVER_ADDR = "127.0.0.1:8000";
      WOODPECKER_GRPC_ADDR = "127.0.0.1:9000";

      WOODPECKER_OPEN = "false";
      WOODPECKER_ADMIN = "justaslime";

      WOODPECKER_FORGEJO = "true";
      WOODPECKER_FORGEJO_URL = "https://code.justaslime.dev";
    };

    environmentFile = [ config.sops.templates."woodpecker-server.env".path ];
  };

  services.woodpecker-agents.agents.docker = {
    enable = true;
    package = pkgs.woodpecker-agent-unstable;

    environment = {
      WOODPECKER_SERVER = "127.0.0.1:9000";
      WOODPECKER_BACKEND = "docker";
      WOODPECKER_HEALTHCHECK_ADDR = "127.0.0.1:3001";
    };

    extraGroups = [ "docker" ];

    environmentFile = [ config.sops.templates."woodpecker-agent.env".path ];
  };
}
