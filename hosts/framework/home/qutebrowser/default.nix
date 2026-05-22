{ lib, pkgs, ... }:

let
  qutebrowserPython = pkgs.python3.withPackages (
    pythonPkgs: with pythonPkgs; [
      pyperclip
      tldextract
    ]
  );

  quteBitwardenFuzzel = pkgs.replaceVars ./userscripts/qute-bitwarden-fuzzel {
    python = lib.getExe qutebrowserPython;
  };

  umpv = pkgs.replaceVars ./userscripts/umpv {
    python = lib.getExe qutebrowserPython;
  };
in
{
  home.packages = with pkgs; [
    bitwarden-cli
    keyutils
    mpv
    qutebrowser
  ];

  xdg.configFile = {
    "qutebrowser/bookmarks/urls".text = ''
      https://gemini.google.com/app Google Gemini
    '';
    "qutebrowser/config.py".source = ./config.py;
    "qutebrowser/userscripts/qute-bitwarden-fuzzel" = {
      source = quteBitwardenFuzzel;
      executable = true;
    };
    "qutebrowser/userscripts/umpv" = {
      source = umpv;
      executable = true;
    };
  };
}
