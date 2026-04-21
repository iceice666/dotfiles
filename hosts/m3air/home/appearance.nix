{
  homeDirectory,
  lib,
  pkgs,
  ...
}:

let
  bundleIdentifier = "com.iceice666.appearance-scheduler";
  bundleName = "Appearance Scheduler.app";
  executableName = "appearance-scheduler";

  infoPlist = pkgs.writeText "appearance-scheduler-Info.plist" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key>
      <string>en</string>
      <key>CFBundleExecutable</key>
      <string>${executableName}</string>
      <key>CFBundleIdentifier</key>
      <string>${bundleIdentifier}</string>
      <key>CFBundleInfoDictionaryVersion</key>
      <string>6.0</string>
      <key>CFBundleName</key>
      <string>Appearance Scheduler</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
      <key>CFBundleShortVersionString</key>
      <string>1.0</string>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>LSUIElement</key>
      <true/>
      <key>NSLocationUsageDescription</key>
      <string>Uses your Mac location to switch appearance 30 minutes after sunrise and 30 minutes before sunset.</string>
      <key>NSLocationAlwaysUsageDescription</key>
      <string>Uses your Mac location to switch appearance 30 minutes after sunrise and 30 minutes before sunset.</string>
      <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
      <string>Uses your Mac location to switch appearance 30 minutes after sunrise and 30 minutes before sunset.</string>
    </dict>
    </plist>
  '';

in
{
  home.activation.appearanceScheduler = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    bundle_dir="$HOME/Applications/${bundleName}"
    contents_dir="$bundle_dir/Contents"
    macos_dir="$contents_dir/MacOS"
    executable_path="$macos_dir/${executableName}"

    mkdir -p "$macos_dir"
    install -m 644 ${infoPlist} "$contents_dir/Info.plist"

    /usr/bin/swiftc \
      -framework CoreLocation \
      -framework Foundation \
      -Xlinker -sectcreate \
      -Xlinker __TEXT \
      -Xlinker __info_plist \
      -Xlinker "$contents_dir/Info.plist" \
      ${./appearance-scheduler.swift} \
      -o "$executable_path"
  '';

  launchd.agents."appearance-scheduler" = {
    enable = true;
    config = {
      Label = bundleIdentifier;
      ProgramArguments = [
        "/usr/bin/open"
        "-a"
        "${homeDirectory}/Applications/${bundleName}"
      ];
      RunAtLoad = true;
      StartInterval = 600;

      StandardOutPath = "/tmp/${bundleIdentifier}.log";
      StandardErrorPath = "/tmp/${bundleIdentifier}.err";
    };
  };
}
