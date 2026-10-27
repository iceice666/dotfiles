{
  lib,
  pkgs,
  dotfiles,
  ...
}:

let
  frameworkAvatar = dotfiles + /assets/framework-avatar.png;
  quartus = pkgs.quartus-prime-lite.override {
    supportedDevices = [ "MAX 10 FPGA" ];
    withQuesta = false;
    # Quartus's bundled Qt needs XWayland rather than the session's Wayland backend.
    extraProfile = ''
      export QT_QPA_PLATFORM=xcb
    '';
  };
in
{
  imports = [
    (dotfiles + /common/home-base/browser.nix)
    ./gui.nix
  ];

  _module.args = {
    avatarImage = frameworkAvatar;
    ghosttyFontSize = 14;
    themegenHost = "framework";
  };

  # Framework uses Niri for window management; no Ghostty tab bar.
  programs.ghostty.settings.window-show-tab-bar = lib.mkForce "never";

  home.packages = with pkgs; [
    obs-studio
    (quartus.override {
      unwrapped = quartus.unwrapped.override {
        # The locked nixpkgs still uses Intel URLs that now return an HTML page.
        # Keep upstream hashes; remove this workaround once nixpkgs uses Altera URLs.
        fetchurl =
          args:
          pkgs.fetchurl (
            args
            // {
              url =
                lib.replaceStrings
                  [ "https://downloads.intel.com/" ]
                  [
                    "https://download.altera.com/"
                  ]
                  args.url;
              curlOptsList = [
                "--user-agent"
                "Alterabot/1.0"
              ];
            }
          );
      };
    })
  ];
}
