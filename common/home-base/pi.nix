{
  config,
  dotfiles,
  homolab,
  lib,
  pkgs,
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

  apiKey = "!${pkgs.coreutils}/bin/cat ${
    lib.escapeShellArg config.sops.secrets.${agentModel.secretName}.path
  }";

  # Themegen renders the wallpaper-derived Pi themes only on GUI hosts; servers
  # keep the built-in pair so the theme setting always resolves.
  hasThemegenThemes = config.home.file ? ".pi/agent/themes/themegen-dark.json";

  # Deployment restores the shared startup model; session overrides stay usable.
  # Other settings remain runtime-owned and writable.
  managedSettings = {
    defaultProvider = "cliproxyapi";
    defaultModel = agentModel.model;
    theme = if hasThemegenThemes then "themegen-light/themegen-dark" else "light/dark";
    hideThinkingBlock = false;
    observational-memory = {
      # Keep background observation work off the selected foreground model, which
      # may be a much more expensive Claude model. Ratio mode scales proactive
      # compaction to the active model's context window.
      model = {
        provider = "cliproxyapi";
        id = "gpt-6-sol";
        thinking = "low";
      };
      # Local patch (see pi/patches): when the preferred background model reports
      # a rate limit, park it for the cooldown and keep consolidating on Claude
      # instead of silently losing memory for the rest of the session.
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

  # Upstream 3.1.3 plus the repo-owned rate-limit fallback patch. The patch is
  # generated against this exact tag: bump both together and re-run the upstream
  # vitest suite from a checkout before changing `rev`.
  observationalMemory = pkgs.applyPatches {
    name = "pi-observational-memory-3.1.3-patched";
    src = pkgs.fetchFromGitHub {
      owner = "elpapi42";
      repo = "pi-observational-memory";
      rev = "3.1.3";
      hash = "sha256-E6ldxcWo3CWM6ugCEsobesRFkn7J9AtQFd0GFXqhMLI=";
    };
    patches = [ ./pi/patches/observational-memory-rate-limit-fallback.patch ];
  };

  piExtensions = pkgs.runCommand "pi-extensions" { } ''
    mkdir -p "$out"
    cp -R ${./pi/extensions}/. "$out/"
    mkdir -p "$out/observational-memory"
    cp -R ${observationalMemory}/src/. "$out/observational-memory/"
  '';

  settingsPath = "${config.home.homeDirectory}/.pi/agent/settings.json";
in
{
  home.packages = [
    pkgs.pi-bin
    pkgs.bash
  ];

  # Pi gates the per-session prompt_cache_key behind "long" cache retention for
  # non-OpenAI base URLs. Without that key the upstream can only route its prompt
  # cache by hashing the prompt head, which every concurrent agent here shares
  # (identical system prompt and tools), so they all land on one cache shard and
  # evict each other. A conversation whose prefix is entirely new -- after a
  # compaction -- then never gets established and re-bills its whole context each
  # turn. Only providers that opt in below see any effect.
  home.sessionVariables.PI_CACHE_RETENTION = "long";

  home.file.".pi/agent/AGENTS.md".source = ./agent-instructions.md;

  home.file.".pi/agent/exa-api-key".source = pkgs.writeShellScript "pi-exa-api-key" ''
    exec ${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.sops.secrets.exa_api_key.path}
  '';

  sops.secrets.exa_api_key = {
    sopsFile = dotfiles + /sensitive/shared/exa.yaml;
    mode = "0400";
  };

  # Keep sibling imports intact and leave unrelated local extensions alone.
  home.file.".pi/agent/extensions" = {
    source = piExtensions;
    recursive = true;
  };

  sops.secrets.${agentModel.secretName} = agentModel.secret;

  # Merge-on-activation instead of a store symlink: Pi rewrites settings.json at
  # runtime, so a read-only link would break /model and /settings persistence.
  home.activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg (builtins.dirOf settingsPath)}
    if [ ! -s ${lib.escapeShellArg settingsPath} ]; then
      ${pkgs.coreutils}/bin/echo '{}' > ${lib.escapeShellArg settingsPath}
    fi
    if merged=$(${pkgs.jq}/bin/jq --argjson managed ${lib.escapeShellArg (builtins.toJSON managedSettings)} '. * $managed' ${lib.escapeShellArg settingsPath}); then
      printf '%s\n' "$merged" > ${lib.escapeShellArg settingsPath}
    else
      echo "pi: settings.json is not valid JSON; leaving it untouched" >&2
    fi
  '';

  home.file.".pi/agent/models.json".text = builtins.toJSON {
    providers.cliproxyapi = {
      baseUrl = agentModel.baseUrl;
      api = "openai-completions";
      inherit apiKey;
      compat = {
        supportsDeveloperRole = true;
        supportsReasoningEffort = true;
        # Pi only sends prompt_cache_key to api.openai.com, so a proxied provider
        # otherwise carries no session identity and CLIProxyAPI round-robins each
        # turn onto a different upstream account, leaving only the shared system
        # prefix warm. These headers give routing.session-affinity a stable key.
        sendSessionAffinityHeaders = true;
        sessionAffinityFormat = "openai";
        # Opts this provider into PI_CACHE_RETENTION=long, which is what makes Pi
        # send prompt_cache_key (the session ID) so each conversation gets its own
        # upstream cache identity. CLIProxyAPI keeps that key and reuses it as the
        # upstream Session-Id; it drops the accompanying prompt_cache_retention on
        # Codex paths, so no 24h retention is actually claimed.
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
      baseUrl = homolab.urls.cliproxyapi;
      api = "anthropic-messages";
      inherit apiKey;
      # Same reason as above; anthropic-messages sends x-session-affinity only.
      # Merged with each model's compat, so forceAdaptiveThinking stays intact.
      compat.sendSessionAffinityHeaders = true;
      # anthropic-messages defaults this to true, so PI_CACHE_RETENTION=long would
      # silently upgrade Claude to 1h cache_control and its pricier writes. Claude's
      # own cache behaviour is still undiagnosed, so pin the existing 5m default.
      compat.supportsLongCacheRetention = false;
      models = [
        (mkClaudeModel "claude-fable-5-1" 1000000 128000 true)
        (mkClaudeModel "claude-opus-5-5" 1000000 128000 true)
        (mkClaudeModel "claude-opus-5" 1000000 128000 true)
        (mkClaudeModel "claude-sonnet-5" 1000000 128000 true)
        (mkClaudeModel "claude-haiku-4-5-20251001" 200000 64000 false)
      ];
    };
  };
}
