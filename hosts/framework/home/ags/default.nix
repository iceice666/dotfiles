{
  config,
  lib,
  pkgs,
  unstablePkgs,
  lockScreen,
  themegenCache,
  ...
}:

let
  agsConfigDir = "${config.home.homeDirectory}/.config/ags";
  ags = pkgs.ags.override { extraPackages = [ pkgs.astal.tray ]; };
  icons = import ./icons.nix { inherit pkgs; };
  shellAssets =
    pkgs.runCommand "framework-ags-assets"
      {
        nativeBuildInputs = [
          ags
          pkgs.dart-sass
        ];
      }
      ''
        mkdir -p "$out" work
        cp ${./app.tsx} work/app.tsx
        ags bundle work/app.tsx "$out/app.js"
        cp ${./style.scss} work/style.scss
        for mode in light dark; do
          cp --remove-destination ${themegenCache}/.config/ags/theme-$mode.scss work/theme.scss
          sass --no-source-map work/style.scss "$out/style-$mode.css"
        done
      '';
  stateBinary = lib.getExe pkgs.framework-shell-state;
  stateConfig = pkgs.writeText "framework-shell-state-config.json" (
    builtins.toJSON {
      home = config.home.homeDirectory;
      preferredInterface = "wlp192s0";
      commands = {
        niri = "${unstablePkgs.niri}/bin/niri";
        wpctl = "${pkgs.wireplumber}/bin/wpctl";
        pactl = "${pkgs.pulseaudio}/bin/pactl";
        upower = "${pkgs.upower}/bin/upower";
        tlpStat = "${pkgs.tlp}/bin/tlp-stat";
        playerctl = "${pkgs.playerctl}/bin/playerctl";
        brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
        nmcli = "${pkgs.networkmanager}/bin/nmcli";
        makoctl = "${unstablePkgs.mako}/bin/makoctl";
        pavucontrol = "${pkgs.pavucontrol}/bin/pavucontrol";
      };
      icons = builtins.mapAttrs (_: toString) icons;
    }
  );
  stateCommand = "${stateBinary} --config-file ${stateConfig}";
  agsReload = "${pkgs.systemd}/bin/systemctl --user --no-block try-restart framework-ags.service";

  ccCtl = pkgs.writeShellScript "framework-cc-ctl" ''
    set -euo pipefail
    export LC_ALL=C
    nmcli=${pkgs.networkmanager}/bin/nmcli
    bluetoothctl=${pkgs.bluez}/bin/bluetoothctl
    makoctl=${unstablePkgs.mako}/bin/makoctl
    darkman=${pkgs.darkman}/bin/darkman
    grep=${pkgs.gnugrep}/bin/grep
    systemctl=${pkgs.systemd}/bin/systemctl
    state() {
      case "$1" in
        wifi) [ "$("$nmcli" -t radio wifi 2>/dev/null)" = enabled ] && echo on || echo off ;;
        bt) "$bluetoothctl" show 2>/dev/null | "$grep" -q "Powered: yes" && echo on || echo off ;;
        dnd) "$makoctl" mode 2>/dev/null | "$grep" -q "do-not-disturb" && echo on || echo off ;;
        dark) [ "$("$darkman" get 2>/dev/null)" = dark ] && echo on || echo off ;;
        lid) "$systemctl" --user is-active --quiet framework-lid-inhibit.service && echo off || echo on ;;
        *) exit 2 ;;
      esac
    }
    case "''${1:-}" in
      state) state "''${2:-}" ;;
      toggle)
        case "''${2:-}" in
          wifi) if [ "$(state wifi)" = on ]; then "$nmcli" radio wifi off; else "$nmcli" radio wifi on; fi ;;
          bt) if [ "$(state bt)" = on ]; then "$bluetoothctl" power off; else "$bluetoothctl" power on; fi ;;
          dnd) "$makoctl" mode -t do-not-disturb ;;
          dark) "$darkman" toggle ;;
          lid)
            if [ "$(state lid)" = off ]; then
              "$systemctl" --user stop framework-lid-inhibit.service
            else
              "$systemctl" --user start framework-lid-inhibit.service
            fi ;;
          *) exit 2 ;;
        esac
        ;;
      *) exit 2 ;;
    esac
  '';

  ccCmd = pkgs.writeShellScript "framework-cc-cmd" ''
    set -euo pipefail
    case "''${1:-}" in
      lock) exec ${lockScreen} lock --daemonize ;;
      suspend) exec ${pkgs.systemd}/bin/systemctl suspend ;;
      reboot) exec ${pkgs.systemd}/bin/systemctl reboot ;;
      shutdown) exec ${pkgs.systemd}/bin/systemctl poweroff ;;
      logout) exec ${unstablePkgs.niri}/bin/niri msg action quit ;;
      clear-notifications) exec ${unstablePkgs.mako}/bin/makoctl dismiss --all ;;
      open-bluetooth) exec ${pkgs.overskride}/bin/overskride ;;
      open-audio) exec ${pkgs.pavucontrol}/bin/pavucontrol ;;
      *) exit 2 ;;
    esac
  '';

  ccWifi = pkgs.writeShellScript "framework-cc-wifi" ''
    set -euo pipefail
    export LC_ALL=C
    nmcli=${pkgs.networkmanager}/bin/nmcli
    jq=${pkgs.jq}/bin/jq
    awk=${pkgs.gawk}/bin/awk
    scan() {
      known=$("$nmcli" -t -f NAME connection show)
      "$nmcli" -m multiline -f ACTIVE,SIGNAL,SECURITY,SSID device wifi list \
      | "$awk" 'function val(s){sub(/^[A-Z]*:[ \t]*/,"",s);sub(/[ \t]+$/,"",s);return s}
          /^ACTIVE:/{a=val($0)} /^SIGNAL:/{sig=val($0)} /^SECURITY:/{sec=val($0)}
          /^SSID:/{ssid=val($0); printf "%s\t%s\t%s\t%s\n",a,sig,sec,ssid}' \
      | "$jq" -R -s -c --arg known "$known" '
          ($known | split("\n") | map(select(length>0))) as $k
          | split("\n") | map(select(length>0))
          | map(split("\t") | {active:(.[0]=="yes"), signal:(.[1]|tonumber? // 0), security:(if (.[2]=="" or .[2]=="--") then "" else .[2] end), ssid:.[3]})
          | map(select(.ssid != "" and .ssid != "--"))
          | map(.known = (.ssid as $s | $k | index($s) != null))
          | group_by(.ssid) | map(. as $g | ($g | max_by(.signal)) + {active: ($g | any(.[]; .active))})
          | sort_by([(if .active then 0 else 1 end), (-.signal)])
        '
    }
    case "''${1:-}" in
      scan) scan ;;
      rescan) "$nmcli" device wifi rescan >/dev/null; scan ;;
      connect)
        ssid="''${2:?SSID required}"
        if "$nmcli" -t -f NAME connection show | ${pkgs.gnugrep}/bin/grep -Fxq -- "$ssid"; then
          "$nmcli" connection up id "$ssid" >/dev/null
        elif [ -n "''${3:-}" ]; then
          "$nmcli" device wifi connect "$ssid" password "$3" >/dev/null
        else
          "$nmcli" device wifi connect "$ssid" >/dev/null
        fi
        scan ;;
      disconnect)
        dev=$("$nmcli" -t -f DEVICE,TYPE device | "$awk" -F: '$2=="wifi"{print $1; exit}')
        [ -z "$dev" ] || "$nmcli" device disconnect "$dev" >/dev/null
        scan ;;
      *) exit 2 ;;
    esac
  '';
