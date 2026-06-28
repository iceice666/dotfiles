{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
  unstablePkgs,
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
      "openai-codex/gpt-5.5"
      "openai-codex/gpt-5.3-codex-spark"
      "anthropic/claude-opus-4-8"
      "anthropic/claude-sonnet-4-6"
      "anthropic/claude-haiku-4-5-20251001"
      "cliproxyapi/*"
      "cliproxyapi-claude/*"
      "opencode-go/*"
      "github-copilot/gpt-5-mini"
      "github-copilot/gpt-5.4-mini"
    ];
    # Canonical selectors and /model should prefer subscription OAuth before
    # the CLIProxyAPI mirrors when both concrete variants are available.
    modelProviderOrder = [
      "openai-codex"
      "anthropic"
      "cliproxyapi"
      "cliproxyapi-claude"
      "opencode-go"
      "github-copilot"
    ];
    modelRoles = {
      default = "openai-codex/gpt-5.5:medium"; # main interactive agent: OAuth first, quality over latency
      slow = "anthropic/claude-opus-4-8:high"; # hardest problems, cross-family
      smol = "openai-codex/gpt-5.3-codex-spark:medium"; # small/quick work on Spark entitlement
      title = "anthropic/claude-haiku-4-5-20251001";
      commit = "anthropic/claude-haiku-4-5-20251001";
      task = "openai-codex/gpt-5.3-codex-spark:high"; # workhorse subagents
      plan = "anthropic/claude-sonnet-4-6:xhigh"; # final plans need strongest reasoning
      designer = "anthropic/claude-sonnet-4-6:high";
      vision = "cliproxyapi/gemini-3-pro-high";
      advisor = "opencode-go/glm-5-2"; # high-quality second opinion
    };
    # GPT/Claude role primaries use OAuth selectors. Their fallback chains keep
    # matching CLIProxyAPI selectors as the first same-model fallback, then add
    # cross-model OAuth/proxy pairs. When a model errors or hits a usage limit,
    # omp switches to the next selector in the role chain, then reverts once the
    # cooldown expires.
    # NOTE: chains are keyed by ROLE name (default/slow/task/...), not by model
    # selector — omp resolves each key via getModelRole(), so a model-selector
    # key silently never matches and fallback never fires.
    retry.fallbackChains = {
      default = [
        "cliproxyapi/gpt-5.5:medium"
        "cliproxyapi-claude/claude-opus-4-8:high"
        "cliproxyapi-claude/claude-sonnet-4-6:high"
      ];
      slow = [
        "cliproxyapi-claude/claude-opus-4-8:high"
        "cliproxyapi/gpt-5.5:xhigh"
        "cliproxyapi-claude/claude-sonnet-4-6:xhigh"
      ];
      task = [
        "cliproxyapi/gpt-5.3-codex-spark:high"
        "cliproxyapi/gpt-5.5:xhigh"
        "cliproxyapi-claude/claude-sonnet-4-6:high"
        "cliproxyapi-claude/claude-opus-4-8:xhigh"
      ];
      plan = [
        "cliproxyapi/gpt-5.5:xhigh"
        "cliproxyapi-claude/claude-opus-4-8:xhigh"
      ];
      smol = [
        "anthropic/claude-haiku-4-5-20251001"
        "cliproxyapi/gpt-5.5:medium"
        "cliproxyapi-claude/claude-sonnet-4-6:medium"
      ];
      title = [
        "anthropic/claude-haiku-4-5-20251001"
        "cliproxyapi/gpt-5.5:medium"
      ];
      commit = [
        "cliproxyapi/gpt-5.5:medium"
        "cliproxyapi-claude/claude-sonnet-4-6:medium"
      ];
      designer = [
        "cliproxyapi-claude/claude-sonnet-4-6:high"
        "cliproxyapi-claude/claude-opus-4-8:high"
        "cliproxyapi/gpt-5.5:xhigh"
      ];
      advisor = [
        "cliproxyapi-claude/claude-opus-4-8:high"
        "cliproxyapi/gpt-5.5:xhigh"
        "cliproxyapi-claude/claude-sonnet-4-6:xhigh"
      ];
      vision = [
        "cliproxyapi/gemini-3.1-flash-image"
        "cliproxyapi/gpt-5.5:xhigh"
        "cliproxyapi/gemini-3-flash"
      ];
    };
  };

  configFile = pkgs.writeText "omp-config.yml" (lib.generators.toYAML { } configConfig);
  cleanupOldFastPlugin = pkgs.writeText "omp-fast-mode-plugin-cleanup.js" ''
    const fs = require("fs");
    const path = require("path");

    const dir = process.argv[2];
    const managed = [
      "@diegopetrucci/pi-openai-fast",
      "@earendil-works/pi-coding-agent",
      "omp-fast-mode",
    ];

    function readJson(file) {
      try {
        return JSON.parse(fs.readFileSync(file, "utf8"));
      } catch {
        return undefined;
      }
    }

    function writeJson(file, value) {
      fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n");
    }

    const packagePath = path.join(dir, "package.json");
    const pkg = readJson(packagePath);
    if (pkg && pkg.dependencies) {
      let changed = false;
      for (const name of managed) {
        if (Object.prototype.hasOwnProperty.call(pkg.dependencies, name)) {
          delete pkg.dependencies[name];
          changed = true;
        }
      }
      if (changed) writeJson(packagePath, pkg);
    }

    const lockPath = path.join(dir, "omp-plugins.lock.json");
    const lock = readJson(lockPath);
    if (lock) {
      let changed = false;
      for (const section of ["plugins", "settings"]) {
        if (!lock[section]) continue;
        for (const name of managed) {
          if (Object.prototype.hasOwnProperty.call(lock[section], name)) {
            delete lock[section][name];
            changed = true;
          }
        }
      }
      if (changed) writeJson(lockPath, lock);
    }

    for (const name of managed) {
      fs.rmSync(path.join(dir, "node_modules", ...name.split("/")), {
        recursive: true,
        force: true,
      });
    }

    const hasPackageDependencies =
      pkg?.dependencies && Object.keys(pkg.dependencies).length > 0;
    const hasRuntimePlugins = lock?.plugins && Object.keys(lock.plugins).length > 0;
    if (!hasPackageDependencies && !hasRuntimePlugins) {
      fs.rmSync(path.join(dir, "node_modules"), { recursive: true, force: true });
    }
  '';
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
  # Clean up the previous fast-mode npm-plugin workaround without touching
  # unrelated user plugins.
  home.activation.omp-fast-mode-plugin-cleanup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    plugin_dir="${config.home.homeDirectory}/.omp/plugins"
    if [ -d "$plugin_dir" ]; then
      ${unstablePkgs.bun}/bin/bun "${cleanupOldFastPlugin}" "$plugin_dir"
    fi
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
