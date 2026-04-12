{
  config,
  pkgs,
  unstablePkgs,
  username,
  homeDirectory,
  ...
}:

let
  auditScript = pkgs.writeShellApplication {
    name = "homolab-daily-audit";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.systemd
      unstablePkgs.opencode
    ];
    text = ''
      set -euo pipefail

      state_dir="''${STATE_DIRECTORY:-/var/lib/homolab-daily-audit}"
      last_success_file="$state_dir/last-success"
      report_date="$(date +%F)"
      run_stamp="$(date --iso-8601=seconds | tr ':' '-')"
      run_dir="$state_dir/runs/$run_stamp"
      bundle_dir="$run_dir/bundle"
      json_output="$run_dir/opencode.jsonl"
      stderr_output="$run_dir/opencode.stderr"
      report_file="$run_dir/report.md"
      email_payload="$run_dir/email.json"
      email_response="$run_dir/email-response.json"

      mkdir -p "$bundle_dir"

      now_epoch="$(date +%s)"
      default_since_epoch="$((now_epoch - 48 * 60 * 60))"
      since_epoch="$default_since_epoch"

      if [ -s "$last_success_file" ]; then
        last_success_raw="$(<"$last_success_file")"
        if last_success_epoch="$(date --date "$last_success_raw" +%s 2>/dev/null)"; then
          if [ "$last_success_epoch" -gt "$default_since_epoch" ]; then
            since_epoch="$last_success_epoch"
          fi
        fi
      fi

      since_iso="$(date --date "@$since_epoch" --iso-8601=seconds)"
      until_iso="$(date --iso-8601=seconds)"
      since_journal="$(date --date "@$since_epoch" "+%Y-%m-%d %H:%M:%S")"
      until_journal="$(date "+%Y-%m-%d %H:%M:%S")"

      write_journal_section() {
        local output="$1"
        local title="$2"
        shift 2

        {
          printf '# %s\n\n' "$title"
          printf '```text\n'
          journalctl --since "$since_journal" --until "$until_journal" -o short-iso --no-pager "$@" 2>&1 || true
          printf '```\n'
        } > "$output"
      }

      {
        printf '# Homolab Audit Window\n\n'
        printf -- '- Host: %s\n' "$(hostname)"
        printf -- '- Since: %s\n' "$since_iso"
        printf -- '- Until: %s\n' "$until_iso"
        printf -- '- Trigger: systemd timer\n'
        printf '\n## Service Scope\n\n'
        printf -- "- Public edge: \`sshd.service\`, \`traefik.service\`, \`cloudflared-tunnel.service\`\n"
        printf -- "- Auth: \`authelia-main.service\`\n"
        printf -- "- Apps: \`forgejo.service\`, \`woodpecker-server.service\`, \`woodpecker-agent-docker.service\`, \`dynacat.service\`\n"
        printf -- "- Platform: \`docker.service\`, \`postgresql.service\`, \`rustfs.service\`, \`dnsmasq.service\`, \`cloudflare-ips-refresh.service\`, \`cloudflare-dyndns.service\`\n"
        printf '\n## Failed Units\n\n```text\n'
        systemctl list-units --state=failed --all --no-pager --no-legend 2>&1 || true
        printf '```\n\n'
        printf '## Recent Restarts And Failures\n\n```text\n'
        journalctl \
          --since "$since_journal" \
          --until "$until_journal" \
          --grep 'Failed with result|Main process exited|Scheduled restart job|Starting |Started |Stopping |Stopped ' \
          -o short-iso \
          --no-pager \
          -n 200 2>&1 || true
        printf '```\n'
      } > "$bundle_dir/00-overview.md"

      write_journal_section \
        "$bundle_dir/10-priority-journal.md" \
        "Priority Journal" \
        -p warning..alert \
        -n 400

      {
        printf '# Authentication And Access\n\n'
        printf '## sshd.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u sshd.service -o short-iso --no-pager -n 300 2>&1 || true
        printf '```\n\n'
        printf '## authelia-main.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u authelia-main.service -o short-iso --no-pager -n 300 2>&1 || true
        printf '```\n\n'
        printf '## sudo And polkit\n\n```text\n'
        journalctl \
          --since "$since_journal" \
          --until "$until_journal" \
          -u polkit.service \
          -t sudo \
          --grep 'authentication failure|not allowed|denied|COMMAND=|session opened|session closed' \
          -o short-iso \
          --no-pager \
          -n 200 2>&1 || true
        printf '```\n'
      } > "$bundle_dir/20-authentication.md"

      {
        printf '# Edge Services\n\n'
        printf '## traefik.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u traefik.service -o short-iso --no-pager -n 250 2>&1 || true
        printf '```\n\n'
        printf '## cloudflared-tunnel.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u cloudflared-tunnel.service -o short-iso --no-pager -n 250 2>&1 || true
        printf '```\n\n'
        printf '## dnsmasq.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u dnsmasq.service -o short-iso --no-pager -n 250 2>&1 || true
        printf '```\n'
      } > "$bundle_dir/30-edge-services.md"

      {
        printf '# Application Services\n\n'
        printf '## forgejo.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u forgejo.service -o short-iso --no-pager -n 250 2>&1 || true
        printf '```\n\n'
        printf '## woodpecker-server.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u woodpecker-server.service -o short-iso --no-pager -n 250 2>&1 || true
        printf '```\n\n'
        printf '## woodpecker-agent-docker.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u woodpecker-agent-docker.service -o short-iso --no-pager -n 250 2>&1 || true
        printf '```\n\n'
        printf '## docker.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u docker.service -o short-iso --no-pager -n 250 2>&1 || true
        printf '```\n\n'
        printf '## postgresql.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u postgresql.service -o short-iso --no-pager -n 250 2>&1 || true
        printf '```\n\n'
        printf '## rustfs.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u rustfs.service -o short-iso --no-pager -n 250 2>&1 || true
        printf '```\n\n'
        printf '## dynacat.service\n\n```text\n'
        journalctl --since "$since_journal" --until "$until_journal" -u dynacat.service -o short-iso --no-pager -n 250 2>&1 || true
        printf '```\n'
      } > "$bundle_dir/40-application-services.md"

      write_journal_section \
        "$bundle_dir/50-kernel.md" \
        "Kernel Messages" \
        -k \
        -p warning..alert \
        -n 250

      if opencode run \
        --format json \
        --agent plan \
        --command daily-audit \
        --dir "$HOME" \
        --file "$bundle_dir/00-overview.md" \
        --file "$bundle_dir/10-priority-journal.md" \
        --file "$bundle_dir/20-authentication.md" \
        --file "$bundle_dir/30-edge-services.md" \
        --file "$bundle_dir/40-application-services.md" \
        --file "$bundle_dir/50-kernel.md" \
        "$since_iso" \
        "$until_iso" \
        > "$json_output" 2> "$stderr_output"; then
        jq -r 'select(.type == "text") | .part.text' "$json_output" > "$report_file"
      fi

      audit_subject="[homolab] Daily audit report for $report_date"

      if [ ! -s "$report_file" ]; then
        audit_subject="[homolab] Daily audit pipeline failed for $report_date"

        {
          printf '# Homolab Daily Audit\n\n'
          printf '## Executive Summary\n\n'
          printf 'The daily audit pipeline failed before a model-authored report was generated.\n\n'
          printf '## Findings\n\n'
          printf -- "- Audit window: \`%s\` to \`%s\`\n" "$since_iso" "$until_iso"
          printf -- "- Run directory: \`%s\`\n" "$run_dir"
          printf '\n```text\n'
          if [ -s "$stderr_output" ]; then
            cat "$stderr_output"
          else
            printf 'OpenCode did not produce any report text.\n'
          fi
          printf '```\n\n'
          printf '## Benign Noise\n\n'
          printf 'Not evaluated because the pipeline failed.\n\n'
          printf '## Follow-Up Actions\n\n'
          printf -- "- Inspect \`%s\` on homolab.\n" "$run_dir"
          printf -- "- Re-run \`systemctl start homolab-daily-audit.service\` after fixing the failure.\n\n"
          printf '## Evidence Reviewed\n\n'
          printf -- "- \`%s\`\n" "$bundle_dir/00-overview.md"
          printf -- "- \`%s\`\n" "$bundle_dir/10-priority-journal.md"
          printf -- "- \`%s\`\n" "$bundle_dir/20-authentication.md"
          printf -- "- \`%s\`\n" "$bundle_dir/30-edge-services.md"
          printf -- "- \`%s\`\n" "$bundle_dir/40-application-services.md"
          printf -- "- \`%s\`\n" "$bundle_dir/50-kernel.md"
        } > "$report_file"
      fi

      ln -sfn "$run_dir" "$state_dir/latest"

      jq -n \
        --arg from 'Homolab Audit <noreply@justaslime.dev>' \
        --arg to 'iceice666@outlook.com' \
        --arg subject "$audit_subject" \
        --rawfile text "$report_file" \
        '{
          from: $from,
          to: [ $to ],
          subject: $subject,
          text: $text
        }' > "$email_payload"

      curl \
        --fail \
        --silent \
        --show-error \
        --header "Authorization: Bearer $(<"${config.sops.secrets."daily-audit-resend-api-key".path}")" \
        --header 'Content-Type: application/json' \
        --data "@$email_payload" \
        https://api.resend.com/emails \
        > "$email_response"

      printf '%s\n' "$until_iso" > "$last_success_file"
    '';
  };
in
{
  systemd.services.homolab-daily-audit = {
    description = "Generate and email the homolab daily audit report";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = username;
      SupplementaryGroups = [ "systemd-journal" ];
      WorkingDirectory = homeDirectory;
      Environment = [
        "HOME=${homeDirectory}"
        "XDG_CONFIG_HOME=${homeDirectory}/.config"
      ];
      ExecStart = "${auditScript}/bin/homolab-daily-audit";
      StateDirectory = "homolab-daily-audit";
      UMask = "0077";
      TimeoutStartSec = "30m";
    };
  };

  systemd.timers.homolab-daily-audit = {
    description = "Run the homolab daily audit report";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "20m";
      OnUnitActiveSec = "1d";
      Persistent = true;
      RandomizedDelaySec = "30m";
      Unit = "homolab-daily-audit.service";
    };
  };
}
