{ pkgs, ... }:

let
  ewwConfigDir = "$HOME/.config/eww";
  scripts = import ./scripts.nix { inherit pkgs ewwConfigDir; };

  yuckFiles = [
    ./yuck/state.yuck
    ./yuck/bar.yuck
    ./yuck/app-strip.yuck
  ];

  ewwYuck =
    builtins.replaceStrings
      [
        "@audioStatus@"
        "@batteryStatus@"
        "@bluetoothStatus@"
        "@datetimeStatus@"
        "@focusWindow@"
        "@mediaStatus@"
        "@niriState@"
        "@notificationAction@"
        "@notificationsStatus@"
        "@pavucontrol@"
        "@perfStatus@"
        "@toggleMic@"
      ]
      [
        (toString scripts.audioStatus)
        (toString scripts.batteryStatus)
        (toString scripts.bluetoothStatus)
        (toString scripts.datetimeStatus)
        (toString scripts.focusWindow)
        (toString scripts.mediaStatus)
        (toString scripts.niriState)
        (toString scripts.notificationAction)
        (toString scripts.notificationsStatus)
        "${pkgs.pavucontrol}/bin/pavucontrol"
        (toString scripts.perfStatus)
        "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
      ]
      (builtins.concatStringsSep "\n\n" (map builtins.readFile yuckFiles));
in
{
  _module.args.ewwLaunch = scripts.launchEww;

  home.packages = [ pkgs.eww ];

  xdg.configFile = {
    "eww/eww.yuck".text = ewwYuck;
    "eww/eww.scss".source = ./eww.scss;
  };
}