in
{
  _module.args = {
    shellNotificationMarkRead = "${stateCommand} notifications mark-read";
    shellNotificationMarkUnread = "${stateCommand} notifications mark-unread";
    inherit agsReload;
    shellState = stateBinary;
    shellStateConfig = stateConfig;
  };

  home.packages = [ ags ];

  xdg.configFile = {
    "ags/app.js".source = "${shellAssets}/app.js";
    "ags/style-light.css".source = "${shellAssets}/style-light.css";
    "ags/style-dark.css".source = "${shellAssets}/style-dark.css";
    "ags/config.json".text = builtins.toJSON {
      inherit stateBinary;
      stateConfig = toString stateConfig;
      ccCtl = toString ccCtl;
      ccCmd = toString ccCmd;
      ccWifi = toString ccWifi;
      icons = builtins.mapAttrs (_: toString) icons;
    };
  };

  systemd.user.services.framework-ags = {
    Unit = {
      Description = "Framework AGS shell";
      ConditionEnvironment = [ "WAYLAND_DISPLAY" ];
      ConditionPathExists = "${agsConfigDir}/app.js";
      PartOf = [ "graphical-session.target" ];
      After = [
        "niri.service"
        "graphical-session.target"
        "tray.target"
      ];
      Wants = [ "tray.target" ];
    };
    Service = {
      Type = "simple";
      Environment = [
        "HOME=${config.home.homeDirectory}"
        "XDG_CONFIG_HOME=${config.home.homeDirectory}/.config"
        "GDK_BACKEND=wayland"
      ];
      WorkingDirectory = agsConfigDir;
      ExecStart = "${ags}/bin/ags run ${agsConfigDir}/app.js";
      Restart = "on-failure";
      RestartSec = 2;
      KillMode = "control-group";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Session-scoped, explicitly toggled: no stale PID files or detached inhibitors.
  systemd.user.services.framework-lid-inhibit = {
    Unit = {
      Description = "Temporarily inhibit lid sleep from the Framework control center";
      PartOf = [ "graphical-session.target" ];
    };
    Service.ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=handle-lid-switch --who=framework-ags --why=Control-center-lid-toggle --mode=block ${pkgs.coreutils}/bin/sleep infinity";
  };
}
