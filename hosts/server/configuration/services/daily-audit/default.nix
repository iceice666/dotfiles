{
  config,
  pkgs,
  unstablePkgs,
  username,
  homeDirectory,
  ...
}:

let
  currentDir = ./.;

  pythonEnv = pkgs.python3.withPackages (
    pythonPkgs: with pythonPkgs; [
      langchain-core
      langchain-ollama
      langgraph
      markdown
      resend
    ]
  );

  ollamaBaseUrl = "http://${config.services.ollama.host}:${toString config.services.ollama.port}";
  ollamaModel =
    if config.services.ollama.loadModels != [ ] then
      builtins.head config.services.ollama.loadModels
    else
      "qwen3.5:9b";

  auditScript = pkgs.writeShellApplication {
    name = "homolab-daily-audit";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.systemd
      pythonEnv
    ];
    text = ''
      set -euo pipefail

      exec "${pythonEnv}/bin/python" "${currentDir}/pipeline.py"
    '';
  };
in
{
  systemd.services.homolab-daily-audit = {
    description = "Generate and email the homolab daily audit report";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      HOME = homeDirectory;
      DAILY_AUDIT_EMAIL_FROM = "Homolab Audit <noreply@justaslime.dev>";
      DAILY_AUDIT_EMAIL_TO = "iceice666@outlook.com";
      DAILY_AUDIT_OLLAMA_BASE_URL = ollamaBaseUrl;
      DAILY_AUDIT_OLLAMA_MODEL = ollamaModel;
      DAILY_AUDIT_RESEND_API_KEY_FILE = config.sops.secrets."daily-audit-resend-api-key".path;
    };

    serviceConfig = {
      Type = "oneshot";
      User = username;
      SupplementaryGroups = [ "systemd-journal" ];
      WorkingDirectory = homeDirectory;
      ExecStart = "${auditScript}/bin/homolab-daily-audit";
      StateDirectory = "homolab-daily-audit";
      UMask = "0077";
      TimeoutStartSec = "30m";
    };
  };

  systemd.timers.homolab-daily-audit = {
    description = "Run the homolab daily audit report";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "20m";
      OnUnitActiveSec = "1d";
      Persistent = true;
      RandomizedDelaySec = "30m";
      Unit = "homolab-daily-audit.service";
    };
  };
}
