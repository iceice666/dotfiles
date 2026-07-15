{
  config,
  homolab,
  pkgs,
  username,
  ...
}:

let
  auditBaseDir = "/var/lib/homolab-audit";
  auditGroup = "homolab-audit";
  reportRecipient = "iceice666@outlook.com";
  reportSender = "Homolab Audit <${homolab.contact.noReplyEmail}>";
  resendApiKeyFile = config.sops.secrets."homolab-audit-resend-api-key".path;

  selectedUnits = [
    "traefik.service"
    "authelia-main.service"
    "podman.socket"
    "postgresql.service"
    "redis.service"
    "tailscaled.service"
    "prometheus.service"
    "grafana.service"
    "tea-asr-1-1-mini.service"
    "multica-backend.service"
    "multica-frontend.service"
    "dynacat.service"
    "cloudflare-ips-refresh.service"
    "cloudflare-ips-refresh.timer"
  ];

  selectedUnitsText = pkgs.lib.concatStringsSep " " selectedUnits;
  selectedJournalUnitArgs = pkgs.lib.concatMapStringsSep " " (unit: "-u ${unit}") selectedUnits;

  collector = pkgs.writeShellApplication {
    name = "homolab-audit-collect";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      findutils
      glibc.getent
      gnused
      hostname
      iproute2
      ipset
      iptables
      jq
      podman
      procps
      sysstat
      systemd
      util-linux
    ];
    text = ''
      set -euo pipefail
      umask 0027

      base_dir=${auditBaseDir}
      runs_dir="$base_dir/runs"
      timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
      collected_at="$(date --iso-8601=seconds)"
      run_dir="$runs_dir/$timestamp"
      input_dir="$run_dir/input"
      context_dir="$run_dir/context"
      status_log="$run_dir/command-status.jsonl"

      install -d -m 0750 -o root -g ${auditGroup} "$base_dir" "$runs_dir"
      install -d -m 2770 -o root -g ${auditGroup} "$run_dir"
      install -d -m 2750 -o root -g ${auditGroup} "$input_dir" "$context_dir"
      : > "$status_log"
      chown root:${auditGroup} "$status_log"
      chmod 0640 "$status_log"

      record_status() {
        name="$1"
        command="$2"
        status="$3"

        jq -nc \
          --arg collected_at "$(date --iso-8601=seconds)" \
          --arg name "$name" \
          --arg command "$command" \
          --argjson status "$status" \
          '{collected_at: $collected_at, name: $name, command: $command, status: $status}' \
          >> "$status_log"
      }

      finish_file() {
        path="$1"
        chown root:${auditGroup} "$path"
        chmod 0640 "$path"
      }

      run_cmd() {
        name="$1"
        shift
        output="$input_dir/$name.txt"

        if "$@" > "$output" 2>&1; then
          status=0
        else
          status="$?"
        fi

        finish_file "$output"
        record_status "$name" "$*" "$status"
      }

      run_sh() {
        name="$1"
        script="$2"
        output="$input_dir/$name.txt"

        if bash -c "$script" > "$output" 2>&1; then
          status=0
        else
          status="$?"
        fi

        finish_file "$output"
        record_status "$name" "$script" "$status"
      }

      cp ${../apps/daily-audit/server-security-audit-guide.md} "$context_dir/server-security-audit-guide.md"
      finish_file "$context_dir/server-security-audit-guide.md"

      run_cmd date date --iso-8601=seconds
      run_cmd hostname hostname
      run_cmd hostnamectl hostnamectl
      run_sh nixos-version "printf '%s\n' '${config.system.nixos.version}'"
      run_cmd uname uname -a
      run_cmd uptime uptime
      run_cmd bootctl-status bootctl status
      run_cmd ip-brief-addr ip -brief addr
      run_cmd ip-route ip route
      run_cmd ip6-route ip -6 route
      run_cmd listeners ss -tulpen
      run_cmd iptables-v4 iptables -S
      run_cmd iptables-v6 ip6tables -S
      run_cmd ipset-names ipset list -name
      run_cmd ipset-cloudflare-v4 ipset list cloudflare-v4
      run_cmd ipset-cloudflare-v6 ipset list cloudflare-v6
      run_cmd systemd-failed systemctl --no-pager --plain --failed
      run_cmd systemd-timers systemctl --no-pager --plain list-timers --all
      run_sh systemd-selected-status "systemctl --no-pager --plain status ${selectedUnitsText}"
      run_sh podman-containers "podman ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'"
      run_cmd mounts findmnt --real --output TARGET,SOURCE,FSTYPE,OPTIONS
      run_cmd disk-free df -h
      run_cmd memory-free free -h
      run_cmd vmstat vmstat 1 5
      run_cmd io-summary iostat -xz 1 2
      run_sh top-cpu "top -b -n 1 -o %CPU | head -n 40"
      run_sh processes-by-cpu "ps -eo pid,ppid,user,stat,%cpu,%mem,rss,vsz,comm,args --sort=-%cpu | head -n 40"
      run_sh processes-by-memory "ps -eo pid,ppid,user,stat,%cpu,%mem,rss,vsz,comm,args --sort=-%mem | head -n 40"
      run_sh systemd-cgroups "systemd-cgtop --batch --iterations=1 --depth=3"
      run_sh podman-stats "podman stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}'"
      run_cmd podman-group getent group podman
      run_cmd audit-group getent group ${auditGroup}
      run_sh journal-selected-24h "journalctl --no-pager --since '24 hours ago' ${selectedJournalUnitArgs}"
      run_sh journal-warnings-24h "journalctl --no-pager --since '24 hours ago' -p warning -n 5000"

      jq -n \
        --arg collected_at "$collected_at" \
        --arg timestamp "$timestamp" \
        --arg host "$(hostname)" \
        --arg run_dir "$run_dir" \
        --arg input_dir "$input_dir" \
        --arg context_dir "$context_dir" \
        --slurpfile commands "$status_log" \
        '{
          collected_at: $collected_at,
          timestamp: $timestamp,
          host: $host,
          run_dir: $run_dir,
          input_dir: $input_dir,
          context_dir: $context_dir,
          commands: $commands
        }' > "$run_dir/manifest.json"
      finish_file "$run_dir/manifest.json"

      ln -sfn "$run_dir" "$base_dir/latest"
      chown -h root:${auditGroup} "$base_dir/latest"

      find "$runs_dir" -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf '{}' +

      printf 'Collected homolab audit bundle: %s\n' "$run_dir"
    '';
  };

  reporter = pkgs.writeShellApplication {
    name = "homolab-audit-report";
    runtimeInputs = with pkgs; [
      bash
      bubblewrap
      coreutils
      curl
      cmark-gfm
      gnused
      jq
      pkgs.oh-my-pi-bin
    ];
    text = ''
      set -euo pipefail
      umask 0027

      base_dir=${auditBaseDir}
      latest="$base_dir/latest"
      api_key_file=${resendApiKeyFile}

      if [ ! -e "$latest" ]; then
        printf 'No audit bundle exists at %s\n' "$latest" >&2
        exit 1
      fi

      run_dir="$(readlink -f "$latest")"
      manifest="$run_dir/manifest.json"
      report_file="$run_dir/daily-report.md"
      prompt_file="$run_dir/report-prompt.md"
      omp_log="$run_dir/omp-output.log"

      if [ ! -s "$manifest" ]; then
        printf 'Audit manifest is missing or empty: %s\n' "$manifest" >&2
        exit 1
      fi

      now_epoch="$(date +%s)"
      manifest_epoch="$(stat -c %Y "$manifest")"
      max_age_seconds=$((26 * 60 * 60))

      send_text_file() {
        subject="$1"
        text_file="$2"
        response_file="$3"
        payload_file="$run_dir/resend-payload.json"
        curl_config_file="$run_dir/resend-curl.conf"
        api_key="$(tr -d '\n' < "$api_key_file")"

        jq -n \
          --arg from "${reportSender}" \
          --arg to "${reportRecipient}" \
          --arg subject "$subject" \
          --rawfile text "$text_file" \
          '{from: $from, to: [$to], subject: $subject, text: $text}' \
          > "$payload_file"
        chmod 0600 "$payload_file"

        {
          printf 'request = "POST"\n'
          printf 'url = "https://api.resend.com/emails"\n'
          printf 'header = "Authorization: Bearer %s"\n' "$api_key"
          printf 'header = "Content-Type: application/json"\n'
          printf 'data-binary = "@%s"\n' "$payload_file"
          printf 'fail\n'
          printf 'silent\n'
          printf 'show-error\n'
        } > "$curl_config_file"
        chmod 0600 "$curl_config_file"

        curl_status=0
        curl --config "$curl_config_file" > "$response_file" || curl_status="$?"
        chmod 0640 "$response_file" || true
        rm -f "$payload_file" "$curl_config_file"
        return "$curl_status"
      }

      render_markdown_email() {
        markdown_file="$1"
        html_file="$2"

        {
          printf '<!doctype html>\n'
          printf '<html><head><meta charset="utf-8">\n'
          printf '<style>\n'
          printf 'body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;line-height:1.55;color:#1f2937;background:#ffffff;margin:0;padding:24px;}\n'
          printf 'main{max-width:760px;margin:0 auto;}\n'
          printf 'h1{font-size:24px;line-height:1.25;margin:0 0 20px;color:#111827;}\n'
          printf 'h2{font-size:18px;line-height:1.35;margin:28px 0 10px;color:#111827;border-bottom:1px solid #e5e7eb;padding-bottom:6px;}\n'
          printf 'h3{font-size:16px;line-height:1.4;margin:22px 0 8px;color:#111827;}\n'
          printf 'p,ul,ol{margin:0 0 14px;}\n'
          printf 'li{margin:4px 0;}\n'
          printf 'code{font-family:"SFMono-Regular",Consolas,monospace;font-size:0.92em;background:#f3f4f6;border-radius:4px;padding:1px 4px;}\n'
          printf 'pre{background:#f3f4f6;border-radius:6px;padding:12px;overflow-x:auto;}\n'
          printf 'pre code{background:transparent;padding:0;}\n'
          printf 'blockquote{border-left:4px solid #d1d5db;margin:0 0 14px;padding:2px 0 2px 12px;color:#4b5563;}\n'
          printf 'table{border-collapse:collapse;margin:0 0 14px;width:100%%;}\n'
          printf 'th,td{border:1px solid #e5e7eb;padding:6px 8px;text-align:left;vertical-align:top;}\n'
          printf 'th{background:#f9fafb;}\n'
          printf '</style></head><body><main>\n'
          cmark-gfm --to html "$markdown_file"
          printf '</main></body></html>\n'
        } > "$html_file"

        chmod 0640 "$html_file"
      }

      send_markdown_file() {
        subject="$1"
        text_file="$2"
        response_file="$3"
        payload_file="$run_dir/resend-payload.json"
        curl_config_file="$run_dir/resend-curl.conf"
        html_file="$run_dir/report-email.html"
        api_key="$(tr -d '\n' < "$api_key_file")"

        render_markdown_email "$text_file" "$html_file"

        jq -n \
          --arg from "${reportSender}" \
          --arg to "${reportRecipient}" \
          --arg subject "$subject" \
          --rawfile text "$text_file" \
          --rawfile html "$html_file" \
          '{from: $from, to: [$to], subject: $subject, text: $text, html: $html}' \
          > "$payload_file"
        chmod 0600 "$payload_file"

        {
          printf 'request = "POST"\n'
          printf 'url = "https://api.resend.com/emails"\n'
          printf 'header = "Authorization: Bearer %s"\n' "$api_key"
          printf 'header = "Content-Type: application/json"\n'
          printf 'data-binary = "@%s"\n' "$payload_file"
          printf 'fail\n'
          printf 'silent\n'
          printf 'show-error\n'
        } > "$curl_config_file"
        chmod 0600 "$curl_config_file"

        curl_status=0
        curl --config "$curl_config_file" > "$response_file" || curl_status="$?"
        chmod 0640 "$response_file" || true
        rm -f "$payload_file" "$curl_config_file"
        return "$curl_status"
      }

      if [ $((now_epoch - manifest_epoch)) -gt "$max_age_seconds" ]; then
        failure_file="$run_dir/report-failure.txt"
        {
          printf 'Homolab daily audit report was not generated.\n\n'
          printf 'Reason: latest audit bundle is older than 26 hours.\n'
          printf 'Bundle: %s\n' "$run_dir"
          printf 'Manifest mtime: %s\n' "$(date --date="@$manifest_epoch" --iso-8601=seconds)"
        } > "$failure_file"
        chmod 0640 "$failure_file"
        send_text_file "Homolab audit report skipped: stale bundle" "$failure_file" "$run_dir/resend-stale-response.json" || true
        printf 'Latest audit bundle is stale: %s\n' "$run_dir" >&2
        exit 1
      fi

      cat > "$prompt_file" <<'PROMPT'
      Generate the daily Homolab server security audit report from this captured evidence bundle.

      Use only files under the current working directory:
      - manifest.json
      - command-status.jsonl
      - input/
      - context/server-security-audit-guide.md

      Do not inspect the live system, do not read outside the current working directory, do not infer decrypted secret values, and do not run collection commands. Treat command failures in command-status.jsonl as audit gaps.

      Write a concise Markdown report with these sections:
      # Homolab Daily Security Audit
      ## TLDR
      ## Executive Summary
      ## Notable Risks
      ## Evidence Highlights
      ## Collector Gaps
      ## Recommended Actions

      In TLDR, give 3-5 bullets summarizing the most important status, risk, and action items. Prioritize externally reachable surfaces, authentication boundaries, firewall drift, failed services, suspicious 24-hour log activity, stale timers, and resource pressure. Include concrete evidence filenames when useful.
      PROMPT
      chmod 0640 "$prompt_file"

      omp_status=0
      omp --print \
        --no-session \
        --approval-mode yolo \
        --cwd "$run_dir" \
        @"$prompt_file" \
        > "$report_file" \
        2> "$omp_log" || omp_status="$?"
      chmod 0640 "$omp_log" || true

      if [ "$omp_status" -ne 0 ] || [ ! -s "$report_file" ]; then
        if [ "$omp_status" -eq 0 ]; then
          omp_status=1
        fi

        failure_file="$run_dir/report-failure.txt"
        {
          printf 'Homolab daily audit report generation failed.\n\n'
          printf 'Bundle: %s\n' "$run_dir"
          printf 'OMP exit status: %s\n' "$omp_status"
          printf 'OMP log: %s\n' "$omp_log"
        } > "$failure_file"
        chmod 0640 "$failure_file"
        send_text_file "Homolab audit report generation failed" "$failure_file" "$run_dir/resend-failure-response.json" || true
        exit "$omp_status"
      fi

      chmod 0640 "$report_file"

      email_status=0
      send_markdown_file \
        "Homolab daily security audit $(date +%F)" \
        "$report_file" \
        "$run_dir/resend-response.json" || email_status="$?"

      if [ "$email_status" -ne 0 ]; then
        failure_file="$run_dir/email-failure.txt"
        {
          printf 'Homolab daily audit report was generated but email delivery failed.\n\n'
          printf 'Bundle: %s\n' "$run_dir"
          printf 'Report: %s\n' "$report_file"
          printf 'Email exit status: %s\n' "$email_status"
        } > "$failure_file"
        chmod 0640 "$failure_file"
        send_text_file "Homolab audit email delivery failed" "$failure_file" "$run_dir/resend-delivery-failure-response.json" || true
        exit "$email_status"
      fi

      printf 'Generated and sent homolab audit report: %s\n' "$report_file"
    '';
  };
