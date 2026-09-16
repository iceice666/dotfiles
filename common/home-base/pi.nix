{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let
  mkModel = id: contextWindow: maxTokens: {
    inherit id contextWindow maxTokens;
    reasoning = true;
  };

  mkClaudeModel =
    id: contextWindow: maxTokens: adaptiveThinking:
    mkModel id contextWindow maxTokens
    // {
      input = [
        "text"
        "image"
      ];
      compat.forceAdaptiveThinking = adaptiveThinking;
    };

  apiKey = "!${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.sops.secrets.cliproxyapi_homonet_api_key.path}";
in
{
  home.packages = [ pkgs.pi-bin ];

  sops.secrets.cliproxyapi_homonet_api_key = {
    sopsFile = dotfiles + /sensitive/shared/cliproxyapi.yaml;
    key = "homonetApiKey";
    mode = "0400";
  };

  home.file.".pi/agent/models.json".text = builtins.toJSON {
    providers.cliproxyapi = {
      baseUrl = "${homolab.urls.cliproxyapi}/v1";
      api = "openai-completions";
      inherit apiKey;
      compat = {
        supportsDeveloperRole = true;
        supportsReasoningEffort = true;
      };
      models = [
        (mkModel "gpt-6-astra" 1050000 128000)
        (mkModel "gpt-5.6-sol" 272000 16384)
        (mkModel "gpt-5.6-luna" 272000 16384)
      ];
    };

    providers.cliproxyapi-claude = {
      baseUrl = homolab.urls.cliproxyapi;
      api = "anthropic-messages";
      inherit apiKey;
      models = [
        (mkClaudeModel "claude-fable-5-1" 1000000 128000 true)
        (mkClaudeModel "claude-opus-5" 1000000 128000 true)
        (mkClaudeModel "claude-sonnet-5" 1000000 128000 true)
        (mkClaudeModel "claude-haiku-4-5-20251001" 200000 64000 false)
      ];
    };
  };
}
