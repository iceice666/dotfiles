{
  username,
  homeDirectory,
  ...
}: {
  launchd.agents = {
    karabiner-driver = {
      serviceConfig = {
        Label = "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice";
        RunAtLoad = true;
        KeepAlive = true;
        UserName = "root";
        Program = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon";
      };
    };

    kanata = {
      serviceConfig = {
        Label = "kanata";
        RunAtLoad = true;
        KeepAlive = true;
        UserName = "root";
        Program = "/etc/profiles/per-user/${username}/bin/kanata";
        ProgramArguments = [
          "-c"
          "${homeDirectory}/Library/Application Support/kanata/kanata.kbd"
        ];
      };
    };
  };
}