in
{
  users = {
    groups.${auditGroup} = { };
    users.${username}.extraGroups = [ auditGroup ];
  };

  systemd.tmpfiles.rules = [
    "d '${auditBaseDir}' 0750 root ${auditGroup} - -"
    "d '${auditBaseDir}/runs' 0750 root ${auditGroup} - -"
  ];

  systemd.services.homolab-audit-collect = {
    description = "Collect Homolab daily audit evidence";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      UMask = "0027";
      ExecStart = "${collector}/bin/homolab-audit-collect";
    };
  };

  systemd.timers.homolab-audit-collect = {
    description = "Collect Homolab daily audit evidence";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:05:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
      Unit = "homolab-audit-collect.service";
    };
  };

  systemd.services.homolab-audit-report = {
    description = "Generate and email Homolab daily audit report";
    after = [
      "network-online.target"
      "homolab-audit-collect.service"
    ];
    requires = [ "homolab-audit-collect.service" ];
    wants = [ "network-online.target" ];

    environment = {
      HOME = "/home/${username}";
      NO_COLOR = "1";
      PI_CODING_AGENT_DIR = "/home/${username}/.omp/agent";
    };

    serviceConfig = {
      Type = "oneshot";
      User = username;
      Group = "users";
      SupplementaryGroups = [ auditGroup ];
      UMask = "0027";
      WorkingDirectory = auditBaseDir;
      ExecStart = "${reporter}/bin/homolab-audit-report";
    };
  };

  systemd.timers.homolab-audit-report = {
    description = "Generate and email Homolab daily audit report";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:25:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
      Unit = "homolab-audit-report.service";
    };
  };
}
