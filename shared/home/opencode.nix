{
  config,
  unstablePkgs,
  dotfiles,
  ...
}:

{
  sops.secrets."openrouter-api-key" = {
    sopsFile = dotfiles + /sensitive/shared/openrouter.yaml;
    key = "api_key";
  };

  programs.opencode = {
    enable = true;
    package = unstablePkgs.opencode;
    settings = {
      plugin = [ "@tarquinen/opencode-dcp@latest" ];
      provider.ollama = {
        models."qwen3.5:9b" = {
          _launch = true;
          name = "qwen3.5:9b";
        };
        name = "Ollama";
        npm = "@ai-sdk/openai-compatible";
        options.baseURL = "http://192.168.1.127:11434/v1";
      };
      provider.openrouter = {
        models."qwen/qwen3.6-plus:free" = {
          name = "qwen/qwen3.6-plus:free";
        };
        name = "OpenRouter";
        npm = "@ai-sdk/openai-compatible";
        options = {
          apiKey = "{file:${config.sops.secrets."openrouter-api-key".path}}";
          baseURL = "https://openrouter.ai/api/v1";
        };
      };
    };
  };
}
