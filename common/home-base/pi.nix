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

  # Themegen renders the wallpaper-derived Pi themes only on GUI hosts; servers
  # keep the built-in pair so the theme setting always resolves.
  hasThemegenThemes = config.home.file ? ".pi/agent/themes/themegen-dark.json";

  # Keys this repo owns. Everything else in settings.json (model choice,
  # lastChangelogVersion, /settings toggles) stays runtime-owned and writable.
  managedSettings = {
    theme = if hasThemegenThemes then "themegen-light/themegen-dark" else "light/dark";
    hideThinkingBlock = false;
  };

  settingsPath = "${config.home.homeDirectory}/.pi/agent/settings.json";
in
{
  home.packages = [
    pkgs.pi-bin
    pkgs.bash
  ];

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
    source = ./pi/extensions;
    recursive = true;
  };

  sops.secrets.cliproxyapi_homonet_api_key = {
    sopsFile = dotfiles + /sensitive/shared/cliproxyapi.yaml;
    key = "homonetApiKey";
    mode = "0400";
  };

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
      baseUrl = "${homolab.urls.cliproxyapi}/v1";
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
      # Same reason as above; anthropic-messages sends x-session-affinity only.
      # Merged with each model's compat, so forceAdaptiveThinking stays intact.
      compat.sendSessionAffinityHeaders = true;
      models = [
        (mkClaudeModel "claude-fable-5-1" 1000000 128000 true)
        (mkClaudeModel "claude-opus-5" 1000000 128000 true)
        (mkClaudeModel "claude-sonnet-5" 1000000 128000 true)
        (mkClaudeModel "claude-haiku-4-5-20251001" 200000 64000 false)
      ];
    };
  };
}
