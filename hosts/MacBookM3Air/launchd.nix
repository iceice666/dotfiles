{...}: {
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
  };
}
