{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  forgejoDataDir = "/var/lib/forgejo";
  forgejoImage = "codeberg.org/forgejo/forgejo:15.0.7";
  forgejoPort = homolab.ports.forgejo;
  forgejoSshPort = homolab.ports.forgejoSsh;
  forgejoAdminPasswordPath = config.sops.secrets.forgejo-admin-password.path;
  githubOauthClientIdPath = config.sops.secrets.forgejo-github-oauth-client-id.path;
  githubOauthClientSecretPath = config.sops.secrets.forgejo-github-oauth-client-secret.path;

  woodpeckerDataDir = "/var/lib/woodpecker";
  woodpeckerServerImage = "docker.io/woodpeckerci/woodpecker-server:v3.18.0";
  woodpeckerAgentImage = "docker.io/woodpeckerci/woodpecker-agent:v3.18.0";
  woodpeckerPort = homolab.ports.woodpecker;
  woodpeckerGrpcPort = homolab.ports.woodpeckerGrpc;
  woodpeckerAgentHealthPort = homolab.ports.woodpeckerAgentHealth;
  woodpeckerAgentSecretPath = config.sops.secrets.woodpecker-agent-secret.path;
  woodpeckerOauthClientPath = "${woodpeckerDataDir}/forgejo-oauth-client";
  woodpeckerServerEnvPath = "${woodpeckerDataDir}/server.env";
  woodpeckerAgentEnvPath = "${woodpeckerDataDir}/agent.env";
  woodpeckerOauthSecretPath = "${woodpeckerDataDir}/forgejo-oauth-secret";

  adminUsername = "iceice666";

  forgejoEnv = pkgs.writeText "lumo-forgejo.env" ''
    USER_UID=1000
    USER_GID=1000
    FORGEJO____APP_NAME=Just a Slime Forge
    FORGEJO____RUN_MODE=prod
    FORGEJO__server__DOMAIN=${homolab.domains.forgejo}
    FORGEJO__server__ROOT_URL=${homolab.urls.forgejo}/
    FORGEJO__server__HTTP_ADDR=127.0.0.1
    FORGEJO__server__HTTP_PORT=${toString forgejoPort}
    FORGEJO__server__OFFLINE_MODE=true
    FORGEJO__server__LFS_START_SERVER=true
    FORGEJO__server__START_SSH_SERVER=true
    FORGEJO__server__SSH_DOMAIN=${homolab.domains.forgejo}
    FORGEJO__server__SSH_PORT=${toString forgejoSshPort}
    FORGEJO__server__SSH_LISTEN_HOST=0.0.0.0
    FORGEJO__server__SSH_LISTEN_PORT=${toString forgejoSshPort}
    FORGEJO__database__DB_TYPE=sqlite3
    FORGEJO__database__PATH=/data/forgejo.db
    FORGEJO__repository__DEFAULT_PRIVATE=private
    FORGEJO__service__DISABLE_REGISTRATION=false
    FORGEJO__service__ALLOW_ONLY_EXTERNAL_REGISTRATION=true
    FORGEJO__service__SHOW_REGISTRATION_BUTTON=false
    FORGEJO__security__INSTALL_LOCK=true
    FORGEJO__webhook__ALLOWED_HOST_LIST=external,loopback,${homolab.domains.woodpecker}
  '';

  forgejoService = pkgs.writeText "lumo-forgejo" ''
    #!/sbin/openrc-run
    name="lumo-forgejo"
    description="Lumo Forgejo software forge"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-forgejo --network=host --env-file=${forgejoEnv} -v ${forgejoDataDir}:/data ${forgejoImage}"
    command_user="root"
    output_log="/var/log/lumo/forgejo.log"
    error_log="/var/log/lumo/forgejo.log"
    respawn_delay=10
    respawn_max=0

    depend() {
      need lumo-podman
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/forgejo.log
      checkpath -d -m 0750 ${forgejoDataDir}
      if ! ${pkgs.podman}/bin/podman image exists ${forgejoImage}; then
        ${pkgs.podman}/bin/podman pull ${forgejoImage} >&2
      fi
    }
  '';

  forgejoBootstrap = pkgs.writeShellScript "lumo-forgejo-bootstrap" ''
    set -eu

    forgejo_url="http://127.0.0.1:${toString forgejoPort}"
    for attempt in $(${pkgs.coreutils}/bin/seq 1 60); do
      if ${pkgs.curl}/bin/curl --fail --silent --show-error "$forgejo_url/api/healthz" >/dev/null 2>&1; then
        break
      fi
      if [ "$attempt" -eq 60 ]; then
        echo "Forgejo did not become ready" >&2
        exit 1
      fi
      ${pkgs.coreutils}/bin/sleep 2
    done

    admin_password="$(cat '${forgejoAdminPasswordPath}')"
    if ${pkgs.podman}/bin/podman exec --user git lumo-forgejo forgejo --work-path /data/gitea --config /data/gitea/conf/app.ini admin user list |
      ${pkgs.gnugrep}/bin/grep -Eq '(^|[[:space:]])${adminUsername}([[:space:]]|$)'; then
      ${pkgs.podman}/bin/podman exec --user git lumo-forgejo \
        forgejo --work-path /data/gitea --config /data/gitea/conf/app.ini admin user change-password \
        --username '${adminUsername}' \
        --password "$admin_password" \
        --must-change-password=false
    else
      ${pkgs.podman}/bin/podman exec --user git lumo-forgejo \
        forgejo --work-path /data/gitea --config /data/gitea/conf/app.ini admin user create \
        --username '${adminUsername}' \
        --password "$admin_password" \
        --email '${homolab.contact.adminEmail}' \
        --admin \
        --must-change-password=false
    fi

    github_client_id="$(cat '${githubOauthClientIdPath}')"
    github_client_secret="$(cat '${githubOauthClientSecretPath}')"
    github_auth_id="$(${pkgs.podman}/bin/podman exec --user git lumo-forgejo \
      forgejo --work-path /data/gitea --config /data/gitea/conf/app.ini admin auth list |
      ${pkgs.gnugrep}/bin/grep -Fi "$(printf '\t')github$(printf '\t')OAuth2$(printf '\t')" |
      ${pkgs.coreutils}/bin/cut -f1)"

    if [ -n "$github_auth_id" ]; then
      github_auth_command="update-oauth"
      set -- --id "$github_auth_id"
    else
      github_auth_command="add-oauth"
      set --
    fi

    ${pkgs.podman}/bin/podman exec --user git lumo-forgejo \
      forgejo --work-path /data/gitea --config /data/gitea/conf/app.ini admin auth "$github_auth_command" \
      "$@" \
      --name github \
      --provider github \
      --key "$github_client_id" \
      --secret "$github_client_secret" \
      --scopes user:email

    oauth_valid=false
    if [ -s '${woodpeckerOauthClientPath}' ] && [ -s '${woodpeckerOauthSecretPath}' ]; then
      oauth_client="$(cat '${woodpeckerOauthClientPath}')"
      applications="$(${pkgs.curl}/bin/curl --fail --silent --show-error \
        --user '${adminUsername}':"$admin_password" \
        "$forgejo_url/api/v1/user/applications/oauth2")"
      if printf '%s' "$applications" | ${pkgs.jq}/bin/jq -e \
        --arg client "$oauth_client" 'any(.[]; .client_id == $client)' >/dev/null; then
        oauth_valid=true
      fi
    fi

    if [ "$oauth_valid" != true ]; then
      payload="$(${pkgs.jq}/bin/jq -nc \
        --arg name 'Woodpecker CI' \
        --arg redirect '${homolab.urls.woodpecker}/authorize' \
        '{name: $name, redirect_uris: [$redirect], confidential_client: true}')"
      application="$(${pkgs.curl}/bin/curl --fail --silent --show-error \
        --user '${adminUsername}':"$admin_password" \
        --header 'Content-Type: application/json' \
        --data "$payload" \
        "$forgejo_url/api/v1/user/applications/oauth2")"
      oauth_client="$(printf '%s' "$application" | ${pkgs.jq}/bin/jq -er '.client_id')"
      oauth_secret="$(printf '%s' "$application" | ${pkgs.jq}/bin/jq -er '.client_secret')"
      umask 077
      printf '%s\n' "$oauth_client" > '${woodpeckerOauthClientPath}'
      printf '%s\n' "$oauth_secret" > '${woodpeckerOauthSecretPath}'
    fi
  '';

  forgejoBootstrapService = pkgs.writeText "lumo-forgejo-bootstrap" ''
    #!/sbin/openrc-run
    name="lumo-forgejo-bootstrap"
    description="Provision the Lumo Forgejo admin, GitHub login, and Woodpecker OAuth client"

    depend() {
      need lumo-forgejo
      after networking
    }

    start() {
      ebegin "Provisioning Forgejo"
      ${forgejoBootstrap}
      eend $?
    }
  '';

  woodpeckerServerService = pkgs.writeText "lumo-woodpecker-server" ''
    #!/sbin/openrc-run
    name="lumo-woodpecker-server"
    description="Lumo Woodpecker CI server"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-woodpecker-server --network=host --env-file=${woodpeckerServerEnvPath} -v ${woodpeckerDataDir}/server:/var/lib/woodpecker ${woodpeckerServerImage}"
    command_user="root"
    output_log="/var/log/lumo/woodpecker-server.log"
    error_log="/var/log/lumo/woodpecker-server.log"
    respawn_delay=10
    respawn_max=0

    depend() {
      need lumo-podman lumo-forgejo-bootstrap
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/woodpecker-server.log
      checkpath -d -m 0700 -o 1000:1000 ${woodpeckerDataDir}/server
      if ! ${pkgs.podman}/bin/podman image exists ${woodpeckerServerImage}; then
        ${pkgs.podman}/bin/podman pull ${woodpeckerServerImage} >&2
      fi
    }
  '';

  woodpeckerAgentService = pkgs.writeText "lumo-woodpecker-agent" ''
    #!/sbin/openrc-run
    name="lumo-woodpecker-agent"
    description="Lumo Woodpecker CI Podman agent"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-woodpecker-agent --network=host --env-file=${woodpeckerAgentEnvPath} -v ${woodpeckerDataDir}/agent:/etc/woodpecker -v /run/podman/podman.sock:/var/run/docker.sock ${woodpeckerAgentImage} agent"
    command_user="root"
    output_log="/var/log/lumo/woodpecker-agent.log"
    error_log="/var/log/lumo/woodpecker-agent.log"
    respawn_delay=10
    respawn_max=0

    depend() {
      need lumo-podman lumo-woodpecker-server
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/woodpecker-agent.log
      checkpath -d -m 0700 -o 1000:1000 ${woodpeckerDataDir}/agent
      if [ -f ${woodpeckerDataDir}/agent/agent.conf ]; then
        chown 1000:1000 ${woodpeckerDataDir}/agent/agent.conf
        chmod 0600 ${woodpeckerDataDir}/agent/agent.conf
      fi
      if ! ${pkgs.podman}/bin/podman image exists ${woodpeckerAgentImage}; then
        ${pkgs.podman}/bin/podman pull ${woodpeckerAgentImage} >&2
      fi
    }
  '';
