{
  config,
  inputs,
  lib,
  pkgs,
  unstablePkgs,
  lockScreen,
  themegenCache,
  ...
}:

let
  agsConfigDir = "${config.home.homeDirectory}/.config/ags";
  agsPackages = inputs.ags.packages.${pkgs.stdenv.hostPlatform.system};
  ags = agsPackages.ags.override {
    extraPackages = [
      agsPackages.notifd
      agsPackages.tray
    ];
  };
  icons = import ./icons.nix { inherit pkgs; };
  shellAssets =
    pkgs.runCommand "framework-ags-assets"
      {
        nativeBuildInputs = [
          ags
          pkgs.dart-sass
          pkgs.gobject-introspection
          pkgs.wrapGAppsHook3
        ];
        buildInputs = [
          pkgs.gjs
          pkgs.gtk4
          pkgs.libadwaita
          agsPackages.io
          agsPackages.astal4
          agsPackages.notifd
          agsPackages.tray
        ];
      }
      ''
        mkdir -p "$out" work
        cp ${./app.tsx} work/app.tsx
        cp ${./state.ts} work/state.ts
        cp ${./control-center.tsx} work/control-center.tsx
        cp ${./notifications.tsx} work/notifications.tsx
        ags bundle work/app.tsx "$out/app.js"
        # Bundle launchers need the GI/runtime environment independently of the CLI.
        mkdir -p "$out/bin"
        cat > "$out/bin/framework-ags" <<'EOF'
        #!${pkgs.runtimeShell}
        exec "$@"
        EOF
        chmod +x "$out/bin/framework-ags"
        gappsWrapperArgsHook
        wrapGApp "$out/bin/framework-ags"
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
        pavucontrol = "${pkgs.pavucontrol}/bin/pavucontrol";
      };
      icons = builtins.mapAttrs (_: toString) icons;
    }
  );
  agsReload = "${pkgs.systemd}/bin/systemctl --user --no-block try-restart framework-ags.service";

  ccCtl = pkgs.writeShellScript "framework-cc-ctl" ''
    set -euo pipefail
    export LC_ALL=C
    nmcli=${pkgs.networkmanager}/bin/nmcli
    bluetoothctl=${pkgs.bluez}/bin/bluetoothctl
    darkman=${pkgs.darkman}/bin/darkman
    grep=${pkgs.gnugrep}/bin/grep
    systemctl=${pkgs.systemd}/bin/systemctl
    state() {
      case "$1" in
        wifi) [ "$("$nmcli" -t radio wifi 2>/dev/null)" = enabled ] && echo on || echo off ;;
        bt) "$bluetoothctl" show 2>/dev/null | "$grep" -q "Powered: yes" && echo on || echo off ;;
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
      hibernate) exec ${pkgs.systemd}/bin/systemctl hibernate ;;
      reboot) exec ${pkgs.systemd}/bin/systemctl reboot ;;
      shutdown) exec ${pkgs.systemd}/bin/systemctl poweroff ;;
      logout) exec ${unstablePkgs.niri}/bin/niri msg action quit ;;
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
    inherit agsReload;
    shellState = stateBinary;
    shellStateConfig = stateConfig;
  };

  home.packages = [ ags ];

  # AGS owns org.freedesktop.Notifications through AstalNotifd; early senders
  # activate the shell unit instead of failing before the session is ready.
  xdg.dataFile."dbus-1/services/org.freedesktop.Notifications.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.Notifications
    Exec=${pkgs.coreutils}/bin/false
    SystemdService=framework-ags.service
  '';

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
      # AGS 3 bundles are executable launchers, not input for `ags run`.
      ExecStart = "${shellAssets}/bin/framework-ags ${agsConfigDir}/app.js";
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
