{ unstablePkgsFor, systems }:

let
  devShellFor =
    system:
    let
      pkgs = unstablePkgsFor system;
      linuxLibraries = with pkgs; [
        fontconfig
        freetype
        libGL
        libxkbcommon
        vulkan-loader
        wayland
      ];
    in
    pkgs.mkShell {
      packages =
        with pkgs;
        [
          cargo
          clippy
          fastfetch
          google-cloud-sdk
          pkg-config
          rust-analyzer
          rustc
          rustfmt
          pkgs.deploy-rs
        ]
        ++ lib.optionals stdenv.isLinux linuxLibraries;

      LD_LIBRARY_PATH = pkgs.lib.optionalString pkgs.stdenv.isLinux (
        pkgs.lib.makeLibraryPath linuxLibraries
      );

      shellHook = ''
        export PATH="$HOME/.local/bin:$PATH"
      '';
    };
in
builtins.listToAttrs (
  map (system: {
    name = system;
    value.default = devShellFor system;
  }) systems
)