in
{
  home.packages = [ pkgs.podman ];

  sops.secrets = {
    forgejo-admin-password = {
      sopsFile = dotfiles + /sensitive/hosts/lumo/forgejo-woodpecker.yaml;
      key = "forgejoAdminPassword";
      mode = "0400";
    };
    forgejo-github-oauth-client-id = {
      sopsFile = dotfiles + /sensitive/hosts/lumo/forgejo-woodpecker.yaml;
      key = "githubOauthClientId";
      mode = "0400";
    };
    forgejo-github-oauth-client-secret = {
      sopsFile = dotfiles + /sensitive/hosts/lumo/forgejo-woodpecker.yaml;
      key = "githubOauthClientSecret";
      mode = "0400";
    };
    woodpecker-agent-secret = {
      sopsFile = dotfiles + /sensitive/hosts/lumo/forgejo-woodpecker.yaml;
      key = "woodpeckerAgentSecret";
      mode = "0400";
    };
  };

  home.activation.lumoForgejoWoodpecker =
    lib.hm.dag.entryAfter [ "lumoDirectories" "sopsAlpine" "lumoPodman" ]
      ''
        install -d -m 0755 /var/log/lumo
        install -d -m 0750 -o 1000 -g 1000 ${forgejoDataDir}
        install -d -m 0700 -o root -g root ${woodpeckerDataDir}
        install -d -m 0700 -o 1000 -g 1000 \
          ${woodpeckerDataDir}/server \
          ${woodpeckerDataDir}/agent
        agent_secret="$(cat '${woodpeckerAgentSecretPath}')"
        {
          printf 'WOODPECKER_HOST=${homolab.urls.woodpecker}\n'
          printf 'WOODPECKER_SERVER_ADDR=127.0.0.1:${toString woodpeckerPort}\n'
          printf 'WOODPECKER_GRPC_ADDR=127.0.0.1:${toString woodpeckerGrpcPort}\n'
          printf 'WOODPECKER_FORGEJO=true\n'
          printf 'WOODPECKER_FORGEJO_URL=${homolab.urls.forgejo}\n'
          printf 'WOODPECKER_FORGEJO_CLIENT=%s\n' "$(cat '${woodpeckerOauthClientPath}')"
          printf 'WOODPECKER_FORGEJO_SECRET=%s\n' "$(cat '${woodpeckerOauthSecretPath}')"
          printf 'WOODPECKER_AGENT_SECRET=%s\n' "$agent_secret"
          printf 'WOODPECKER_OPEN=true\n'
          printf 'WOODPECKER_ADMIN=${adminUsername}\n'
        } > ${woodpeckerServerEnvPath}
        {
          printf 'WOODPECKER_SERVER=127.0.0.1:${toString woodpeckerGrpcPort}\n'
          printf 'WOODPECKER_AGENT_SECRET=%s\n' "$agent_secret"
          printf 'WOODPECKER_AGENT_CONFIG_FILE=/etc/woodpecker/agent.conf\n'
          printf 'WOODPECKER_BACKEND=docker\n'
          printf 'WOODPECKER_HOSTNAME=lumo\n'
          printf 'WOODPECKER_MAX_WORKFLOWS=1\n'
          printf 'WOODPECKER_HEALTHCHECK_ADDR=127.0.0.1:${toString woodpeckerAgentHealthPort}\n'
          printf 'DOCKER_HOST=unix:///var/run/docker.sock\n'
        } > ${woodpeckerAgentEnvPath}
        chmod 0400 ${woodpeckerServerEnvPath} ${woodpeckerAgentEnvPath}


        install -Dm755 ${forgejoService} /etc/init.d/lumo-forgejo
        install -Dm755 ${forgejoBootstrapService} /etc/init.d/lumo-forgejo-bootstrap
        install -Dm755 ${woodpeckerServerService} /etc/init.d/lumo-woodpecker-server
        install -Dm755 ${woodpeckerAgentService} /etc/init.d/lumo-woodpecker-agent

        /sbin/rc-update add lumo-forgejo default
        /sbin/rc-update add lumo-forgejo-bootstrap default
        /sbin/rc-update add lumo-woodpecker-server default
        /sbin/rc-update add lumo-woodpecker-agent default

        restart_service() {
          service="$1"
          if ! /sbin/rc-service "$service" restart; then
            sleep 5
            /sbin/rc-service "$service" restart
          fi
        }

        restart_service lumo-forgejo
        restart_service lumo-forgejo-bootstrap
        restart_service lumo-woodpecker-server
        restart_service lumo-woodpecker-agent
      '';
}
