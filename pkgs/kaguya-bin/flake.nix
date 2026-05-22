{
  description = "Kaguya browser binary package";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    kaguya-cache = {
      url = "path:./empty-cache";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      kaguya-cache,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      package = pkgs.callPackage ./default.nix { src = kaguya-cache; };
    in
    {
      packages.${system} = {
        default = package;
        kaguya-bin = package;
      };

      apps.${system}.default = {
        type = "app";
        program = "${package}/bin/kaguya";
        meta.description = "Run Kaguya browser";
      };

      overlays.default = final: _prev: {
        kaguya-bin = final.callPackage ./default.nix { src = kaguya-cache; };
      };
    };
}
