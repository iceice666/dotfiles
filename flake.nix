{
  description = "The entrypoint for the system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

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

    nirinit = {
      url = "github:amaanq/nirinit";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri-scratchpad-helper = {
      url = "github:gvolpe/niri-scratchpad";
      flake = false;
    };

    tempestmiku.url = "github:mozufu/TempestMiku/52c4be161f3e6966acce8e00d31297b8a83a72c5";

    reimu-on-starlit-water = {
      url = "github:iceice666/reimu_on_starlit_water";
      flake = false;
    };

    kaguya-cache = {
      url = "git+file:.?dir=pkgs/kaguya-bin/empty-cache";
      flake = false;
    };

    kaguya-browser = {
      url = "git+file:.?dir=pkgs/kaguya-bin";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.kaguya-cache.follows = "kaguya-cache";
    };

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    inputs:
    import ./lib/flake {
      inherit inputs;
      dotfiles = ./.;
    };
}
