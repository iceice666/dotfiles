{ pkgs, unstablePkgs, ... }:

# Workstation-only CLI tools. They stay off the Raspberry Pi servers because the
# repo's Node overlay changes their build-time closures, so cache.nixos.org has no
# matching aarch64 outputs: full ffmpeg drags in SDL/pipewire/gtk4/gstreamer, and
# bitwarden-cli builds against the pinned Node 22 runtime.
{
  home.packages = [
    pkgs.ffmpeg
    unstablePkgs.bitwarden-cli
  ];
}
