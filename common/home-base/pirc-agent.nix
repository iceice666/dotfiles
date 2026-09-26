{ ... }:

{
  # pirc node-local agent config (`pirc agent`, spawned by `pirc node`), read
  # from ~/.config/.pirc. Providers and the default model are not here: the
  # lumo gateway pushes them to every node (common/home-base/pirc-models.nix).
  home.file.".config/.pirc/AGENTS.md".source = ./agent-instructions.md;

  home.file.".config/.pirc/config.json".text = builtins.toJSON {
    features.observationalMemory = {
      # Keep background observation off the (possibly Claude) foreground model.
      model = {
        provider = "cliproxyapi";
        id = "gpt-6-sol";
        thinking = "low";
      };
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
}
