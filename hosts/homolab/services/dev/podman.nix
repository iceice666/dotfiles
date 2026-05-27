{ ... }:

{
  virtualisation.podman = {
    enable = true;

    # Docker-compatible socket for tools that expect the Docker API.
    # Access is restricted to the podman group; iceice666 is NOT a member.
    dockerSocket.enable = true;
    dockerCompat = true;
  };
}
