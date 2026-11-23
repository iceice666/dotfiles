{ lib, pkgs, ... }:

let
  stateDir = "/var/lib/lumo-logrotate";

  # supervise-daemon keeps each log open, so copy and truncate in place
  # instead of moving the file. Size-gated so the audit collector at 04:05
  # still sees a full day of most service logs.
  config = pkgs.writeText "lumo-logrotate.conf" ''
    /var/log/lumo/*.log {
      size 50M
      rotate 4
      compress
      copytruncate
      missingok
      notifempty
    }
  '';
in
{
  # Runs before lumoAudit, whose crond restart picks up this entry too.
  home.activation.lumoLogrotate = lib.hm.dag.entryBetween [ "lumoAudit" ] [ "lumoDirectories" ] ''
    ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${stateDir}

    crontab=/etc/crontabs/root
    ${pkgs.coreutils}/bin/touch "$crontab"
    ${pkgs.gnused}/bin/sed -i '/# dotfiles-lumo-logrotate$/d' "$crontab"
    # After the audit collector (04:05) and reporter (04:25).
    printf '45 4 * * * %s # dotfiles-lumo-logrotate\n' \
      '${pkgs.logrotate}/bin/logrotate -s ${stateDir}/status ${config}' >> "$crontab"
    ${pkgs.coreutils}/bin/chmod 0600 "$crontab"
  '';
}
