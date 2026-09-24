{
  config,
  dotfiles,
  inputs,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  agentModel = import ../../../common/home-base/agent-model.nix { inherit dotfiles homolab; };
  settingsPath = "${config.programs.dsh-desktop.dshHome}/settings.yaml";
  settingsPython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  managedSettings = pkgs.writeText "dsh-desktop-settings.json" (
    builtins.toJSON {
      agent-default-model = {
        provider = "cliproxyapi";
        model = agentModel.model;
      };
      llm-pi-ai.providers.cliproxyapi = {
        apiKeyEnv = "CLIPROXYAPI_API_KEY";
        api = "openai-completions";
        baseURL = agentModel.baseUrl;
        models = [
          {
            id = agentModel.model;
            inherit (agentModel) contextWindow maxTokens;
            input = [ "text" ];
          }
        ];
      };
    }
  );
in
{
  imports = [ inputs.dsh-desktop.homeManagerModules.default ];

  # DeepSeek Harness desktop app, copied to ~/Applications/Home Manager Apps.
  # Name and icon are baked into the bundle; set them here, not in the app.
  programs.dsh-desktop = {
    enable = true;
    name = "大燒貨";
    icon = ../../../assets/dsh.png;
  };

  # Declared identically in pi.nix; sops-nix merges equal definitions.
  sops.secrets.exa_api_key = {
    sopsFile = dotfiles + /sensitive/shared/exa.yaml;
    mode = "0400";
  };
  sops.secrets.${agentModel.secretName} = agentModel.secret;

  home.activation.dshDesktopSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${settingsPython}/bin/python ${./merge-dsh-settings.py} \
      ${lib.escapeShellArg settingsPath} ${managedSettings}
  '';

  sops.templates."dsh-desktop-env" = {
    path = "${config.programs.dsh-desktop.dshHome}/.env";
    mode = "0600";
    content = ''
      EXA_API_KEY=${config.sops.placeholder.exa_api_key}
      CLIPROXYAPI_API_KEY=${config.sops.placeholder.${agentModel.secretName}}
    '';
  };
}
