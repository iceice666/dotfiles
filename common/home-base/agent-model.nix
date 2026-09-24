{ dotfiles, homolab }:

{
  # Shared OpenAI-compatible startup profile for Pi and dsh-desktop.
  model = "gpt-6-astra";
  contextWindow = 1050000;
  maxTokens = 128000;
  baseUrl = "${homolab.urls.cliproxyapi}/v1";
  secretName = "cliproxyapi_homonet_api_key";
  secret = {
    sopsFile = dotfiles + /sensitive/shared/cliproxyapi.yaml;
    key = "homonetApiKey";
    mode = "0400";
  };
}
