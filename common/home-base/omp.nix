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
        (mkClaudeThinkingModel "claude-fable-5" 1000000 64000)
        (mkClaudeThinkingModel "claude-sonnet-5" 1000000 64000)
        (mkClaudeThinkingModel "claude-opus-5" 1000000 64000)
        (mkModel "claude-haiku-4-5-20251001" 200000 16000 false)
      ];
    };
  };

  # omp requires block-style YAML for models.yml. Keep this generator pure:
  # deploy-rs evaluates lumo from Darwin before remoteBuild can take over, so
  # import-from-derivation would try to build aarch64-linux text files locally.
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
    # Native OAuth providers are explicitly allow-listed here instead of
    # filtered in CLIProxyAPI's server config. Keep OAuth first so
    # canonical/scoped resolution tries local subscriptions before the homelab
    # proxy. CLIProxyAPI stays globbed because its concrete models are declared
    # in models.yml above. github-copilot is pinned to included /
    # low-multiplier models so Edu Pro premium quota is preserved.
    enabledModels = [
      "cliproxyapi/*"
      "cliproxyapi-claude/*"
      "opencode-go/*"
    ];
    # Canonical selectors and /model use the declared provider preference when
    # concrete variants are available from multiple providers.
    modelProviderOrder = [
      "cliproxyapi"
      "cliproxyapi-claude"
      "opencode-go"
    ];
    modelRoles = {
      default = "cliproxyapi/gpt-5.6-sol:high"; # main interactive agent: OAuth first, quality over latency
      slow = "cliproxyapi-claude/claude-opus-5:high"; # hardest problems, cross-family
      smol = "cliproxyapi/gpt-5.6-sol:low"; # small/quick work
      title = "cliproxyapi-claude/claude-haiku-4-5-20251001";
      commit = "cliproxyapi/gpt-5.6-terra:medium";
      task = "cliproxyapi/gpt-5.6-sol:medium"; # workhorse subagents
      plan = "cliproxyapi-claude/claude-sonnet-5:xhigh"; # final plans need strongest reasoning
      designer = "cliproxyapi-claude/claude-sonnet-5:high";
      vision = "cliproxyapi/gpt-5.6-sol:high";
      advisor = "opencode-go/kimi-k3"; # high-quality second opinion
    };
    # Role primaries use CLIProxyAPI selectors. Their fallback chains add
    # cross-model proxy alternatives. When a model errors or hits a usage limit,
    # omp switches to the next selector in the role chain, then reverts once the
    # cooldown expires.
    # NOTE: chains are keyed by ROLE name (default/slow/task/...), not by model
    # selector — omp resolves each key via getModelRole(), so a model-selector
    # key silently never matches and fallback never fires.
    retry.fallbackChains = {
      default = [
        "cliproxyapi-claude/claude-opus-5:high"
        "cliproxyapi/gpt-5.6-sol:high"
      ];
      slow = [
        "cliproxyapi/gpt-5.6-sol:xhigh"
        "cliproxyapi-claude/claude-sonnet-5:xhigh"
      ];
      task = [
        "cliproxyapi/gpt-5.3-codex-spark:high"
        "cliproxyapi/gpt-5.6-sol:high"
        "cliproxyapi-claude/claude-opus-5:high"
      ];
      plan = [
        "cliproxyapi/gpt-5.6-sol:xhigh"
        "cliproxyapi-claude/claude-opus-5:xhigh"
      ];
      smol = [
        "cliproxyapi-claude/claude-sonnet-5:medium"
      ];
      title = [
        "anthropic/claude-haiku-4-5-20251001"
        "cliproxyapi/gpt-5.6-sol:low"
      ];
      designer = [
        "cliproxyapi-claude/claude-sonnet-5:high"
        "cliproxyapi-claude/claude-opus-5:high"
        "cliproxyapi/gpt-5.6-sol:xhigh"
      ];
      advisor = [
        "cliproxyapi/gpt-5.6-sol:xhigh"
        "cliproxyapi-claude/claude-opus-5:high"
      ];
      vision = [
        "cliproxyapi/gpt-5.6-sol:xhigh"
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
