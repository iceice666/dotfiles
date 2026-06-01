{ ... }:

{
  virtualisation.containers.storage.settings.storage = {
    driver = "overlay";
    graphroot = "/mnt/storage/podman";
    runroot = "/run/containers/storage";
  };

  virtualisation.podman = {
    enable = true;

    # Docker-compatible socket for tools that expect the Docker API.
    # Access is restricted to the podman group; iceice666 is NOT a member.
    dockerSocket.enable = true;
    dockerCompat = true;
  };

  systemd.tmpfiles.rules = [
    "d /mnt/storage/podman 0700 root root - -"
  ];
}
