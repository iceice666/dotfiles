{ config, unstablePkgs, ... }:

let
  caBundle = config.environment.etc."ssl/certs/ca-certificates.crt".source;
  registryCa = config.environment.etc."docker/certs.d/code.justaslime.dev/ca.crt".source;
in
{
  services.woodpecker-server = {
    enable = true;
    package = unstablePkgs.woodpecker-server;

    environment = {
      WOODPECKER_HOST = "https://ci.justaslime.dev";
      WOODPECKER_SERVER_ADDR = "127.0.0.1:8000";
      WOODPECKER_GRPC_ADDR = "127.0.0.1:9000";

      WOODPECKER_OPEN = "false";
      WOODPECKER_ADMIN = "justaslime";
      WOODPECKER_PLUGINS_PRIVILEGED = "woodpeckerci/plugin-docker-buildx";

      WOODPECKER_FORGEJO = "true";
      WOODPECKER_FORGEJO_URL = "https://code.justaslime.dev";
    };

    environmentFile = [ config.sops.templates."woodpecker-server.env".path ];
  };

  services.woodpecker-agents.agents.docker = {
    enable = true;
    package = unstablePkgs.woodpecker-agent;

    environment = {
      WOODPECKER_SERVER = "127.0.0.1:9000";
      WOODPECKER_BACKEND = "docker";
      WOODPECKER_BACKEND_DOCKER_VOLUMES = "${caBundle}:/etc/ssl/certs/ca-certificates.crt:ro,${registryCa}:/etc/docker/certs.d/code.justaslime.dev/ca.crt:ro";
      WOODPECKER_HEALTHCHECK_ADDR = "127.0.0.1:3001";
    };

    extraGroups = [ "docker" ];

    environmentFile = [ config.sops.templates."woodpecker-agent.env".path ];
  };
}
