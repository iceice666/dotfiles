{
  config,
  lib,
  pkgs,
  unstablePkgs,
  lockScreen,
  ...
}:

let
  ewwConfigDir = "${config.home.homeDirectory}/.config/eww";

  icons = {
    appPlaceholder = pkgs.writeText "eww-app-placeholder.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#8a8a8a" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="4.5" y="4.5" width="15" height="15" rx="3.5"/><path d="M8.5 12h7"/><path d="M12 8.5v7"/></svg>
    '';
    batteryAc = pkgs.writeText "eww-battery-ac.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M7 2h3v5h4V2h3v5h2v4a7 7 0 0 1-6 6.92V22h-2v-4.08A7 7 0 0 1 5 11V7h2z"/></svg>
    '';
    batteryBat = pkgs.writeText "eww-battery-bat.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M20 4c-6.6.15-11.4 2.4-14.05 6.25C3.6 13.65 3.4 18 3.4 18H2v2h9v-2H5.45c.08-.92.5-3.95 2.2-6.4C9.6 8.8 13 7 18 6.35c-.35 2.95-1.18 5.05-2.52 6.4-1.25 1.25-2.85 1.85-4.98 1.85h-.7l-1.2 2H10.5c2.65 0 4.78-.82 6.4-2.45C18.98 12.08 20 8.75 20 4z"/></svg>
    '';
    batteryCharging = pkgs.writeText "eww-battery-charging.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M10 2h4v2h-4z"/><path d="M8 5h8a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zm4 3-3 7h3l-1 5 5-8h-3l2-4z"/></svg>
    '';
    batteryNormal = pkgs.writeText "eww-battery-normal.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M10 2h4v2h-4z"/><path d="M8 5h8a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zm2 8v6h4v-6z"/></svg>
    '';
    batteryUnknown = pkgs.writeText "eww-battery-unknown.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M10 2h4v2h-4z"/><path d="M8 5h8a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zm3 4v2h2V9zm0 4v5h2v-5z"/></svg>
    '';
    brightness = pkgs.writeText "eww-brightness.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M11 1h2v4h-2zM11 19h2v4h-2zM1 11h4v2H1zM19 11h4v2h-4zM4.22 2.8 7.05 5.64 5.64 7.05 2.8 4.22zM16.95 18.36l1.41-1.41 2.84 2.83-1.42 1.42zM2.8 19.78l2.84-2.83 1.41 1.41-2.83 2.84zM16.95 5.64l2.83-2.84 1.42 1.42-2.84 2.83zM12 7a5 5 0 1 1 0 10 5 5 0 0 1 0-10z"/></svg>
    '';
    controlCenter = pkgs.writeText "eww-control-center.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><rect x="3" y="3" width="10" height="7" rx="3.5"/><rect x="15" y="3" width="6" height="7" rx="2.5"/><rect x="3" y="13" width="7" height="8" rx="2.5"/><rect x="13" y="13" width="8" height="3" rx="1.5"/><rect x="13" y="19" width="8" height="3" rx="1.5"/></svg>
    '';
    media = pkgs.writeText "eww-media.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M5 4h2v16H5zM9 5l10 7-10 7z"/></svg>
    '';
    micActive = pkgs.writeText "eww-mic-active.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11h2a5 5 0 0 0 10 0h2a7 7 0 0 1-6 6.92V21h4v2H7v-2h4v-3.08A7 7 0 0 1 5 11z"/></svg>
    '';
    network = pkgs.writeText "eww-network.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M12 18.5 8.5 15a5 5 0 0 1 7 0z"/><path d="m5.65 12.15 1.42 1.42a7 7 0 0 1 9.86 0l1.42-1.42a9 9 0 0 0-12.7 0z"/><path d="m2.8 9.3 1.42 1.4a11 11 0 0 1 15.56 0l1.42-1.4a13 13 0 0 0-18.4 0z"/><circle cx="12" cy="20" r="1.5"/></svg>
    '';
    micMuted = pkgs.writeText "eww-mic-muted.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M4.7 3.3 21 19.6 19.6 21l-3.5-3.5A7 7 0 0 1 13 17.92V21h4v2H7v-2h4v-3.08A7 7 0 0 1 5 11h2a5 5 0 0 0 7.6 4.26l-2.1-2.1A3 3 0 0 1 9 10.5V6.7l-5.7-5.7z"/><path d="M15 11.7V6a3 3 0 0 0-4.88-2.34l6.1 6.1A5 5 0 0 1 15 11.7zM17 11h2a6.95 6.95 0 0 1-1.04 3.65l-1.5-1.5A5 5 0 0 0 17 11z"/></svg>
    '';
    notification = pkgs.writeText "eww-notification.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M12 2a2 2 0 0 1 2 2v.3A6 6 0 0 1 18 10v3l2 3v2H4v-2l2-3v-3a6 6 0 0 1 4-5.7V4a2 2 0 0 1 2-2zM9 20h6a3 3 0 0 1-6 0z"/></svg>
    '';
    speakerHigh = pkgs.writeText "eww-speaker-high.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M3 10v4h4l6 5V5L7 10z"/><path d="M16 8v8a4.5 4.5 0 0 0 0-8z"/><path d="M18.5 5.5v13a8 8 0 0 0 0-13z"/></svg>
    '';
    speakerLow = pkgs.writeText "eww-speaker-low.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M3 10v4h4l6 5V5L7 10z"/><path d="M16 8v8a4.5 4.5 0 0 0 0-8z"/></svg>
    '';
    speakerMuted = pkgs.writeText "eww-speaker-muted.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M3 10v4h4l6 5V5L7 10z"/><path d="m16 8 5 8h-3l-2-3-2 3h-3l4-6-4-6h3l2 3 2-3h3z"/></svg>
    '';
    tray = pkgs.writeText "eww-tray.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M4 5h16v4H4z"/><path d="M4 11h7v8H4z"/><path d="M13 11h7v8h-7z"/></svg>
    '';
    bluetooth = pkgs.writeText "eww-bluetooth.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M17.71 7.71 12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29zM13 5.83l1.88 1.88L13 9.59V5.83zm1.88 10.46L13 18.17v-3.76l1.88 1.88z"/></svg>
    '';
    clear = pkgs.writeText "eww-clear.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M9 3h6l1 2h4v2H4V5h4l1-2zM6 8h12l-1 13H7L6 8z"/></svg>
    '';
    darkMode = pkgs.writeText "eww-dark-mode.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
    '';
    lock = pkgs.writeText "eww-lock.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M12 2a5 5 0 0 0-5 5v3H6a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-9a1 1 0 0 0-1-1h-1V7a5 5 0 0 0-5-5zm-3 8V7a3 3 0 0 1 6 0v3H9z"/></svg>
    '';
    logout = pkgs.writeText "eww-logout.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M10 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h5v-2H5V5h5V3zm7 5-1.41 1.41L17.17 11H9v2h8.17l-1.58 1.59L17 16l4-4-4-4z"/></svg>
    '';
    reboot = pkgs.writeText "eww-reboot.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M12 4V1L8 5l4 4V6a6 6 0 1 1-6 6H4a8 8 0 1 0 8-8z"/></svg>
    '';
    shutdown = pkgs.writeText "eww-shutdown.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M11 2h2v10h-2V2zM7.8 5.2 6.4 6.6a7 7 0 1 0 11.2 0l-1.4-1.4a5 5 0 1 1-8.4 0z"/></svg>
    '';
    suspend = pkgs.writeText "eww-suspend.svg" ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M8 5h3v14H8zM13 5h3v14h-3z"/></svg>
    '';
  };

  stateBinary = lib.getExe pkgs.framework-eww-state;
  stateConfig = pkgs.writeText "framework-eww-state-config.json" (
    builtins.toJSON {
      inherit ewwConfigDir;
      home = config.home.homeDirectory;
      preferredInterface = "wlp192s0";
      commands = {
        eww = "${pkgs.eww}/bin/eww";
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
        systemctl = "${pkgs.systemd}/bin/systemctl";
      };
      icons = builtins.mapAttrs (_: toString) icons;
    }
  );
  stateCommand = "${stateBinary} --config-file ${stateConfig}";
  stateCommands = {
    changeMicVolume = "${stateCommand} audio volume mic";
    changeSpeakerVolume = "${stateCommand} audio volume speaker";
    focusWindow = "${stateCommand} focus-window";
    notificationAction = "${stateCommand} notifications action";
    notificationMarkRead = "${stateCommand} notifications mark-read";
    notificationMarkUnread = "${stateCommand} notifications mark-unread";
    niriGroupsSeed = "${stateCommand} seed-niri-groups";
    nextMedia = "${stateCommand} media next";
    openPavucontrol = "${stateCommand} open-pavucontrol";
    playPauseMedia = "${stateCommand} media play-pause";
    previousMedia = "${stateCommand} media previous";
    reloadEww = "${stateCommand} reload";
    setBrightness = "${stateCommand} brightness set";
    setMicVolume = "${stateCommand} audio set mic";
    setSpeakerVolume = "${stateCommand} audio set speaker";
    toggleMic = "${stateCommand} audio toggle mic";
    toggleSpeaker = "${stateCommand} audio toggle speaker";
  };

  ccCtl = pkgs.writeShellScript "framework-cc-ctl" ''
    set -u
    nmcli=${pkgs.networkmanager}/bin/nmcli
    bluetoothctl=${pkgs.bluez}/bin/bluetoothctl
    makoctl=${unstablePkgs.mako}/bin/makoctl
    darkman=${pkgs.darkman}/bin/darkman
    grep=${pkgs.gnugrep}/bin/grep

    state() {
      case "$1" in
        wifi) [ "$("$nmcli" -t radio wifi 2>/dev/null)" = enabled ] && echo on || echo off ;;
        bt) "$bluetoothctl" show 2>/dev/null | "$grep" -q "Powered: yes" && echo on || echo off ;;
        dnd) "$makoctl" mode 2>/dev/null | "$grep" -q "do-not-disturb" && echo on || echo off ;;
        dark) [ "$("$darkman" get 2>/dev/null)" = dark ] && echo on || echo off ;;
        *) echo off ;;
      esac
    }

    toggle() {
      case "$1" in
        wifi) if [ "$(state wifi)" = on ]; then "$nmcli" radio wifi off; else "$nmcli" radio wifi on; fi ;;
        bt) if [ "$(state bt)" = on ]; then "$bluetoothctl" power off; else "$bluetoothctl" power on; fi ;;
        dnd) "$makoctl" mode -t do-not-disturb ;;
        dark) "$darkman" toggle ;;
      esac
    }

    case "''${1:-}" in
      state) state "''${2:-}" ;;
      toggle)
        toggle "''${2:-}" >/dev/null 2>&1 || true
        ${pkgs.coreutils}/bin/sleep 0.2
        ${pkgs.eww}/bin/eww --config ${ewwConfigDir} update "cc_''${2:-}=$(state "''${2:-}")" >/dev/null 2>&1 || true
        ;;
    esac
  '';

  ccCmd = pkgs.writeShellScript "framework-cc-cmd" ''
    set -u
    case "''${1:-}" in
      lock) exec ${lockScreen} lock --daemonize ;;
      suspend) exec ${pkgs.systemd}/bin/systemctl suspend ;;
      reboot) exec ${pkgs.systemd}/bin/systemctl reboot ;;
      shutdown) exec ${pkgs.systemd}/bin/systemctl poweroff ;;
      logout) exec ${unstablePkgs.niri}/bin/niri msg action quit ;;
      clear-notifications) exec ${unstablePkgs.mako}/bin/makoctl dismiss --all ;;
      toggle)
        ${pkgs.eww}/bin/eww --config ${ewwConfigDir} update cc_view=home >/dev/null 2>&1 || true
        exec ${pkgs.eww}/bin/eww --config ${ewwConfigDir} open --toggle --arg monitor="''${2:-}" control-center ;;
      open-bluetooth) exec ${pkgs.overskride}/bin/overskride ;;
      open-audio) exec ${pkgs.pavucontrol}/bin/pavucontrol ;;
    esac
  '';

  ccWifi = pkgs.writeShellScript "framework-cc-wifi" ''
    set -u
    nmcli=${pkgs.networkmanager}/bin/nmcli
    jq=${pkgs.jq}/bin/jq
    awk=${pkgs.gawk}/bin/awk
    eww="${pkgs.eww}/bin/eww --config ${ewwConfigDir}"

    scan() {
      known=$("$nmcli" -t -f NAME connection show 2>/dev/null)
      "$nmcli" -m multiline -f ACTIVE,SIGNAL,SECURITY,SSID device wifi list 2>/dev/null \
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

    wifi_iface() {
      "$nmcli" -t -f DEVICE,TYPE device 2>/dev/null | "$awk" -F: '$2=="wifi"{print $1; exit}'
    }

    refresh() {
      out=$(scan); [ -n "$out" ] || out="[]"
      $eww update wifi_networks="$out" >/dev/null 2>&1 || true
    }

    case "''${1:-}" in
      scan) out=$(scan); [ -n "$out" ] && printf '%s' "$out" || printf '[]' ;;
      rescan)
        "$nmcli" device wifi rescan >/dev/null 2>&1 || true
        ${pkgs.coreutils}/bin/sleep 1
        refresh
        ;;
      connect)
        ssid="''${2:-}"
        [ -n "$ssid" ] || exit 0
        pw=$($eww get wifi_password 2>/dev/null || true)
        if "$nmcli" -t -f NAME connection show 2>/dev/null | ${pkgs.gnugrep}/bin/grep -Fxq "$ssid"; then
          "$nmcli" connection up id "$ssid" >/dev/null 2>&1 || true
        elif [ -n "$pw" ]; then
          "$nmcli" device wifi connect "$ssid" password "$pw" >/dev/null 2>&1 || true
        else
          "$nmcli" device wifi connect "$ssid" >/dev/null 2>&1 || true
        fi
        $eww update wifi_password= wifi_pw_target= >/dev/null 2>&1 || true
        ${pkgs.coreutils}/bin/sleep 1
        refresh
        ;;
      disconnect)
        dev=$(wifi_iface)
        [ -n "$dev" ] && "$nmcli" device disconnect "$dev" >/dev/null 2>&1 || true
        ${pkgs.coreutils}/bin/sleep 1
        refresh
        ;;
    esac
  '';

  yuckFiles = [
    ./yuck/state.yuck
    ./yuck/bar.yuck
    ./yuck/app-strip.yuck
    ./yuck/control-center.yuck
  ];

  ewwYuck =
    builtins.replaceStrings
      [
        "@batteryUnknown@"
        "@brightnessIcon@"
        "@changeMicVolume@"
        "@changeSpeakerVolume@"
        "@controlCenterIcon@"
        "@focusWindow@"
        "@mediaIcon@"
        "@micActive@"
        "@networkIcon@"
        "@nextMedia@"
        "@niriGroupsSeed@"
        "@notificationAction@"
        "@notificationIcon@"
        "@openPavucontrol@"
        "@playPauseMedia@"
        "@previousMedia@"
        "@setBrightness@"
        "@setMicVolume@"
        "@setSpeakerVolume@"
        "@speakerHigh@"
        "@trayIcon@"
        "@toggleMic@"
        "@toggleSpeaker@"
        "@ccCmd@"
        "@ccCtl@"
        "@ccWifi@"
        "@iconBluetooth@"
        "@iconClear@"
        "@iconDarkMode@"
        "@iconLock@"
        "@iconLogout@"
        "@iconReboot@"
        "@iconShutdown@"
        "@iconSuspend@"
      ]
      [
        (toString icons.batteryUnknown)
        (toString icons.brightness)
        stateCommands.changeMicVolume
        stateCommands.changeSpeakerVolume
        (toString icons.controlCenter)
        stateCommands.focusWindow
        (toString icons.media)
        (toString icons.micActive)
        (toString icons.network)
        stateCommands.nextMedia
        stateCommands.niriGroupsSeed
        stateCommands.notificationAction
        (toString icons.notification)
        stateCommands.openPavucontrol
        stateCommands.playPauseMedia
        stateCommands.previousMedia
        stateCommands.setBrightness
        stateCommands.setMicVolume
        stateCommands.setSpeakerVolume
        (toString icons.speakerHigh)
        (toString icons.tray)
        stateCommands.toggleMic
        stateCommands.toggleSpeaker
        (toString ccCmd)
        (toString ccCtl)
        (toString ccWifi)
        (toString icons.bluetooth)
        (toString icons.clear)
        (toString icons.darkMode)
        (toString icons.lock)
        (toString icons.logout)
        (toString icons.reboot)
        (toString icons.shutdown)
        (toString icons.suspend)
      ]
      (builtins.concatStringsSep "\n\n" (map builtins.readFile yuckFiles));
