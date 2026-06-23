{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  # Agent config + internal state (HERMES_HOME): config.yaml, .env, sessions,
  # skills, memories, kanban, etc. Mounted to the container's /opt/data.
  dataDir = "/var/lib/hermes";

  # Agent working directory (terminal.cwd): where the agent runs shell commands
  # and creates files during tasks. Bind-mounted at the same path so the host
  # sees exactly what the agent works on.
  workDir = "/home/hermes";

  # The `latest` tag tracks the main branch (auto-updated on every push to
  # main). To pin a specific release, change to a tag like `vX.Y.Z` when
  # available on Docker Hub.
  image = "docker.io/nousresearch/hermes-agent:latest";

  # LLM traffic goes through the lumo cliproxyapi service on the same host,
  # which already routes to the configured upstream providers.
  cliproxyapiBaseUrl = "http://127.0.0.1:${toString homolab.ports.cliproxyapi}/v1";
  honchoBaseUrl = "http://127.0.0.1:${toString homolab.ports.honcho}";

  honchoConfig = pkgs.writeText "hermes-honcho.json" (
    builtins.toJSON {
      baseUrl = honchoBaseUrl;
      workspace = "tempest-miku";
      peerName = "brian";
      hosts.hermes = {
        enabled = true;
        aiPeer = "tempest-miku";
        workspace = "tempest-miku";
        peerName = "brian";
        recallMode = "hybrid";
        writeFrequency = "async";
        sessionStrategy = "per-session";
        pinUserPeer = true;
        contextTokens = 1600;
        contextCadence = 1;
        dialecticCadence = 3;
        dialecticDepth = 2;
        dialecticReasoningLevel = "low";
        reasoningLevelCap = "high";
        dialecticMaxChars = 800;
        saveMessages = true;
        observationMode = "directional";
      };
    }
  );

  containerEntrypoint = pkgs.writeText "hermes-honcho-entrypoint" ''
    #!/bin/sh
    set -eu

    if ! /opt/hermes/.venv/bin/python -c "import honcho" >/dev/null 2>&1; then
      restore_perms() { chmod -R a-w /opt/hermes/.venv; }
      trap restore_perms EXIT
      chmod -R u+w /opt/hermes/.venv
      /usr/local/bin/uv pip install --python /opt/hermes/.venv/bin/python honcho-ai==2.0.1
      trap - EXIT
      restore_perms
    fi

    exec /init /opt/hermes/docker/main-wrapper.sh gateway run
  '';

  sharedApiKeyPath = config.sops.secrets.cliproxyapi-shared-api-key.path;
  exaApiKeyPath = config.sops.secrets.exa-api-key.path;
  # User-editable agent secrets as a sops dotenv file: TELEGRAM_BOT_TOKEN,
  # TELEGRAM_ALLOWED_USERS, TELEGRAM_HOME_CHANNEL, and any extra env vars.
  # Edit with: just secret-edit sensitive/hosts/lumo/hermes-agent.env
  hermesEnvPath = config.sops.secrets.hermes-env.path;

  # Durable agent identity (SOUL.md), installed into HERMES_HOME. Hermes reads
  # it as slot #1 of the system prompt and never rewrites it, so the repo file
  # is the source of truth: edit hermes-soul.md and redeploy to change persona.
  soulFile = ./hermes-soul.md;

  openrcService = pkgs.writeText "lumo-hermes-agent" ''
    #!/sbin/openrc-run
    name="lumo-hermes-agent"
    description="Lumo Hermes Agent (Nous Research) gateway container"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --network=host --env=HERMES_HOME=/opt/data --env=HERMES_DISABLE_LAZY_INSTALLS=0 --entrypoint=/bin/sh --name=lumo-hermes-agent -v ${dataDir}:/opt/data -v ${workDir}:${workDir} -v ${containerEntrypoint}:/usr/local/bin/hermes-honcho-entrypoint:ro ${image} /usr/local/bin/hermes-honcho-entrypoint"
    command_user="root"
    output_log="/var/log/lumo/hermes-agent.log"
    error_log="/var/log/lumo/hermes-agent.log"
    respawn_delay=10
    respawn_max=0

    depend() {
      need lumo-podman lumo-cliproxyapi lumo-honcho-api
      after networking
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/hermes-agent.log
      # Only pull when the image is missing. The ~3.85 GB image is re-copied
      # on every pull, so unconditional pulls would stall each service restart
      # (including the cascade triggered during a Home Manager activation).
      if ! ${pkgs.podman}/bin/podman image exists ${image}; then
        ${pkgs.podman}/bin/podman pull ${image} >&2
      fi
    }
  '';
in
{
  home.packages = [ pkgs.podman ];

  # cliproxyapi-shared-api-key and exa-api-key are also declared by
  # cliproxyapi.nix; sops-nix is idempotent on (sopsFile, key) tuples, so the
  # redeclaration is a no-op for decryption and keeps this module
  # self-contained.
  sops.secrets.cliproxyapi-shared-api-key = {
    sopsFile = dotfiles + /sensitive/shared/cliproxyapi.yaml;
    key = "apiKey";
    mode = "0400";
  };
  sops.secrets.exa-api-key = {
    sopsFile = dotfiles + /sensitive/shared/exa.yaml;
    key = "exa_api_key";
    mode = "0400";
  };
  # Whole sops dotenv file: the decrypted secret value is the full .env body
  # (sops-nix ignores `key` for dotenv format). Merged into the agent's .env
  # at activation, so the user can add or edit env vars directly.
  sops.secrets.hermes-env = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/hermes-agent.env;
    format = "dotenv";
    mode = "0400";
  };

  home.activation.lumoHermesAgent = lib.hm.dag.entryAfter [ "lumoDirectories" "sopsAlpine" ] ''
        if ! /usr/bin/getent group hermes >/dev/null; then
          /usr/sbin/addgroup -g 10000 -S hermes
        fi
        if ! /usr/bin/id hermes >/dev/null 2>&1; then
          /usr/sbin/adduser -S -D -h ${workDir} -s /bin/sh -G hermes -u 10000 hermes
        fi

        # Home directory doubles as the agent working directory (terminal.cwd),
        # bind-mounted into the container at the same path. Created by adduser for
        # new users; ensure it exists with skeleton files for existing users.
        if [ ! -d ${workDir} ]; then
          install -d -m 0750 -o hermes -g hermes ${workDir}
          cp -r /etc/skel/. ${workDir}/ 2>/dev/null || true
          chown -R hermes:hermes ${workDir}
        fi
        if [ "$(/usr/bin/getent passwd hermes | cut -d: -f6)" != "${workDir}" ]; then
          /usr/sbin/usermod -d ${workDir} hermes
        fi

        # Config + internal state directory (HERMES_HOME), mounted to /opt/data.
        install -d -m 0750 -o hermes -g hermes ${dataDir}

        # The agent reads HERMES_HOME/.env (${dataDir} -> /opt/data) at startup.
        # Compose it from derived vars, shared API keys, and the user-editable
        # sops dotenv (Telegram + any extra vars the user adds). Re-rendered on
        # every activation so updated secrets propagate on the next switch.
        {
          printf '%s\n' "HERMES_UID=10000"
          printf '%s\n' "HERMES_GID=10000"
          printf '%s\n' "OPENAI_BASE_URL=${cliproxyapiBaseUrl}"
          printf 'OPENAI_API_KEY=%s\n' "$(cat '${sharedApiKeyPath}')"
          printf 'EXA_API_KEY=%s\n' "$(cat '${exaApiKeyPath}')"
          cat '${hermesEnvPath}'
        } > ${dataDir}/.env.new
        install -m 0600 -o hermes -g hermes ${dataDir}/.env.new ${dataDir}/.env
        rm -f ${dataDir}/.env.new

        # Install the durable agent identity (HERMES_HOME/SOUL.md, slot #1 of
        # the system prompt). Hermes only reads it, so sync it from the repo on
        # every activation rather than seeding once.
        install -m 0644 -o hermes -g hermes ${soulFile} ${dataDir}/SOUL.md

        # Pave a minimal config.yaml on first activation so the agent uses
        # cliproxyapi immediately — no interactive 'hermes model' needed.
        # Guarded by a marker file; delete /var/lib/hermes/.hermes-config-seeded
        # and re-apply to regenerate the config with updated defaults.
        if [ ! -f ${dataDir}/.hermes-config-seeded ]; then

          cat > ${dataDir}/config.yaml << 'CONFIGEOF'
    model:
      provider: "custom"
      default: "gpt-5.5"
      base_url: "${cliproxyapiBaseUrl}"

    skills:
      guard_agent_created: true

    terminal:
      backend: "local"
      cwd: "/home/hermes"
      timeout: 180

    memory:
      provider: "honcho"
      memory_enabled: true
      user_profile_enabled: true
      write_approval: true

    approvals:
      mode: manual
      timeout: 60
      cron_mode: deny
      mcp_reload_confirm: true
      destructive_slash_confirm: true
    CONFIGEOF

          chown hermes:hermes ${dataDir}/config.yaml
          chmod 0600 ${dataDir}/config.yaml
          touch ${dataDir}/.hermes-config-seeded
        fi

        # Keep Honcho selected even after Hermes rewrites config.yaml. Existing
        # memory-provider subkeys are replaced deliberately: Honcho's detailed
        # state lives in honcho.json, not under config.yaml.
        if [ -f ${dataDir}/config.yaml ]; then
          /usr/bin/awk '
            BEGIN { wrote=0; skipping=0 }
            /^memory:/ {
              print "memory:"
              print "  provider: \"honcho\""
              wrote=1
              skipping=1
              next
            }
            skipping && /^[^[:space:]]/ { skipping=0 }
            skipping { next }
            { print }
            END {
              if (!wrote) {
                print ""
                print "memory:"
                print "  provider: \"honcho\""
              }
            }
          ' ${dataDir}/config.yaml > ${dataDir}/config.yaml.new
          install -m 0600 -o hermes -g hermes ${dataDir}/config.yaml.new ${dataDir}/config.yaml
          rm -f ${dataDir}/config.yaml.new
        fi

        install -m 0600 -o hermes -g hermes ${honchoConfig} ${dataDir}/honcho.json

        # The hermes "custom" provider authenticates with model.api_key from
        # config.yaml; it does not read OPENAI_API_KEY from the environment.
        # Inject the shared cliproxyapi key into the model section on every
        # activation so it survives hermes' config rewrites and key rotation.
        if [ -f ${dataDir}/config.yaml ]; then
          apikey="$(cat '${sharedApiKeyPath}')"
          /usr/bin/awk -v key="$apikey" '
            /^model:/ { print; print "  api_key: \"" key "\""; inmodel=1; next }
            inmodel && /^  api_key:/ { next }
            inmodel && /^[a-zA-Z_]/ { inmodel=0 }
            { print }
          ' ${dataDir}/config.yaml > ${dataDir}/config.yaml.new
          install -m 0600 -o hermes -g hermes ${dataDir}/config.yaml.new ${dataDir}/config.yaml
          rm -f ${dataDir}/config.yaml.new
        fi

        # nixpkgs podman on Alpine requires an explicit signature policy.
        # Without this, every `podman pull` fails with "no policy.json file found".
        # "insecureAcceptAnything" matches Docker's default — acceptable for
        # the official nousresearch/hermes-agent image pulled from Docker Hub.
        install -d -m 0755 /etc/containers
        if [ ! -f /etc/containers/policy.json ]; then
          cat > /etc/containers/policy.json << 'POLICYEOF'
    {"default":[{"type":"insecureAcceptAnything"}]}
    POLICYEOF
          chmod 0644 /etc/containers/policy.json
        fi

        install -Dm755 ${openrcService} /etc/init.d/lumo-hermes-agent
        /sbin/rc-update add lumo-hermes-agent default
        /sbin/rc-service lumo-hermes-agent restart
  '';
}
