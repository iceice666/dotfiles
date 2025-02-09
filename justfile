hostname := `hostname -s`


# List all the just commands
[private]
default:
    @just --choose

#
# For deploy
#

[macos]
dirty-deploy: && deploy
    git add .

[macos]
deploy: && fmt
    nix build .#darwinConfigurations.{{hostname}}.system
    @echo ""
    @echo "Successfully eval config"
    @echo "Switching..."
    @echo ""
    ./result/sw/bin/darwin-rebuild switch --flake .#{{hostname}}

[macos]
deploy-debug: && fmt
    nix build .#darwinConfigurations.{{hostname}}.system --show-trace --verbose
    @echo ""
    @echo "Successfully eval config"
    @echo "Switching..."
    @echo ""
    ./result/sw/bin/darwin-rebuild switch --flake .#{{hostname}} --show-trace --verbose

[linux]
dirty-deploy:
    @echo "Not supported yet!"

[linux]
deploy:
    @echo "Not supported yet!"

[linux]
deploy-debug:
    @echo "Not supported yet!"

#
#  nix related commands
#

# Update all the flake inputs
[group('nix')]
update:
    nix flake update

# Update specific input
# Usage: just upd-pkg <nixpkgs>
[group('nix')]
update-pkg input:
    nix flake update {{input}}

# List all generations of the system profile
[group('nix')]
history:
    nix profile history --profile /nix/var/nix/profiles/system

# Open a nix shell with the flake
[group('nix')]
repl:
    nix repl -f flake:nixpkgs

# remove all generations older than 7 days
# on darwin, you may need to switch to root user to run this command
[group('nix')]
clean:
    sudo -H nix profile wipe-history --profile /nix/var/nix/profiles/system  --older-than 7d

# Garbage collect all unused nix store entries
[group('nix')]
gc:
    # garbage collect all unused nix store entries(system-wide)
    sudo nix-collect-garbage --delete-older-than 7d
    # garbage collect all unused nix store entries(for the user - home-manager)
    # https://github.com/NixOS/nix/issues/8508
    nix-collect-garbage --delete-older-than 7d

[group('nix')]
fmt:
    # format the nix files in this repo
    nix fmt

# Show all the auto gc roots in the nix store
[group('nix')]
gcroot:
    ls -al /nix/var/nix/gcroots/auto/


# Calculate the sha256 hash of given url
[group('nix')]
hash url:
    nix hash to-sri --type sha256 $(nix-prefetch-url {{url}})
