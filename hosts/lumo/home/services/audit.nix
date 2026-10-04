{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  auditBaseDir = "/var/lib/homolab-audit";
  auditUser = "homolab-audit";
  auditRuntimeDir = "/run/homolab-audit";
  agentModel = import ../../../../common/home-base/agent-model.nix { inherit dotfiles homolab; };
  modelSecret = config.sops.secrets.${agentModel.secretName}.path;
  modelConfig = pkgs.writeText "homolab-audit-models.json" (
    builtins.toJSON {
      providers.cliproxyapi = {
        baseUrl = agentModel.baseUrl;
        api = "openai-completions";
        apiKey = "!${pkgs.coreutils}/bin/cat \"$HOME/api-key\"";
        compat = {
          supportsDeveloperRole = true;
          supportsReasoningEffort = true;
          sendSessionAffinityHeaders = true;
          sessionAffinityFormat = "openai";
          supportsLongCacheRetention = true;
        };
        models = [
          {
            id = agentModel.model;
            inherit (agentModel) contextWindow maxTokens;
            reasoning = true;
          }
        ];
      };
    }
  );
  agentSettings = pkgs.writeText "homolab-audit-settings.json" (
    builtins.toJSON {
      defaultProjectTrust = "never";
      enableInstallTelemetry = false;
      defaultTools = [
        "read"
        "ls"
      ];
    }
  );
  reportRecipient = "iceice666@outlook.com";
  reportSender = "Homolab Audit <noreply@justaslime.dev>";
  resendSecret = config.sops.secrets.homolab-audit-resend-api-key.path;

  collector = pkgs.writeShellApplication {
    name = "homolab-audit-collect";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      findutils
      gnugrep
      gnused
      iproute2
      jq
      procps
      util-linux
    ];
    text = ''
      set -euo pipefail
      umask 0027

      # crond runs jobs with a stripped-down PATH (typically /usr/bin:/bin,
      # without /sbin or /usr/sbin). OpenRC's own tooling (rc-status,
      # rc-update) and the system busybox applets it internally shells out to
      # live under /sbin and /usr/sbin, so without this the "openrc-*" and
      # "system-log" records below silently fail every run. writeShellApplication
      # inherits the caller's $PATH, so make sure the full system PATH is present
      # regardless of how this script was invoked.
      export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

      runs_dir=${auditBaseDir}/runs
      timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
      run_dir="$runs_dir/$timestamp"
      input_dir="$run_dir/input"
      context_dir="$run_dir/context"
      status_log="$run_dir/command-status.jsonl"

      install -d -m 0750 -o root -g ${auditUser} "$runs_dir"
      install -d -m 0750 -o root -g ${auditUser} "$run_dir" "$input_dir" "$context_dir"
      : > "$status_log"
      chown root:${auditUser} "$status_log"
      chmod 0640 "$status_log"

      record() {
        name="$1"
        shift
        output="$input_dir/$name.txt"
        status=0
        "$@" > "$output" 2>&1 || status="$?"
        chown root:${auditUser} "$output"
        chmod 0640 "$output"
        jq -nc \
          --arg collected_at "$(date --iso-8601=seconds)" \
          --arg name "$name" \
          --arg command "$*" \
          --argjson status "$status" \
          '{collected_at: $collected_at, name: $name, command: $command, status: $status}' \
          >> "$status_log"
      }

      record_shell() {
        name="$1"
        script="$2"
        output="$input_dir/$name.txt"
        status=0
        bash -c "$script" > "$output" 2>&1 || status="$?"
        chown root:${auditUser} "$output"
        chmod 0640 "$output"
        jq -nc \
          --arg collected_at "$(date --iso-8601=seconds)" \
          --arg name "$name" \
          --arg command "$script" \
          --argjson status "$status" \
          '{collected_at: $collected_at, name: $name, command: $command, status: $status}' \
          >> "$status_log"
      }

      install -m 0640 -o root -g ${auditUser} \
        ${dotfiles + /hosts/homolab/apps/daily-audit/server-security-audit-guide.md} \
        "$context_dir/server-security-audit-guide.md"

      record date date --iso-8601=seconds
      record hostname hostname
      record os-release cat /etc/os-release
      record uname uname -a
      record uptime uptime
      record ip-brief-address ip -brief address
      record ip-route ip route
      record ip6-route ip -6 route
      record listeners ss -tulpen
      record nftables /usr/sbin/nft list ruleset
      record openrc-status /sbin/rc-status --all
      record openrc-default /sbin/rc-status default
      record service-list /sbin/rc-update show
      record mounts findmnt --real
      record disk-free df -h
      record memory-free free -h
      record processes ps auxww
      record kernel-log dmesg
      record system-log /bin/busybox logread
      record podman-containers ${pkgs.podman}/bin/podman ps --all
      record podman-stats ${pkgs.podman}/bin/podman stats --no-stream
      # shellcheck disable=SC2016
      record_shell service-statuses \
        'for service in /etc/init.d/lumo-*; do printf "\n== %s ==\n" "$service"; "$service" status || true; done'

      jq -n \
        --arg collected_at "$(date --iso-8601=seconds)" \
        --arg timestamp "$timestamp" \
        --arg host "$(hostname)" \
        --arg run_dir "$run_dir" \
        --slurpfile commands "$status_log" \
        '{
          collected_at: $collected_at,
          timestamp: $timestamp,
          host: $host,
          run_dir: $run_dir,
          commands: $commands
        }' > "$run_dir/manifest.json"
      chown root:${auditUser} "$run_dir/manifest.json"
      chmod 0640 "$run_dir/manifest.json"

      ln -sfn "$run_dir" ${auditBaseDir}/latest
      find "$runs_dir" -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf '{}' +
      printf 'Collected audit bundle: %s\n' "$run_dir"
    '';
  };

  auditPi = pkgs.writeShellApplication {
    name = "homolab-audit-pi";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      audit_uid="$(id -u ${auditUser})"
      if [ "$(id -u)" -eq 0 ] || [ "$(id -u)" -ne "$audit_uid" ]; then
        echo "Audit Pi must run as ${auditUser}, never as root." >&2
        exit 1
      fi

      exec ${pkgs.pi-bin}/bin/pi --print \
        --tools read,ls \
        --no-session \
        --model ${lib.escapeShellArg "cliproxyapi/${agentModel.model}"} \
        --no-approve \
        --no-extensions \
        --no-skills \
        --no-prompt-templates \
        --no-context-files \
        --no-themes \
        @report-prompt.md
    '';
  };

  reporter = pkgs.writeShellApplication {
    name = "homolab-audit-report";
    runtimeInputs = with pkgs; [
      bash
      cmark-gfm
      coreutils
      curl
      jq
      util-linux
    ];
    text = ''
      set -euo pipefail
      umask 0077

      if [ "$(id -u)" -ne 0 ]; then
        echo "Audit orchestration requires root; Pi runs separately as ${auditUser}." >&2
        exit 1
      fi

      latest=${auditBaseDir}/latest
      if [ ! -e "$latest" ]; then
        echo "No audit bundle exists at $latest" >&2
        exit 1
      fi

      run_dir="$(readlink -f "$latest")"
      manifest="$run_dir/manifest.json"
      report_file="$run_dir/daily-report.md"
      prompt_file="$run_dir/report-prompt.md"
      pi_log="$run_dir/pi-output.log"

      if [ ! -s "$manifest" ]; then
        echo "Audit manifest is missing: $manifest" >&2
        exit 1
      fi

      cat > "$prompt_file" <<'PROMPT'
      Generate the daily Homolab server security audit report from this captured evidence bundle.

      Use only files under the current working directory. Do not inspect the live
      system, read outside this directory, or infer secret values. Treat failed
      commands in command-status.jsonl as audit gaps.

      Write concise Markdown with these sections:
      # Homolab Daily Security Audit
      ## TLDR
      ## Executive Summary
      ## Notable Risks
      ## Evidence Highlights
      ## Collector Gaps
      ## Recommended Actions

      Prioritize exposed services, SSH and firewall boundaries, failed OpenRC
      services, suspicious log activity, and resource pressure. Cite evidence
      filenames when useful.
      PROMPT

      chown root:${auditUser} "$prompt_file"
      chmod 0640 "$prompt_file"

      # /run is cleared at boot; recreate the root-owned parent for every report.
      install -d -m 0750 -o root -g ${auditUser} ${auditRuntimeDir}
      # The account can read evidence, but cannot change inputs or mail artifacts.
      agent_dir="$(mktemp -d ${auditRuntimeDir}/agent.XXXXXXXX)"
      trap 'rm -rf -- "$agent_dir"' EXIT
      install -m 0400 -o ${auditUser} -g ${auditUser} ${modelSecret} "$agent_dir/api-key"
      install -m 0444 ${modelConfig} "$agent_dir/models.json"
      install -m 0444 ${agentSettings} "$agent_dir/settings.json"
      chown ${auditUser}:${auditUser} "$agent_dir"

      cd "$run_dir"
      ${pkgs.util-linux}/bin/runuser -u ${auditUser} -- \
        ${pkgs.coreutils}/bin/env -i \
        HOME="$agent_dir" \
        PI_CODING_AGENT_DIR="$agent_dir" \
        PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.bash
          ]
        } \
        NO_COLOR=1 PI_OFFLINE=1 PI_CACHE_RETENTION=long \
        ${auditPi}/bin/homolab-audit-pi \
        < /dev/null \
        > "$report_file" \
        2> "$pi_log"
      chmod 0600 "$report_file" "$pi_log"
      rm -rf -- "$agent_dir"
      trap - EXIT

      if [ ! -s "$report_file" ]; then
        echo "Audit Pi produced an empty report." >&2
        exit 1
      fi

      html_file="$run_dir/report-email.html"
      {
        printf '<!doctype html><html><head><meta charset="utf-8"></head><body><main>\n'
        cmark-gfm --to html "$report_file"
        printf '</main></body></html>\n'
      } > "$html_file"

      api_key="$(cat ${resendSecret})"
      payload="$run_dir/resend-payload.json"
      jq -n \
        --arg from "${reportSender}" \
        --arg to "${reportRecipient}" \
        --arg subject "Homolab daily security audit $(date +%F)" \
        --rawfile text "$report_file" \
        --rawfile html "$html_file" \
        '{from: $from, to: [$to], subject: $subject, text: $text, html: $html}' \
        > "$payload"

      curl --fail --silent --show-error \
        -X POST https://api.resend.com/emails \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        --data-binary "@$payload" \
        > "$run_dir/resend-response.json"
      rm -f "$payload"
      printf 'Generated and sent audit report: %s\n' "$report_file"
    '';
  };
