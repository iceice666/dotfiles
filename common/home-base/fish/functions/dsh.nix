{ ... }:

{
  programs.fish.functions.dsh = {
    description = "Run @deepseek-ai/dsh on an official (non-Nix) Node build via fnm";
    body = ''
      # dsh's native addon (node-addon-require-builtin) locates Node's internal
      # ESM/CJS loader by pattern-matching V8-embedded getter machine code. Its
      # pattern database only recognizes official nodejs.org release builds, so
      # it fails on Nix-built Node (nodejs_24 / nodejs-slim) with
      # "Unsupported/no-getter". Run dsh through fnm on an official Node build
      # instead; the Nix-managed Node stays untouched for everything else.
      if not type -q fnm
          echo "dsh: fnm is required to run an official Node build (add pkgs.fnm to home-base packages and rebuild)" >&2
          return 1
      end

      set -l dsh_bin (command -s dsh)
      if test -z "$dsh_bin"
          echo "dsh: no 'dsh' executable found on PATH" >&2
          return 1
      end

      set -l fnm_alias dsh-runtime
      if not fnm list 2>/dev/null | string match -q "*$fnm_alias*"
          echo "dsh: installing an official Node build for dsh via fnm (one-time)..." >&2
          fnm install 24
          or return 1
          fnm alias 24 $fnm_alias
          or return 1
      end

      fnm exec --using=$fnm_alias -- $dsh_bin $argv
    '';
  };
}
