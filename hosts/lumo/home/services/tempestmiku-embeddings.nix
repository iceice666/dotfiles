{
  lib,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/tempestmiku-embeddings";
  image = "docker.io/ollama/ollama@sha256:57f573b47f1f71ebb445789f279fe3e596a8beab182f7cf486db9205bad87c5a";
  model = "granite-embedding:278m";
  modelManifest = "${dataDir}/models/manifests/registry.ollama.ai/library/granite-embedding/278m";
  service = pkgs.writeText "lumo-tempestmiku-embeddings" ''
    #!/sbin/openrc-run
    name="lumo-tempestmiku-embeddings"
    description="TempestMiku local-only embedding service"
    supervisor=supervise-daemon
    command="${pkgs.podman}/bin/podman"
    command_args="run --replace --rm --name=lumo-tempestmiku-embeddings --network=host --env=OLLAMA_HOST=127.0.0.1:11434 --env=OLLAMA_KEEP_ALIVE=10m --env=OLLAMA_NO_CLOUD=1 --env=OLLAMA_NUM_PARALLEL=1 --cpuset-cpus=0,1 --cap-drop=all --security-opt=no-new-privileges --pids-limit=512 --tmpfs=/tmp:rw,nosuid,nodev,size=256m --volume=${dataDir}:/root/.ollama ${image}"
    command_user="root"
    output_log="/var/log/lumo/tempestmiku-embeddings.log"
    error_log="/var/log/lumo/tempestmiku-embeddings.log"
    respawn_delay=10
    respawn_max=0

    depend() {
      need lumo-podman
      after networking
    }

    start_pre() {
      checkpath -d -m 0700 -o root:root ${dataDir}
      checkpath -f -m 0640 -o root:root /var/log/lumo/tempestmiku-embeddings.log
      if ! ${pkgs.podman}/bin/podman image exists ${image}; then
        ${pkgs.podman}/bin/podman pull ${image} >&2
      fi
      if [ ! -f ${modelManifest} ]; then
        bootstrap=lumo-tempestmiku-embeddings-bootstrap
        ${pkgs.podman}/bin/podman rm -f "$bootstrap" >/dev/null 2>&1 || true
        ${pkgs.podman}/bin/podman run -d --replace --name="$bootstrap" \
          --network=host \
          --env=OLLAMA_HOST=127.0.0.1:11435 \
          --env=OLLAMA_NUM_PARALLEL=1 \
          --cpuset-cpus=0,1 \
          --volume=${dataDir}:/root/.ollama \
          ${image} >&2
        waited=0
        until ${pkgs.podman}/bin/podman exec "$bootstrap" ollama list >/dev/null 2>&1; do
          if [ "$waited" -ge 180 ]; then
            ${pkgs.podman}/bin/podman rm -f "$bootstrap" >/dev/null 2>&1 || true
            eend 1 "timed out starting the embedding model bootstrap"
            return 1
          fi
          sleep 1
          waited=$((waited + 1))
        done
        if ! ${pkgs.podman}/bin/podman exec "$bootstrap" ollama pull ${model} >&2; then
          ${pkgs.podman}/bin/podman rm -f "$bootstrap" >/dev/null 2>&1 || true
          eend 1 "could not provision the pinned embedding model"
          return 1
        fi
        ${pkgs.podman}/bin/podman rm -f "$bootstrap" >/dev/null
      fi
    }
  '';
in
{
  home.activation.lumoTempestMikuEmbeddings =
    lib.hm.dag.entryAfter [ "lumoPodman" "lumoDirectories" ]
      ''
        install -d -m 0700 -o root -g root ${dataDir}
        install -Dm755 ${service} /etc/init.d/lumo-tempestmiku-embeddings
        /sbin/rc-update add lumo-tempestmiku-embeddings default
        /sbin/rc-service lumo-tempestmiku-embeddings restart
      '';
}
