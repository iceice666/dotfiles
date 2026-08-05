{ pkgs, ... }:

{
  launchd.agents."appearance-scheduler" = {
    enable = true;
    config = {
      Label = "com.iceice666.appearance-scheduler";
      ProgramArguments = [ "${pkgs.appearance-scheduler}/bin/appearance-scheduler" ];
      RunAtLoad = true;
      StartInterval = 600;

      StandardOutPath = "/tmp/com.iceice666.appearance-scheduler.log";
      StandardErrorPath = "/tmp/com.iceice666.appearance-scheduler.err";
    };
  };
}
