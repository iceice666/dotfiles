{ ... }:

let
  nodeExporterPort = 19100;
in
{
  # Residual node-exporter so lumo's Prometheus can scrape homolab host metrics
  # over the tailnet. The tailscale0 interface is trusted in tailscale.nix, so
  # no additional firewall rules are needed; the existing LAN DROP rule is
  # interface-specific (enp7s0) and does not block tailnet traffic.
  services.prometheus.exporters.node = {
    enable = true;
    # Bind to all interfaces so the tailnet can reach this exporter.
    # Port is protected from LAN by the explicit DROP rule in networking.nix.
    listenAddress = "0.0.0.0";
    port = nodeExporterPort;
    enabledCollectors = [
      "processes"
      "systemd"
    ];
    extraFlags = [
      "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run/credentials/.+|var/lib/docker/.+|var/lib/containers/storage/.+)($|/)"
      "--collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|mqueue|nsfs|overlay|proc|pstore|rpc_pipefs|securityfs|sysfs|tracefs)$"
      "--collector.systemd.unit-include=(authelia-main|cloudflare-ips-refresh|tea-asr-1-1-mini|tailscaled|traefik)\\.(service|socket|timer)"
    ];
  };
}
