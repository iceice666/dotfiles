{
  inputs,
  pkgs,
  unstablePkgs,
  username,
  homeDirectory,
  dotfiles,
  ...
}:

{
  imports = [
    inputs.sops-nix.homeManagerModules.sops
    (dotfiles + /common/home)
  ];

  sops.age.keyFile = "${homeDirectory}/.config/sops/age/keys.txt";

  home.stateVersion = "25.11";

  home.packages = [
    unstablePkgs.woodpecker-cli
  ];

  home.file.".config/opencode/skill/homolab-daily-audit".source =
    ./opencode-skill/homolab-daily-audit;

  programs.opencode.settings.command.daily-audit = {
    description = "Analyze the homolab daily audit bundle";
    agent = "plan";
    template = ''
      Use the `homolab-daily-audit` skill before analyzing the attached files.

      Review the attached `homolab` audit bundle for this window:
      - Since: $1
      - Until: $2

      Use only the attached files and the loaded skill references. Treat suspicious activity as heuristic evidence, not proof. Distinguish likely malicious activity, operational issues, and benign background noise.

      Produce Markdown with exactly these sections:
      # Homolab Daily Audit
      ## Executive Summary
      ## Findings
      ## Benign Noise
      ## Follow-Up Actions
      ## Evidence Reviewed

      If there are no notable problems, say so explicitly in `Executive Summary` and `Findings`.
    '';
  };

  programs.fish.interactiveShellInit = ''
    set -gx HOSTNAME (hostname)
  '';
}
