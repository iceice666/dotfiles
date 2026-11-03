{
  config,
  lab,
  lib,
  pkgs,
  ...
}:

let
  version = "0.4.1";
  src = pkgs.fetchFromGitHub {
    owner = "amosblomqvist";
    repo = "learnharness";
    rev = "v${version}";
    hash = "sha256-tfmvZCGjQJgTjCZ6kyKtV1UeL+sTTiNyR+z9tI5arVQ=";
  };
  # Upstream CI builds on Node 26. Digest-pinned multi-arch manifest list;
  # bump it deliberately together with the source tag.
  nodeImage = "docker.io/library/node:26-bookworm-slim@sha256:bc0a2afd3b74ce12222fc8bab99271e66257f021078f5f4a5d687a77d280c1d9";
  containerfile = ./learnharness.Containerfile;
  # No upstream image exists, so lumo builds one locally. The tag changes
  # whenever the source, Containerfile or base image changes.
  buildId = builtins.substring 0 12 (
    builtins.hashString "sha256" "${src}\n${containerfile}\n${nodeImage}"
  );
  image = "localhost/learnharness:${version}-${buildId}";
  # Set by the Containerfile on the final image and the build stage.
  imageLabel = "dev.justaslime.app=learnharness";

  dataDir = "/var/lib/learnharness";
  envPath = "/var/lib/learnharness-env/learnharness.env";
  buildLog = "/var/log/lumo/learnharness-build.log";
  port = lab.ports.learnharness;
  # The official node image runs as `node` (uid/gid 1000).
  containerUid = "1000";
  sharedApiKeyPath = config.sops.secrets.cliproxyapi-shared-api-key.path;

  podman = "${pkgs.podman}/bin/podman";

  ensureImage = pkgs.writeShellScript "lumo-learnharness-ensure-image" ''
    set -eu
    exec 9>/run/lumo-learnharness-build.lock
    ${pkgs.util-linux}/bin/flock 9
    if ${podman} image exists ${image}; then
      exit 0
    fi
    echo "learnharness: building ${image}" >&2
    ${podman} build --pull=missing \
      --build-arg=NODE_IMAGE=${nodeImage} \
      --file=${containerfile} --tag=${image} ${src} >&2
    # Drop superseded LearnHarness builds and their dangling build stages.
    ${podman} images --filter=label=${imageLabel} --format '{{.Repository}}:{{.Tag}}' \
      | grep -v -F -x -e '${image}' -e '<none>:<none>' \
      | xargs -r ${podman} rmi >&2 || true
    ${podman} image prune --force --filter=label=${imageLabel} >&2 || true
  '';

  appService = pkgs.writeText "lumo-learnharness" ''
    #!/sbin/openrc-run
    name="lumo-learnharness"
    description="Lumo LearnHarness learning app (browser mode)"
    supervisor=supervise-daemon
    command="${podman}"
    # --init: node as PID 1 ignores SIGTERM, so stops would end in SIGKILL
    # mid-write; podman-init forwards it and Next exits cleanly.
    command_args="run --replace --rm --init --name=lumo-learnharness --network=host --cap-drop=all --security-opt=no-new-privileges --env-file=${envPath} --env=NODE_OPTIONS=--use-openssl-ca --env=SSL_CERT_FILE=/etc/dotfiles-ca.crt --env=SSL_CERT_DIR=/etc/dotfiles-certs --volume=${pkgs.dotfiles-cacert}/etc/ssl/certs/ca-no-trust-rules-bundle.crt:/etc/dotfiles-ca.crt:ro --volume=${pkgs.dotfiles-cacert.hashed}/etc/ssl/certs:/etc/dotfiles-certs:ro --volume=${dataDir}:/data --tmpfs=/app/.next/cache:rw,mode=1777,size=256m ${image}"
    command_user="root"
    output_log="/var/log/lumo/learnharness.log"
    error_log="/var/log/lumo/learnharness.log"
    respawn_delay=10
    respawn_max=0

    depend() {
      need lumo-podman
      after networking lumo-cliproxyapi
    }

    start_pre() {
      checkpath -f -m 0640 -o root:root /var/log/lumo/learnharness.log
      checkpath -f -m 0640 -o root:root ${buildLog}
      ${ensureImage} >>${buildLog} 2>&1 || return $?
    }
  '';
in
{
  home.packages = [ pkgs.podman ];

  home.activation.lumoLearnharness =
    lib.hm.dag.entryAfter [ "lumoDirectories" "sopsAlpine" "lumoPodman" "lumoCliproxyapi" ]
      ''
        install -d -m 0755 /var/log/lumo
        # Learner data, the BYOK auth file and $HOME live in the bind mount. The
        # app's file tools can read the container user's home, so nothing else
        # from the host is mounted.
        install -d -m 0700 -o ${containerUid} -g ${containerUid} \
          ${dataDir} ${dataDir}/data ${dataDir}/auth ${dataDir}/home

        install -d -m 0700 -o root -g root "$(dirname ${envPath})"
        shared_api_key="$(cat '${sharedApiKeyPath}')"
        {
          printf 'HOSTNAME=127.0.0.1\n'
          printf 'PORT=${toString port}\n'
          # Settings → Providers → Custom endpoint picks this up as the env-owned
          # key; enter http://127.0.0.1:${toString lab.ports.cliproxyapi}/v1 as the base URL.
          printf 'CUSTOM_OPENAI_API_KEY=%s\n' "$shared_api_key"
          printf 'TZ=Asia/Taipei\n'
        } > ${envPath}
        chmod 0400 ${envPath}

        install -Dm755 ${appService} /etc/init.d/lumo-learnharness
        /sbin/rc-update add lumo-learnharness default
        touch ${buildLog}
        chmod 0640 ${buildLog}
        if ${podman} image exists ${image}; then
          /sbin/rc-service lumo-learnharness restart
        else
          # A cold npm ci + next build on the Pi outlasts deploy-rs's confirm
          # window, so build detached and restart only once the image exists.
          echo "learnharness: building ${image} in the background; see ${buildLog}" >&2
          ${pkgs.util-linux}/bin/setsid -f ${pkgs.runtimeShell} -c \
            '${ensureImage} && /sbin/rc-service lumo-learnharness restart' \
            >>${buildLog} 2>&1 </dev/null
        fi
      '';
}
