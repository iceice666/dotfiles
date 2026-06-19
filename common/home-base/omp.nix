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
        (mkModel "claude-opus-4-8" 200000 32000 false)
        (mkModel "claude-sonnet-4-6" 200000 64000 false)
        (mkModel "claude-haiku-4-5-20251001" 200000 16000 false)
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
      slow = "cliproxyapi/claude-opus-4-8:high"; # hardest problems
      smol = "opencode-go/mimo-v2.5"; # $0.14/$0.28, 1M ctx, vision
      title = "smol";
      commit = "github-copilot/gemini-3-flash-preview";
      task = "cliproxyapi/claude-sonnet-4-6";
      plan = "opencode-go/glm-5.2:high"; # GLM 5.2
      designer = "cliproxyapi/claude-sonnet-4-6";
      vision = "cliproxyapi/gemini-3-flash";
      advisor = "cliproxyapi/claude-sonnet-4-6:medium";
    };
    # Globs keep cliproxyapi + opencode-go fully open; github-copilot is pinned
    # to included / low-multiplier models so Edu Pro premium quota is preserved.
    enabledModels = [
      "cliproxyapi/*"
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
        "cliproxyapi/claude-opus-4-8"
        "cliproxyapi/claude-sonnet-4-6"
      ];
      slow = [
        "cliproxyapi/gpt-5.5"
        "cliproxyapi/claude-sonnet-4-6"
      ];
      task = [
        "cliproxyapi/claude-opus-4-8"
        "cliproxyapi/gpt-5.5"
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
