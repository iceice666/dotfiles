{
  lib,
  pkgs,
  ...
}:

let
  zedBundleId = "dev.zed.Zed";

  zedTypes = [
    "com.apple.property-list"
    "net.daringfireball.markdown"
    "public.json"
    "public.plain-text"
    "public.script"
    "public.shell-script"
    "public.source-code"
    "public.xml"
  ];

  zedExtensions = [
    "c"
    "cc"
    "conf"
    "cpp"
    "css"
    "fish"
    "go"
    "graphql"
    "h"
    "hpp"
    "html"
    "ini"
    "java"
    "js"
    "json"
    "jsonc"
    "jsx"
    "lua"
    "md"
    "mdx"
    "mjs"
    "nix"
    "php"
    "pl"
    "py"
    "rb"
    "rs"
    "scss"
    "sh"
    "sql"
    "swift"
    "toml"
    "ts"
    "tsx"
    "txt"
    "xml"
    "yaml"
    "yml"
    "zig"
  ];

  applyDefaultApps = pkgs.writeShellScript "m3air-apply-default-apps" ''
        #!/usr/bin/env bash
        set -euo pipefail

        readonly default_browser='${pkgs.default-browser}/bin/default-browser'
        readonly utiluti='${pkgs.utiluti}/bin/utiluti'
        readonly zed_bundle_id='${zedBundleId}'

        resolve_bundle_id() {
          local app_path bundle_id

          for app_path in "$@"; do
            if [ -d "$app_path" ]; then
              if bundle_id="$(/usr/bin/mdls -name kMDItemCFBundleIdentifier -raw "$app_path" 2>/dev/null)"; then
                if [ -n "$bundle_id" ] && [ "$bundle_id" != "(null)" ]; then
                  printf '%s\n' "$bundle_id"
                  return 0
                fi
              fi
            fi
          done

          return 1
        }

        set_default_type() {
          local type="$1"
          local current_bundle_id

          current_bundle_id="$($utiluti type --bundle-id "$type" 2>/dev/null || true)"
          if [ "$current_bundle_id" != "$zed_bundle_id" ]; then
            if ! "$utiluti" type set "$type" "$zed_bundle_id"; then
              echo "failed to set Zed as the default app for $type" >&2
            fi
          fi
        }

        set_default_extension() {
          local extension="$1"
          local current_bundle_id

          current_bundle_id="$($utiluti type --bundle-id --extension "$extension" 2>/dev/null || true)"
          if [ "$current_bundle_id" != "$zed_bundle_id" ]; then
            if ! "$utiluti" type set --extension "$extension" "$zed_bundle_id"; then
              echo "failed to set Zed as the default app for .$extension" >&2
            fi
          fi
        }

        zen_bundle_id=""
        if ! zen_bundle_id="$(resolve_bundle_id \
          "/Applications/Zen.app" \
          "/Applications/Zen Browser.app" \
          "$HOME/Applications/Zen.app" \
          "$HOME/Applications/Zen Browser.app")"
        then
          zen_bundle_id=""
        fi

        if [ -z "$zen_bundle_id" ]; then
          zen_bundle_id="$(/usr/bin/osascript -e 'id of app "Zen"' 2>/dev/null || true)"
        fi

        if [ -z "$zen_bundle_id" ]; then
          zen_bundle_id="$(/usr/bin/osascript -e 'id of app "Zen Browser"' 2>/dev/null || true)"
        fi

        if [ -n "$zen_bundle_id" ]; then
          current_browser_bundle_id="$($utiluti url http --bundle-id 2>/dev/null || true)"
          if [ "$current_browser_bundle_id" != "$zen_bundle_id" ]; then
            if ! "$default_browser" --identifier "$zen_bundle_id"; then
              echo "failed to set Zen as the default browser" >&2
            fi
          fi
        else
          echo "Zen app bundle identifier not found; skipping default browser update." >&2
        fi

        zed_paths="$($utiluti app for-id "$zed_bundle_id" 2>/dev/null || true)"
        if [ -n "$zed_paths" ] \
          || [ -d "/Applications/Zed.app" ] \
          || [ -d "/Applications/Home Manager Apps/Zed.app" ] \
          || [ -d "$HOME/Applications/Zed.app" ] \
          || [ -d "$HOME/Applications/Home Manager Apps/Zed.app" ]
        then
    ${lib.concatMapStringsSep "\n" (type: "      set_default_type ${lib.escapeShellArg type}") zedTypes}

    ${lib.concatMapStringsSep "\n" (
      extension: "      set_default_extension ${lib.escapeShellArg extension}"
    ) zedExtensions}
        else
          echo "Zed app not found in Launch Services; skipping default editor update." >&2
        fi
  '';
in
{
  home.packages = with pkgs; [
    default-browser
    utiluti
  ];

  launchd.agents.default-apps = {
    enable = true;
    config = {
      Label = "com.iceice666.default-apps";
      ProgramArguments = [ "${applyDefaultApps}" ];
      RunAtLoad = true;

      StandardOutPath = "/tmp/com.iceice666.default-apps.log";
      StandardErrorPath = "/tmp/com.iceice666.default-apps.err";
    };
  };
}
