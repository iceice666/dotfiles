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
    keyutils
    mpv
    qutebrowser
  ];

  home.activation.qutebrowserBookmarks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    bookmarks_dir="$HOME/.config/qutebrowser/bookmarks"
    bookmarks_file="$bookmarks_dir/urls"

    ${pkgs.coreutils}/bin/mkdir -p "$bookmarks_dir"

    if [ -L "$bookmarks_file" ]; then
      ${pkgs.coreutils}/bin/rm "$bookmarks_file"
    fi

    if [ ! -e "$bookmarks_file" ]; then
      {
        printf '%s\n' 'https://gemini.google.com/app Google Gemini'
      } > "$bookmarks_file"
    fi

    ${pkgs.coreutils}/bin/chmod u+rw "$bookmarks_file"
  '';

  xdg.configFile = {
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
