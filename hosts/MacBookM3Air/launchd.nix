{...}: {
  launchd.daemons = {
    karabiner-driverkit = {
      serviceConfig = {
        Label = "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice";
        RunAtLoad = true;
        KeepAlive = true;
        UserName = "root";
        Program = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon";
      };
    };

    karabiner-device-manager = {
      serviceConfig = {
        Label = "org.pqrs.Karabiner-VirtualHIDDevice-Manager";
        RunAtLoad = true;
        KeepAlive = true;
        UserName = "root";
        ProgramArgments = [
          "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager" "activate"
        ];
      };
    };
  };
}
