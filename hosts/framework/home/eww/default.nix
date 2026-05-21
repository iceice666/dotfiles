{
  config,
  lib,
  pkgs,
  unstablePkgs,
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
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000000"><path d="M4 7a3 3 0 0 1 3-3h10a3 3 0 1 1 0 6H7a3 3 0 0 1-3-3zm3-1a1 1 0 1 0 0 2h10a1 1 0 1 0 0-2zM4 17a3 3 0 1 1 3 3h10a3 3 0 1 1 0-6H7a3 3 0 0 1-3 3zm3-1a1 1 0 1 0 0 2h10a1 1 0 1 0 0-2z"/></svg>
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

  yuckFiles = [
    ./yuck/state.yuck
    ./yuck/bar.yuck
    ./yuck/app-strip.yuck
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
