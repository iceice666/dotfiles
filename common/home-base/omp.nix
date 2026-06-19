{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  ...
}:

let

  mkModel =
    id: contextWindow: maxTokens: reasoning:
    { inherit id contextWindow maxTokens; } // lib.optionalAttrs reasoning { inherit reasoning; };

  # Claude models are served over CLIProxyAPI's native Anthropic /v1/messages
  # endpoint. On the OpenAI-completions path omp routes reasoning by appending a
  # "-thinking" suffix to the model id (e.g. claude-sonnet-4-6-thinking), which
  # CLIProxyAPI has no provider mapping for -> "502 unknown provider". On the
  # anthropic-messages path omp keeps the plain model id and carries reasoning in
  # the request body (thinking.type/budget_tokens), which CLIProxyAPI accepts.
  # Declaring an explicit thinking block also strips omp's synthesized suffix
  # routing for the model.
  mkClaudeThinkingModel = id: contextWindow: maxTokens: {
    inherit id contextWindow maxTokens;
    thinking = {
      mode = "anthropic-budget-effort";
      efforts = [
        "minimal"
        "low"
        "medium"
        "high"
        "max"
      ];
    };
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
        (mkModel "gpt-5.5" 128000 16384 false)
        (mkModel "gpt-5.4" 128000 16384 false)
        (mkModel "gpt-5.4-mini" 128000 16384 false)
        (mkModel "gpt-5.3-codex-spark" 128000 16384 false)
        (mkModel "gpt-oss-120b-medium" 128000 16384 false)
        (mkModel "gemini-3-pro-high" 1000000 8192 false)
        (mkModel "gemini-3-pro-low" 1000000 8192 false)
        (mkModel "gemini-3.1-pro-low" 1000000 8192 false)
        (mkModel "gemini-3-flash" 1000000 8192 false)
        (mkModel "gemini-3.1-flash-image" 1000000 8192 false)
        (mkModel "gemini-3.1-flash-lite" 1000000 8192 false)
        (mkModel "gemini-3.5-flash-low" 1000000 8192 false)
      ];
    };
    # Claude on the native Anthropic endpoint (see mkClaudeThinkingModel note).
    providers.cliproxyapi-claude = {
      baseUrl = homolab.urls.cliproxyapi;
      api = "anthropic-messages";
      apiKey = apiKeySentinel;
      models = [
        (mkClaudeThinkingModel "claude-opus-4-8" 200000 32000)
        (mkClaudeThinkingModel "claude-sonnet-4-6" 200000 64000)
        (mkModel "claude-haiku-4-5-20251001" 200000 16000 false)
      ];
    };
  };

  modelsYaml =
    lib.replaceStrings [ apiKeySentinel ] [ config.sops.placeholder.cliproxyapi_homonet_api_key ]
      (lib.generators.toYAML { } modelsConfig);

  # config.yml holds model-role assignments and the model allow-list (no secret),
  # so it is seeded as a mutable file on each switch. Live edits via
  # `omp config set` / `/settings` persist until the next home-manager rebuild,
  # which restores the values declared here.
  configConfig = {
    providers.webSearch = "auto";
    symbolPreset = "nerd";
    theme = {
      dark = "titanium";
      light = "light";
    };
    setupVersion = 1;
    modelRoles = {
      default = "cliproxyapi/gpt-5.5:medium"; # $5/$30, 128K ctx, vision
      slow = "cliproxyapi-claude/claude-opus-4-8:high"; # hardest problems
      smol = "opencode-go/mimo-v2.5"; # $0.14/$0.28, 1M ctx, vision
      title = "smol";
      commit = "github-copilot/gemini-3-flash-preview";
      task = "cliproxyapi-claude/claude-sonnet-4-6";
      plan = "cliproxyapi/gpt-5.5:xhigh"; # final plans need stronger reasoning
      designer = "cliproxyapi-claude/claude-sonnet-4-6";
      vision = "cliproxyapi/gemini-3-flash";
      advisor = "opencode-go/glm-5.2:high"; # cheap second opinion; not final planning
    };
    # Globs keep cliproxyapi + opencode-go fully open; github-copilot is pinned
    # to included / low-multiplier models so Edu Pro premium quota is preserved.
    enabledModels = [
      "cliproxyapi/*"
      "cliproxyapi-claude/*"
      "opencode-go/*"
      "github-copilot/gpt-4.1"
      "github-copilot/gpt-4o"
      "github-copilot/gpt-4o-mini"
      "github-copilot/gpt-5-mini"
      "github-copilot/gpt-5.4-mini"
      "github-copilot/gpt-5.4-nano"
      "github-copilot/raptor-mini"
      "github-copilot/grok-code-fast-1"
      "github-copilot/gemini-3-flash-preview"
    ];
    # Cross-model fallback: when a model errors or hits a usage limit and no
    # sibling credential is free, switch to the next selector in its chain
    # (zero delay), then revert once the cooldown expires. All cliproxyapi.
    # NOTE: chains are keyed by ROLE name (default/slow/task/...), not by model
    # selector — omp resolves each key via getModelRole(), so a model-selector
    # key silently never matches and fallback never fires.
    retry.fallbackChains = {
      default = [
        "cliproxyapi-claude/claude-opus-4-8"
        "cliproxyapi-claude/claude-sonnet-4-6"
      ];
      slow = [
        "cliproxyapi/gpt-5.5"
        "cliproxyapi-claude/claude-sonnet-4-6"
      ];
      task = [
        "cliproxyapi-claude/claude-opus-4-8"
        "cliproxyapi/gpt-5.5"
      ];
      plan = [
        "cliproxyapi-claude/claude-opus-4-8:max"
      ];

    };
  };

  configFile = pkgs.writeText "omp-config.yml" (lib.generators.toYAML { } configConfig);
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

  # Seed the global config.yml mutably (it carries no secret). Overwritten on
  # every switch, so the repo stays the source of truth for roles + allow-list.
  home.activation.omp-config-seed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -d -m 0700 "${config.home.homeDirectory}/.omp/agent"
    install -m 0600 "${configFile}" "${config.home.homeDirectory}/.omp/agent/config.yml"
  '';

  home.packages = with pkgs; [
    oh-my-pi-bin
  ];

  # omp's builtin web_search tool prefers Exa; the key is read from the
  # process environment (resolved via the agent .env file at startup).
  sops.templates."omp-env".path = "${config.home.homeDirectory}/.omp/agent/.env";
  sops.templates."omp-env".mode = "0600";
  sops.templates."omp-env".content = ''
    EXA_API_KEY=${config.sops.placeholder.exa_api_key}
  '';

}
