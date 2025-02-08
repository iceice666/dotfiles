{pkgs, ...}: let
  nu_scriptRepo = pkgs.fetchFromGitHub {
    owner = "nushell";
    repo = "nu_scripts";
    rev = "main";
    sha256 = "sha256-h8nuX6fE5zJ9dzjzAH1l/8N4F4RMhOIniLSSgCawm0U=";
  };

  source_completion = cmds:
    builtins.concatStringsSep "\n"
    (map (cmd: "source ${nu_scriptRepo}/custom-completions/${cmd}/${cmd}-completions.nu") cmds);
in {
  programs.nushell = {
    enable = true;
    configFile.source = ../config/nu/config.nu;
    envFile.source = ../config/nu/env.nu;
    extraConfig = ''
      source ${../config/nu/custom.nu}

      ${source_completion ["bat" "cargo" "curl" "docker" "eza" "flutter" "pnpm" "git" "just" "nix" "poetry" "ssh"]}

    '';
  };
}
