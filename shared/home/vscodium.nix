{ pkgs, ... }:

let
  productJsonTarget =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "Library/Application Support/VSCodium/product.json"
    else
      ".config/VSCodium/product.json";

  productJson = {
    defaultChatAgent = {
      extensionId = "GitHub.copilot";
      chatExtensionId = "GitHub.copilot-chat";
      chatExtensionOutputId = "GitHub.copilot-chat.GitHub Copilot Chat.log";
      chatExtensionOutputExtensionStateCommand = "github.copilot.debug.extensionState";
      documentationUrl = "https://aka.ms/github-copilot-overview";
      termsStatementUrl = "https://aka.ms/github-copilot-terms-statement";
      privacyStatementUrl = "https://aka.ms/github-copilot-privacy-statement";
      skusDocumentationUrl = "https://aka.ms/github-copilot-plans";
      publicCodeMatchesUrl = "https://aka.ms/github-copilot-match-public-code";
      manageSettingsUrl = "https://aka.ms/github-copilot-settings";
      managePlanUrl = "https://aka.ms/github-copilot-manage-plan";
      manageOverageUrl = "https://aka.ms/github-copilot-manage-overage";
      upgradePlanUrl = "https://aka.ms/github-copilot-upgrade-plan";
      signUpUrl = "https://aka.ms/github-sign-up";
      provider = {
        default = {
          id = "github";
          name = "GitHub";
        };
        enterprise = {
          id = "github-enterprise";
          name = "GHE.com";
        };
        google = {
          id = "google";
          name = "Google";
        };
        apple = {
          id = "apple";
          name = "Apple";
        };
      };
      providerExtensionId = "vscode.github-authentication";
      providerUriSetting = "github-enterprise.uri";
      providerScopes = [
        [
          "read:user"
          "user:email"
          "repo"
          "workflow"
        ]
        [ "user:email" ]
        [ "read:user" ]
      ];
      entitlementUrl = "https://api.github.com/copilot_internal/user";
      entitlementSignupLimitedUrl = "https://api.github.com/copilot_internal/subscribe_limited_user";
      chatQuotaExceededContext = "github.copilot.chat.quotaExceeded";
      completionsQuotaExceededContext = "github.copilot.completions.quotaExceeded";
      walkthroughCommand = "github.copilot.open.walkthrough";
      completionsMenuCommand = "github.copilot.toggleStatusMenu";
      completionsRefreshTokenCommand = "github.copilot.signIn";
      chatRefreshTokenCommand = "github.copilot.refreshToken";
      generateCommitMessageCommand = "github.copilot.git.generateCommitMessage";
      resolveMergeConflictsCommand = "github.copilot.git.resolveMergeConflicts";
      completionsAdvancedSetting = "github.copilot.advanced";
      completionsEnablementSetting = "github.copilot.enable";
      nextEditSuggestionsSetting = "github.copilot.nextEditSuggestions.enabled";
      tokenEntitlementUrl = "https://api.github.com/copilot_internal/v2/token";
      mcpRegistryDataUrl = "https://api.github.com/copilot/mcp_registry";
    };

    trustedExtensionAuthAccess = {
      github = [ "GitHub.copilot-chat" ];
      github-enterprise = [ "GitHub.copilot-chat" ];
    };

    extensionsGallery = {
      serviceUrl = "https://marketplace.visualstudio.com/_apis/public/gallery";
      itemUrl = "https://marketplace.visualstudio.com/items";
      cacheUrl = "https://vscode.blob.core.windows.net/gallery/index";
      extensionUrlTemplate = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/{publisher}/vsextensions/{name}/{version}/vspackage";
      resourceUrlTemplate = "https://{publisher}.vscode-unpkg.net/{publisher}/{name}/{version}/{path}";
    };
  };
in
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;

    profiles.default = {
      extensions = [
        pkgs.vscode-extensions.github.copilot
        pkgs.vscode-extensions.github."copilot-chat"
      ];

      userSettings = {
        "chat.disableAIFeatures" = false;
        "editor.fontFamily" = "Cascadia Code NF";
        "editor.fontSize" = 16;
        "terminal.integrated.fontFamily" = "Cascadia Code NF";
        "terminal.integrated.fontSize" = 16;
        "window.autoDetectColorScheme" = true;
        "workbench.colorTheme" = "Themegen Dark";
        "workbench.preferredDarkColorTheme" = "Themegen Dark";
        "workbench.preferredLightColorTheme" = "Themegen Light";
      };
    };
  };

  home.file = {
    "${productJsonTarget}".text = builtins.toJSON productJson;
  };
}
