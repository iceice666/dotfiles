{...}: {
  programs.zed-editor = {
    enable = true;

    extensions = [
      "nix"
      "ocaml"
      "dockerfile"
      "docker-compose"
    ];


    userSettings = {
      languages = {
        Nix = {
          language_servers = [
            "nil"
            "!nixd"
          ];
          formatter = {
            external = {
              command = "nixfmt";
            };
          };
        };
      };
    };
  };
}
