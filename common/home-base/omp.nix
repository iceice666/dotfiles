{
  config,
  dotfiles,
  homolab,
  pkgs,
  ...
}:

let
  inherit (pkgs) lib;

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
