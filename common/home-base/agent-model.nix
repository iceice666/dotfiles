{ dotfiles, lab }:

{
  # Shared CLIProxyAPI profile: GPT defaults for pirc, and the gateway key that
  # Claude Code and the Lumo audit runner also read.
  model = "gpt-6-astra";
  contextWindow = 1050000;
  maxTokens = 128000;
  baseUrl = "${lab.urls.cliproxyapi}/v1";
  secretName = "cliproxyapi_homonet_api_key";
  secret = {
    sopsFile = dotfiles + /sensitive/shared/cliproxyapi.yaml;
    key = "homonetApiKey";
    mode = "0400";
  };
}
