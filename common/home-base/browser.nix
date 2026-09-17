{ config, pkgs, ... }:

{
  home.packages = [ pkgs.playwright-cli ];

  home.file.".skills/playwright-browser".source = ./agent-skills/skills/playwright-browser;
  home.file.".agents/skills/playwright-browser".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.skills/playwright-browser";

  home.file.".playwright/cli.config.json".text = builtins.toJSON {
    browser = {
      browserName = "chromium";
      isolated = true;
      launchOptions = {
        executablePath =
          if pkgs.stdenv.hostPlatform.isDarwin then
            "${pkgs.helium-bin}/Applications/Helium.app/Contents/MacOS/Helium"
          else
            "${pkgs.chromium}/bin/chromium";
        headless = true;
        chromiumSandbox = true;
      };
    };
    timeouts = {
      action = 10000;
      navigation = 60000;
    };
    console.level = "error";
  };
}