in
{
  _module.args = {
    ewwNotificationMarkRead = stateCommands.notificationMarkRead;
    ewwNotificationMarkUnread = stateCommands.notificationMarkUnread;
    ewwReload = stateCommands.reloadEww;
    ewwState = stateBinary;
    ewwStateConfig = stateConfig;
  };

  programs.eww.enable = true;

  xdg.configFile = {
    "eww/eww.yuck".text = ewwYuck;
    "eww/eww.scss" = {
      source = ./eww.scss;
      force = true;
    };
  };

  systemd.user.services.framework-eww = {
    Unit = {
      Description = "Framework Eww daemon";
      ConditionEnvironment = [ "WAYLAND_DISPLAY" ];
      ConditionPathExists = "${ewwConfigDir}/eww.yuck";
      PartOf = [ "graphical-session.target" ];
      After = [
        "niri.service"
        "graphical-session.target"
        "tray.target"
      ];
      Wants = [
        "graphical-session.target"
        "tray.target"
      ];
    };

    Service = {
      Type = "simple";
      Environment = [
        "HOME=${config.home.homeDirectory}"
        "XDG_CONFIG_HOME=${config.home.homeDirectory}/.config"
      ];
      WorkingDirectory = ewwConfigDir;
      ExecStart = "${pkgs.eww}/bin/eww --force-wayland --config ${ewwConfigDir} --no-daemonize daemon";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.framework-eww-bars = {
    Unit = {
      Description = "Framework Eww state daemon and bar windows";
      ConditionEnvironment = [ "WAYLAND_DISPLAY" ];
      ConditionPathExists = "${ewwConfigDir}/eww.yuck";
      PartOf = [ "graphical-session.target" ];
      After = [
        "framework-eww.service"
        "niri.service"
        "graphical-session.target"
      ];
      Requires = [ "framework-eww.service" ];
    };

    Service = {
      Type = "simple";
      Environment = [
        "HOME=${config.home.homeDirectory}"
        "XDG_CONFIG_HOME=${config.home.homeDirectory}/.config"
      ];
      WorkingDirectory = ewwConfigDir;
      ExecStart = "${stateCommand} daemon";
      Restart = "on-failure";
      RestartSec = 2;
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
