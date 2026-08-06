{ pkgs, ... }:

{
  # SleepGuard.app is built and installed imperatively (`just sleepguard-install`) —
  # see pkgs/sleepguard/README.md for why it isn't a Nix derivation.
  home.packages = [ pkgs.xcodegen ];

  launchd.agents."sleepguard" = {
    enable = true;
    config = {
      Label = "com.iceice666.sleepguard";
      ProgramArguments = [ "/Applications/SleepGuard.app/Contents/MacOS/SleepGuard" ];
      RunAtLoad = true;
      KeepAlive = true;

      StandardOutPath = "/tmp/com.iceice666.sleepguard.log";
      StandardErrorPath = "/tmp/com.iceice666.sleepguard.err";
    };
  };
}
