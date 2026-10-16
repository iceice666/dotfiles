{
  description = "The entrypoint for the system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    xlibre-overlay.url = "git+https://codeberg.org/takagemacoed/xlibre-overlay?ref=dev-for-26.05";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ags = {
      url = "github:Aylur/ags/v3.1.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ghostty.url = "github:iceice666/ghostty/4df2074389ca6404d37564b05a6bef1f55bb284d";

    niri-scratchpad-helper = {
      url = "github:gvolpe/niri-scratchpad";
      flake = false;
    };

    pirc = {
      url = "github:iceice666/pirc";
      # pirc's bun.lock needs Bun 1.4, which the stable channel lacks.
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    reimu-on-starlit-water = {
      url = "github:iceice666/reimu_on_starlit_water";
      flake = false;
    };

  };

  outputs =
    inputs:
    import ./lib/flake {
      inherit inputs;
      dotfiles = ./.;
    };
}
