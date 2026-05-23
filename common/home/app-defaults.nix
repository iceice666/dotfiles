{ lib, pkgs, ... }:

let
  browserDesktop = "zen.desktop";
  editorDesktop = "dev.zed.Zed.desktop";

  browserAssociations = {
    "text/html" = browserDesktop;
    "x-scheme-handler/http" = browserDesktop;
    "x-scheme-handler/https" = browserDesktop;
    "x-scheme-handler/about" = browserDesktop;
    "x-scheme-handler/unknown" = browserDesktop;
  };

  editorAssociations = {
    "application/json" = editorDesktop;
    "application/toml" = editorDesktop;
    "application/xml" = editorDesktop;
    "application/x-shellscript" = editorDesktop;
    "application/x-yaml" = editorDesktop;
    "text/css" = editorDesktop;
    "text/markdown" = editorDesktop;
    "text/plain" = editorDesktop;
    "text/x-c" = editorDesktop;
    "text/x-c++src" = editorDesktop;
    "text/x-go" = editorDesktop;
    "text/x-java" = editorDesktop;
    "text/x-lua" = editorDesktop;
    "text/x-nix" = editorDesktop;
    "text/x-python" = editorDesktop;
    "text/x-ruby" = editorDesktop;
    "text/x-rust" = editorDesktop;
    "text/x-scss" = editorDesktop;
    "text/xml" = editorDesktop;
  };
in
{
  xdg.mimeApps = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = true;
    defaultApplications = browserAssociations // editorAssociations;
  };
}
