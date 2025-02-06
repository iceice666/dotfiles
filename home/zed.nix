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
      autosave = "on_focus_change";
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
