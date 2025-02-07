let home = $env.home

use std/util "path add"

path add $"($home)/.orbstack/bin"
path add $"($home)/.cargo/bin"
path add $"($home)/bin"
path add $"($home)/.local/bin"

path add /nix/var/nix/profiles/default/bin
path add /opt/homebrew/bin
path add /run/current-system/sw/bin/
