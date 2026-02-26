# dotfiles

Nix configuration for three machines managed via [nix-darwin](https://github.com/nix-darwin/nix-darwin), [home-manager](https://github.com/nix-community/home-manager), and [just](https://github.com/casey/just).

## Machines

| Host | OS | Config type | Username |
|---|---|---|---|
| `M3Air` | macOS (aarch64) | nix-darwin + home-manager | `iceice666` |
| `framework` | Void Linux (x86_64) | home-manager standalone | `iceice666` |
| `server` | NixOS (x86_64) | nixos + home-manager | `root` |

## Structure

```
common/           # applied to every host
  home/           # shared home-manager config (git, fish, starship, direnv, …)
    fish/         # fish shell config and functions
  configuration/  # shared system-level config

shared/           # optional config shared across some (but not all) hosts
  home/
    zed.nix       # Zed editor config (desktop hosts only)

hosts/            # per-machine config
  m3air/
    configuration/  # nix-darwin system config
    home/           # macOS-specific home-manager config
  framework/
    home/           # home-manager standalone config
  server/
    configuration/  # NixOS system config (+ hardware-configuration.nix)
    home/           # server-specific home-manager config
```

## Usage

Run `just` to list all available recipes. Common ones:

```sh
just m3air-rebuild      # darwin-rebuild switch
just framework-rebuild  # home-manager switch
just server-rebuild     # nixos-rebuild switch

just update             # nix flake update
just update-input input # update a single flake input
just fmt                # format all Nix files with nixfmt
just check              # nix flake check
just gc                 # nix-collect-garbage -d
just search query       # search nixpkgs across platforms
```

## First-time setup

### M3 Air

```sh
# 1. Install Nix (if not already)
curl -fsSL https://install.determinate.systems/nix | sh

# 2. Install Homebrew
just m3air-homebrew

# 3. Build and activate
just m3air-rebuild
```

### Framework (Void Linux)

```sh
# Install home-manager, then:
just framework-rebuild
```

### NixOS Server

On a fresh NixOS install, generate the hardware config first:

```sh
just server-gen-hardware
# Review hosts/server/configuration/hardware-configuration.nix, commit it, then:
just server-rebuild
```

> **Note:** `hosts/server/configuration/hardware-configuration.nix` is machine-specific and
> must be generated on the actual server with `nixos-generate-config`. It is not tracked in this repo.
