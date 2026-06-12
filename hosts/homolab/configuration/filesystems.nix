{ ... }:

{
  # Shared NTFS disk accessible from both NixOS and Windows.
  # Prerequisites:
  #   - Format the disk as NTFS in Windows and set the volume label to "Shared"
  #     (or change the label here to match what you chose).
  #   - Disable Windows Fast Startup: `powercfg /h off` in an admin PowerShell.
  #   - Do NOT hibernate while the disk is in use from the other OS.
  fileSystems."/mnt/shared" = {
    device = "/dev/disk/by-label/Shared";
    # ntfs3 until linuxPackages_latest picks up 7.1; change to "ntfs" after.
    fsType = "ntfs3";
    options = [
      "uid=1000"
      "gid=100"
      "umask=022"
      "windows_names"
      "noatime"
      "nofail"
    ];
  };
}
