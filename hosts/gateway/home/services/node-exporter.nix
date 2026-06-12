{ lib, pkgs, ... }:

let
  nodeExporterPort = 19100;

  nodeExporterService = pkgs.writeText "gateway-node-exporter" ''
    #!/sbin/openrc-run
    name="gateway-node-exporter"
    description="Gateway node exporter"
    supervisor=supervise-daemon
    command="${pkgs.prometheus-node-exporter}/bin/node_exporter"
    command_args="--web.listen-address=0.0.0.0:${toString nodeExporterPort} --collector.processes '--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run/credentials/.+|var/lib/containers/storage/.+)($|/)' '--collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|mqueue|nsfs|overlay|proc|pstore|securityfs|sysfs|tracefs)$'"
    command_user="node-exporter:node-exporter"
    output_log="/var/log/gateway/node-exporter.log"
    error_log="/var/log/gateway/node-exporter.log"
    respawn_delay=5
    respawn_max=0

    depend() {
      need net
    }

    start_pre() {
      checkpath -d -m 0755 -o root:root /var/log/gateway
      checkpath -f -m 0640 -o node-exporter:node-exporter /var/log/gateway/node-exporter.log
    }
  '';
in
{
  home.packages = [ pkgs.prometheus-node-exporter ];

  home.activation.gatewayNodeExporter = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! /usr/bin/getent group node-exporter >/dev/null; then
      /usr/sbin/addgroup -S node-exporter
    fi
    if ! /usr/bin/id node-exporter >/dev/null 2>&1; then
      /usr/sbin/adduser -S -D -H -h /var/lib/node-exporter -s /sbin/nologin -G node-exporter node-exporter
    fi

    install -Dm755 ${nodeExporterService} /etc/init.d/gateway-node-exporter
    /sbin/rc-update add gateway-node-exporter default
    /sbin/rc-service gateway-node-exporter restart
  '';
}
