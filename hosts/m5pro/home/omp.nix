{
  config,
  dotfiles,
  homolab,
  lib,
  ...
}:

let
  mkModel =
    id: contextWindow: maxTokens: reasoning:
    { inherit id contextWindow maxTokens; } // lib.optionalAttrs reasoning { inherit reasoning; };

  # Claude models are served over CLIProxyAPI's native Anthropic /v1/messages
  # endpoint. On the OpenAI-completions path omp routes reasoning by appending a
  # "-thinking" suffix to the model id (e.g. claude-sonnet-5-thinking), which
  # CLIProxyAPI has no provider mapping for -> "502 unknown provider". On the
  # anthropic-messages path omp keeps the plain model id and carries reasoning in
  # the request body (thinking.type/budget_tokens), which CLIProxyAPI accepts.
  # Marking reasoning=true ensures omp advertises thinking effort levels and
  # routes /thinking selectors through the Anthropic budget-effort protocol
  # instead of suffix-based routing.
  mkClaudeThinkingModel = id: contextWindow: maxTokens: {
    inherit id contextWindow maxTokens;
    reasoning = true;
    input = [ "text" ];
  };

  # apiKey is injected at activation by sops; a sentinel is serialized into the
  # YAML and then replaced with the runtime placeholder string.
  apiKeySentinel = "@@CLIPROXYAPI_API_KEY@@";

  modelsConfig = {
    providers.cliproxyapi = {
      baseUrl = "${homolab.urls.cliproxyapi}/v1";
      api = "openai-completions";
      apiKey = apiKeySentinel;
      compat = {
        supportsDeveloperRole = true;
        supportsReasoningEffort = true;
      };
      models = [
        (mkModel "gpt-6-astra" 1050000 128000 false)
        (mkModel "gpt-5.6-terra" 272000 16384 false)
        (mkModel "gpt-5.6-sol" 272000 16384 false)
        (mkModel "gpt-5.6-luna" 272000 16384 false)
        (mkModel "gpt-5.5" 272000 16384 false)
        (mkModel "gpt-5.4" 1000000 16384 false)
        (mkModel "gpt-5.4-mini" 272000 16384 false)
        (mkModel "gpt-5.3-codex-spark" 128000 16384 false)
        (mkModel "codex-auto-review" 272000 16384 false)
      ];
    };
    # Claude on the native Anthropic endpoint (see mkClaudeThinkingModel note).
    providers.cliproxyapi-claude = {
      baseUrl = homolab.urls.cliproxyapi;
      api = "anthropic-messages";
      apiKey = apiKeySentinel;
      models = [
        (mkClaudeThinkingModel "claude-fable-5-1" 1000000 64000)
        (mkClaudeThinkingModel "claude-sonnet-5" 1000000 64000)
        (mkClaudeThinkingModel "claude-opus-5" 1000000 64000)
        (mkModel "claude-haiku-4-5-20251001" 200000 16000 false)
      ];
    };
  };

  # OMP requires block-style YAML; render without import-from-derivation.
  toYaml =
    let
      indent = level: lib.concatStrings (builtins.genList (_: "  ") level);
      isScalar =
        value: value == null || builtins.isBool value || builtins.isInt value || builtins.isString value;
      renderScalar =
        value:
        if value == null then
          "null"
        else if builtins.isBool value then
          if value then "true" else "false"
        else if builtins.isInt value then
          toString value
        else if builtins.isString value then
          builtins.toJSON value
        else
          throw "Unsupported YAML scalar";
      render =
        level: value:
        if builtins.isAttrs value then
          lib.concatMapStrings (
            name:
            let
              item = value.${name};
            in
            if isScalar item then
              "${indent level}${builtins.toJSON name}: ${renderScalar item}\n"
            else
              "${indent level}${builtins.toJSON name}:\n${render (level + 1) item}"
          ) (builtins.attrNames value)
        else if builtins.isList value then
          lib.concatMapStrings (
            item:
            if isScalar item then
              "${indent level}- ${renderScalar item}\n"
            else
              "${indent level}-\n${render (level + 1) item}"
          ) value
        else
          throw "Unsupported YAML value";
    in
    render 0;

  modelsYaml =
    lib.replaceStrings [ apiKeySentinel ] [ config.sops.placeholder.cliproxyapi_homonet_api_key ]
      (toYaml modelsConfig);

in
{
  sops.secrets.exa_api_key = {
    sopsFile = dotfiles + /sensitive/shared/exa.yaml;
    mode = "0400";
  };

  sops.secrets.cliproxyapi_homonet_api_key = {
    sopsFile = dotfiles + /sensitive/shared/cliproxyapi.yaml;
    key = "homonetApiKey";
    mode = "0400";
  };

  sops.templates."omp-models".path = "${config.home.homeDirectory}/.omp/agent/models.yml";
  sops.templates."omp-models".mode = "0600";
  sops.templates."omp-models".content = modelsYaml;

  # config.yml, auth, and sessions remain user-managed.

  # omp's builtin web_search tool prefers Exa; the key is read from the
  # process environment (resolved via the agent .env file at startup).
  sops.templates."omp-env".path = "${config.home.homeDirectory}/.omp/agent/.env";
  sops.templates."omp-env".mode = "0600";
  sops.templates."omp-env".content = ''
    EXA_API_KEY=${config.sops.placeholder.exa_api_key}
  '';

}
