{
  config,
  dotfiles,
  homolab,
  lib,
  ...
}:

let
  agentModel = import ./agent-model.nix { inherit dotfiles homolab; };

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

  # Read at request time, so the key never enters the Nix store.
  apiKeyFile = config.sops.secrets.${agentModel.secretName}.path;
in
{
  sops.secrets.${agentModel.secretName} = agentModel.secret;

  # pirc's built-in agent (`pirc agent`, spawned by `pirc gateway`/`pirc node`)
  # reads its global config from ~/.config/.pirc. Same providers as Pi.
  home.file.".config/.pirc/AGENTS.md".source = ./agent-instructions.md;

  home.file.".config/.pirc/config.json".text = builtins.toJSON {
    defaultModel = {
      provider = "cliproxyapi";
      id = agentModel.model;
    };

    providers.cliproxyapi = {
      api = "openai-chat";
      baseUrl = agentModel.baseUrl;
      inherit apiKeyFile;
      compat = {
        supportsDeveloperRole = true;
        supportsReasoningEffort = true;
        # prompt_cache_key + session_id give CLIProxyAPI's session affinity a
        # stable per-conversation key (see the notes in pi.nix).
        sendSessionAffinityHeaders = true;
        supportsLongCacheRetention = true;
      };
      models = [
        (mkModel agentModel.model agentModel.contextWindow agentModel.maxTokens)
      ]
      ++ builtins.filter (model: model.id != agentModel.model) [
        (mkModel "gpt-6-astra" 1050000 128000)
        (mkModel "gpt-6-sol" 1050000 128000)
        (mkModel "gpt-6-luna" 1050000 128000)
      ];
    };

    providers.cliproxyapi-claude = {
      api = "anthropic-messages";
      baseUrl = homolab.urls.cliproxyapi;
      inherit apiKeyFile;
      models = [
        (mkClaudeModel "claude-fable-5-1" 1000000 128000 true)
        (mkClaudeModel "claude-opus-5-5" 1000000 128000 true)
        (mkClaudeModel "claude-opus-5" 1000000 128000 true)
        (mkClaudeModel "claude-sonnet-5" 1000000 128000 true)
        (mkClaudeModel "claude-haiku-4-5-20251001" 200000 64000 false)
      ];
    };

    features.observationalMemory = {
      # Keep background observation off the (possibly Claude) foreground model.
      model = {
        provider = "cliproxyapi";
        id = "gpt-6-sol";
        thinking = "low";
      };
      fallbackModels = [
        {
          provider = "cliproxyapi-claude";
          id = "claude-sonnet-5";
        }
      ];
      rateLimitCooldownMs = 900000;
      compactAfterTokensMode = "ratio";
      compactAfterTokensRatio = 0.68;
      agentMaxTokens = 8192;
    };
  };
}
