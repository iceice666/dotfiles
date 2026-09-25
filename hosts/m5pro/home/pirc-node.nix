{ config, pkgs, ... }:

let
  stateDir = "${config.home.homeDirectory}/.local/pirc-node";
in
{
  imports = [ ../../../common/home-base/pirc-agent.nix ];

  # Outbound pirc node: connects to the lumo daemon and runs one `pirc agent`
  # per session locally. PIRC_NODE_TOKEN and the rest of the node settings
  # (PIRC_NODE_ID, PIRC_DAEMON_URL, PIRC_WORKSPACES, PIRC_ALLOWED_USERS,
  # PIRC_STATE_DIR) stay in the out-of-store agent.env.
  launchd.agents.pirc-node = {
    enable = true;
    config = {
      Label = "dev.pirc.node-agent";
      ProgramArguments = [
        "/bin/bash"
        "-c"
        ''
          export PATH="/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"
          set -a; source "${stateDir}/agent.env"; set +a
          exec ${pkgs.pirc}/bin/pirc node
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${stateDir}/agent.log";
      StandardErrorPath = "${stateDir}/agent.err";
    };
  };
}
