{ config, pkgs, ... }:

let
  runtimeDirectory = "gce-dns";
  authKeyFile = "/run/${runtimeDirectory}/tailscale-auth-key";
  metadataUrl = "http://metadata.google.internal/computeMetadata/v1/instance/attributes/tailscale-auth-key";
in
{
  systemd.services.gce-dns-tailscale-auth-key = {
    description = "Fetch gce-dns Tailscale auth key from GCE metadata";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    before = [ "tailscaled-autoconnect.service" ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RuntimeDirectory = runtimeDirectory;
      RuntimeDirectoryMode = "0700";
      RemainAfterExit = true;
    };
    path = with pkgs; [
      coreutils
      curl
      jq
      config.services.tailscale.package
    ];
    script = ''
      state="$(tailscale status --json --peers=false 2>/dev/null | jq -r '.BackendState // empty' || true)"
      if [ "$state" = "Running" ]; then
        exit 0
      fi

      umask 077
      tmp="$(mktemp /run/${runtimeDirectory}/tailscale-auth-key.XXXXXX)"
      trap 'rm -f "$tmp"' EXIT

      curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --retry 20 \
        --retry-delay 3 \
        --connect-timeout 5 \
        --header "Metadata-Flavor: Google" \
        ${metadataUrl} > "$tmp"

      if [ ! -s "$tmp" ]; then
        echo "GCE metadata attribute tailscale-auth-key is empty" >&2
        exit 1
      fi

      install -m 0400 -o root -g root "$tmp" ${authKeyFile}
    '';
  };

  systemd.services.tailscaled-autoconnect = {
    requires = [ "gce-dns-tailscale-auth-key.service" ];
    after = [ "gce-dns-tailscale-auth-key.service" ];
  };
}
