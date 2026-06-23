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

  # Host-side working directory — bind-mounted into the container at containerWorkDir.
  # Keep it outside /home/ inside the container: hermes' write_file tool flags
  # /home/ paths as protected credential files.
  hostWorkDir = "/home/hermes";
  containerWorkDir = "/opt/workspace";

  # The `latest` tag tracks the main branch (auto-updated on every push to
  # main). To pin a specific release, change to a tag like `vX.Y.Z` when
  # available on Docker Hub.
  image = "docker.io/nousresearch/hermes-agent:latest";

  # LLM traffic goes through the lumo cliproxyapi service on the same host,
  # which already routes to the configured upstream providers.
  cliproxyapiBaseUrl = "http://127.0.0.1:${toString homolab.ports.cliproxyapi}/v1";
  honchoBaseUrl = "http://127.0.0.1:${toString homolab.ports.honcho}";

  replaceTemplate =
    source: replacements:
    let
      names = builtins.attrNames replacements;
    in
    builtins.replaceStrings (map (name: "@${name}@") names) (map (name: replacements.${name}) names) (
      builtins.readFile source
    );

  initialConfig = pkgs.writeText "hermes-config.yaml" (
    replaceTemplate ./config.yaml {
      inherit cliproxyapiBaseUrl;
    }
  );

  honchoConfig = pkgs.writeText "hermes-honcho.json" (
    replaceTemplate ./honcho.json {
      inherit honchoBaseUrl;
    }
  );

  containerEntrypoint = pkgs.writeText "hermes-honcho-entrypoint" (
    builtins.readFile ./container-entrypoint
  );

  openrcService = pkgs.writeText "lumo-hermes-agent" (
    replaceTemplate ./openrc-service {
      inherit
        dataDir
        image
        hostWorkDir
        containerWorkDir
        ;
      containerEntrypoint = toString containerEntrypoint;
      podman = "${pkgs.podman}/bin/podman";
    }
  );

  managedSkillNames = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
  );

  # Bundled upstream skills to hide from this deployment. Hermes reads
  # .curator_suppressed before syncing bundled skills, so entries here stay
  # pruned across image updates while user-created skills remain untouched.
  prunedBundledSkillNames = [ "yuanbao" ];

  installManagedSkills = lib.concatMapStringsSep "\n" (
    name:
    let
      source = "${./skills}/${name}";
      target = "${dataDir}/skills/${name}";
    in
    ''
      ${pkgs.coreutils}/bin/rm -rf ${lib.escapeShellArg target}
      ${pkgs.coreutils}/bin/cp -R ${lib.escapeShellArg source} ${lib.escapeShellArg target}
      ${pkgs.coreutils}/bin/chown -R hermes:hermes ${lib.escapeShellArg target}
      ${pkgs.coreutils}/bin/chmod -R u=rwX,go=rX ${lib.escapeShellArg target}
    ''
  ) managedSkillNames;

  pruneBundledSkills = lib.concatMapStringsSep "\n" (
    name:
    let
      target = "${dataDir}/skills/${name}";
    in
    ''
      ${pkgs.coreutils}/bin/rm -rf ${lib.escapeShellArg target}
      if ! ${pkgs.gnugrep}/bin/grep -qxF ${lib.escapeShellArg name} ${dataDir}/skills/.curator_suppressed 2>/dev/null; then
        printf '%s\n' ${lib.escapeShellArg name} >> ${dataDir}/skills/.curator_suppressed
      fi
    ''
  ) prunedBundledSkillNames;

  sharedApiKeyPath = config.sops.secrets.cliproxyapi-shared-api-key.path;
  exaApiKeyPath = config.sops.secrets.exa-api-key.path;
  # User-editable agent secrets as a sops dotenv file: TELEGRAM_BOT_TOKEN,
  # TELEGRAM_ALLOWED_USERS, TELEGRAM_HOME_CHANNEL, and any extra env vars.
  # Edit with: just secret-edit sensitive/hosts/lumo/hermes-agent.env
  hermesEnvPath = config.sops.secrets.hermes-env.path;
