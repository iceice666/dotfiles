{
  homolab,
  pkgs,
  ...
}:

let
  interface = homolab.network.interface;
  idleWindow = 1200; # 20 minutes in seconds

  idleSuspendScript = pkgs.writeShellScript "homolab-idle-suspend" ''
    set -euo pipefail
    last_active_file=/run/homolab-last-active

    # Update last-active if any LLM or SSH connections are established.
    if ${pkgs.iproute2}/bin/ss -tnH state established | \
            ${pkgs.gnugrep}/bin/grep -qE ':(${toString homolab.ports.shimmy}|${toString homolab.ports.ssh})'; then
        ${pkgs.coreutils}/bin/date +%s > "$last_active_file"
        exit 0
    fi

    # Seed last-active if missing (guard for unexpected restarts).
    if [ ! -f "$last_active_file" ]; then
        ${pkgs.coreutils}/bin/date +%s > "$last_active_file"
        exit 0
    fi

    last_active=$(${pkgs.coreutils}/bin/cat "$last_active_file")
    now=$(${pkgs.coreutils}/bin/date +%s)
    idle_for=$((now - last_active))

    if [ "$idle_for" -ge ${toString idleWindow} ]; then
        ${pkgs.util-linux}/bin/logger -t homolab-idle-suspend \
            "idle ''${idle_for}s >= ${toString idleWindow}s, suspending"
        ${pkgs.systemd}/bin/systemctl suspend
    fi
  '';
in
{
  # Arm Wake-on-LAN so the NIC can receive magic packets while suspended.
  networking.interfaces.${interface}.wakeOnLan.enable = true;

  # Re-arm WoL after NetworkManager brings the interface up, so it survives
  # NM reapplying its connection profile on reconnect or resume.
  networking.networkmanager.dispatcherScripts = [
    {
      source = pkgs.writeText "nm-wol-rearm" ''
        #!/bin/sh
        [ "$1" = "${interface}" ] || exit 0
        [ "$2" = "up" ] || exit 0
        ${pkgs.ethtool}/bin/ethtool -s ${interface} wol g
      '';
      type = "basic";
    }
  ];

  # Seed last-active on boot so the idle window starts fresh.
  systemd.services.homolab-mark-active = {
    description = "Seed idle-suspend activity timestamp on boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "seed-last-active" ''
        ${pkgs.coreutils}/bin/date +%s > /run/homolab-last-active
      '';
    };
  };

  # Re-seed last-active on every resume so the full idle window is available
  # before the next auto-suspend.
  powerManagement.resumeCommands = ''
    ${pkgs.coreutils}/bin/date +%s > /run/homolab-last-active
  '';

  # Rolling idle-check: runs every 5 minutes, suspends if no LLM or SSH
  # connections have been active for >= ${toString idleWindow}s.
  systemd.services.homolab-idle-suspend = {
    description = "Suspend homolab when idle";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = idleSuspendScript;
    };
  };

  systemd.timers.homolab-idle-suspend = {
    description = "Periodic idle check for homolab auto-suspend";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Persistent = true;
      Unit = "homolab-idle-suspend.service";
    };
  };
}
