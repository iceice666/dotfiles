{ dotfiles, username, ... }:

{
  sops.secrets."homolab-audit-resend-api-key" = {
    sopsFile = dotfiles + /sensitive/hosts/homolab/resend.yaml;
    key = "apiKey";
    owner = username;
    group = "homolab-audit";
    mode = "0400";
    restartUnits = [ "homolab-audit-report.service" ];
  };
}