in
{
  home.packages = [ pkgs.podman ];

  # cliproxyapi-shared-api-key and exa-api-key are also declared by
  # cliproxyapi.nix; sops-nix is idempotent on (sopsFile, key) tuples, so the
  # redeclaration is a no-op for decryption and keeps this module self-contained.
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

  home.activation.lumoHermesAgent =
    lib.hm.dag.entryAfter [ "lumoDirectories" "sopsAlpine" "lumoHoncho" ]
      ''
            if ! /usr/bin/getent group hermes >/dev/null; then
              /usr/sbin/addgroup -g 10000 -S hermes
            fi
            if ! /usr/bin/id hermes >/dev/null 2>&1; then
              /usr/sbin/adduser -S -D -h ${hostWorkDir} -s /bin/sh -G hermes -u 10000 hermes
            fi

            # Host working directory — bind-mounted into the container at ${containerWorkDir}.
            # Created by adduser for new users; ensure it exists for existing users.
            if [ ! -d ${hostWorkDir} ]; then
              install -d -m 0750 -o hermes -g hermes ${hostWorkDir}
              cp -r /etc/skel/. ${hostWorkDir}/ 2>/dev/null || true
              chown -R hermes:hermes ${hostWorkDir}
            fi
            if [ "$(/usr/bin/getent passwd hermes | cut -d: -f6)" != "${hostWorkDir}" ]; then
              /usr/sbin/usermod -d ${hostWorkDir} hermes
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
            install -m 0644 -o hermes -g hermes ${./SOUL.md} ${dataDir}/SOUL.md

            # Install repo-managed Hermes skills into HERMES_HOME. Only the skill
            # directories shipped by this module are replaced; user-created skills stay
            # untouched. Listed upstream bundled skills are suppressed and removed.
            install -d -m 0755 -o hermes -g hermes ${dataDir}/skills
        ${installManagedSkills}
            touch ${dataDir}/skills/.curator_suppressed
            chown hermes:hermes ${dataDir}/skills/.curator_suppressed
            chmod 0644 ${dataDir}/skills/.curator_suppressed
        ${pruneBundledSkills}

            # Install the managed config on every activation so model routing,
            # Honcho memory, and gateway defaults stay consistent with this repo.
            install -m 0600 -o hermes -g hermes ${initialConfig} ${dataDir}/config.yaml

            # Keep Honcho selected even after Hermes rewrites config.yaml. Existing
            # memory-provider subkeys are replaced deliberately: Honcho's detailed
            # state lives in honcho.json, not under config.yaml.
            if [ -f ${dataDir}/config.yaml ]; then
              /usr/bin/awk -f ${./ensure-memory-provider.awk} ${dataDir}/config.yaml > ${dataDir}/config.yaml.new
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
              /usr/bin/awk -v key="$apikey" -f ${./inject-model-api-key.awk} ${dataDir}/config.yaml > ${dataDir}/config.yaml.new
              install -m 0600 -o hermes -g hermes ${dataDir}/config.yaml.new ${dataDir}/config.yaml
              rm -f ${dataDir}/config.yaml.new
            fi

            # nixpkgs podman on Alpine requires an explicit signature policy.
            # Without this, every `podman pull` fails with "no policy.json file found".
            # "insecureAcceptAnything" matches Docker's default — acceptable for
            # the official nousresearch/hermes-agent image pulled from Docker Hub.
            install -d -m 0755 /etc/containers
            if [ ! -f /etc/containers/policy.json ]; then
              install -m 0644 ${./containers-policy.json} /etc/containers/policy.json
            fi

            install -Dm755 ${openrcService} /etc/init.d/lumo-hermes-agent
            /sbin/rc-update add lumo-hermes-agent default
            /sbin/rc-service lumo-hermes-agent restart
      '';
}
