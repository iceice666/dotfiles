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
hosts/
  m3air/        # nix-darwin system config + macOS-specific home
  framework/    # home-manager standalone config
  server/       # NixOS system config + server home
user/
  default.nix   # shared: git, direnv, starship, fish
  desktop.nix   # desktop-only packages (zed-editor); not used on server
  fish/         # fish shell config and functions
```

## Usage

Run `just` to list all available recipes. Common ones:

```sh
just m3air-rebuild      # darwin-rebuild switch
just framework-rebuild  # home-manager switch
just server-rebuild     # nixos-rebuild switch

just update             # nix flake update
just fmt                # format all Nix files with nixfmt
just check              # nix flake check
just gc                 # nix-collect-garbage -d
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
# Review hosts/server/hardware-configuration.nix, commit it, then:
just server-rebuild
```

> **Note:** `hosts/server/hardware-configuration.nix` is machine-specific and
> must be generated on the actual server with `nixos-generate-config`. It is
> not tracked in this repo. Add it to `.gitignore` or commit a per-server copy.
