# pirc model providers. They live only on the gateway (lumo), which resolves
# the key and pushes the providers to every node; nodes configure none.
# `apiKey` is a pirc key reference, e.g. { apiKeyEnv = "…"; }.
{ dotfiles, homolab }:
apiKey:

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
in
{
  defaultModel = {
    provider = "cliproxyapi";
    id = agentModel.model;
  };

  providers.cliproxyapi = apiKey // {
    api = "openai-chat";
    baseUrl = agentModel.baseUrl;
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

  providers.cliproxyapi-claude = apiKey // {
    api = "anthropic-messages";
    baseUrl = homolab.urls.cliproxyapi;
    models = [
      (mkClaudeModel "claude-fable-5-1" 1000000 128000 true)
      (mkClaudeModel "claude-opus-5-5" 1000000 128000 true)
      (mkClaudeModel "claude-opus-5" 1000000 128000 true)
      (mkClaudeModel "claude-sonnet-5" 1000000 128000 true)
      (mkClaudeModel "claude-haiku-4-5-20251001" 200000 64000 false)
    ];
  };
}