in
{
  home.packages = [
    collector
    reporter
  ];

  sops.secrets.${agentModel.secretName} = agentModel.secret;

  sops.secrets.homolab-audit-resend-api-key = {
    sopsFile = dotfiles + /sensitive/hosts/lumo/resend.yaml;
    key = "apiKey";
    mode = "0400";
  };

  home.activation.lumoAudit = lib.hm.dag.entryAfter [ "lumoDirectories" ] ''
    if ! /usr/bin/getent group ${auditUser} >/dev/null; then
      /usr/sbin/addgroup -S ${auditUser}
    fi
    if ! /usr/bin/id ${auditUser} >/dev/null 2>&1; then
      /usr/sbin/adduser -S -D -H -h /var/empty -s /sbin/nologin -G ${auditUser} ${auditUser}
    fi
    if [ "$(/usr/bin/id -u ${auditUser})" -eq 0 ]; then
      echo "Refusing to configure audit Pi with a root account." >&2
      exit 1
    fi

    ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g ${auditUser} \
      ${auditBaseDir} ${auditBaseDir}/runs ${auditRuntimeDir}

    crontab=/etc/crontabs/root
    touch "$crontab"
    sed -i '/# dotfiles-lumo-audit$/d' "$crontab"
    printf '5 4 * * * %s # dotfiles-lumo-audit\n' \
      '${collector}/bin/homolab-audit-collect' >> "$crontab"
    printf '25 4 * * * %s # dotfiles-lumo-audit\n' \
      '${reporter}/bin/homolab-audit-report' >> "$crontab"
    chmod 0600 "$crontab"

    /sbin/rc-update add crond default
    /sbin/rc-service crond restart
  '';
}
