{ inputs, dotfiles }:

[
  (import (dotfiles + /hosts/m3air/host.nix) { inherit inputs dotfiles; })
  (import (dotfiles + /hosts/framework/host.nix) { inherit inputs dotfiles; })
  (import (dotfiles + /hosts/homolab/host.nix) { inherit inputs dotfiles; })
  (import (dotfiles + /hosts/gce-dns/host.nix) { inherit inputs dotfiles; })
]
