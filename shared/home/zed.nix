{ pkgs, ... }:

{
  programs.zed-editor = {
    enable = true;
    extraPackages = with pkgs; [
      nil
      nixfmt
    ];

    userSettings = {
      project_panel.sort_mode = "directories_first";
      git_panel = {
        sort_by_path = true;
        tree_view = true;
      };

      base_keymap = "Emacs";
      vim_mode = true;

      theme = {
        mode = "system";
        light = "Gruvbox Light";
        dark = "VSCode Dark Polished";
      };
      icon_theme = {
        mode = "dark";
        light = "Material Icon Theme";
        dark = "Material Icon Theme";
      };

      agent = {
        default_profile = "minimal";
        use_modifier_to_send = true;
      };

      auto_install_extensions = builtins.listToAttrs (
        map
          (name: {
            inherit name;
            value = true;
          })
          [
            "nix"
            "ocaml"
            "dockerfile"
            "docker-compose"
            "toml"
            "haskell"
            "make"
            "zig"
            "rainbow-csv"
            "vscode-dark-polished"
            "material-icon-theme"
          ]
      );

      autosave = "on_focus_change";

      buffer_font_family = "Cascadia Code NF";
      buffer_font_features.ss19 = true;
      buffer_font_size = 16;
      buffer_font_weight = 400;
      ui_font_family = ".SystemUIFont";
      ui_font_size = 18;
      terminal.line_height.custom = 1.18;

      indent_guides = {
        enabled = true;
        coloring = "indent_aware";
      };

      inlay_hints.enabled = true;

      file_types = {
        Dockerfile = [
          "Dockerfile"
          "Dockerfile.*"
        ];
        JSON = [
          "json"
          "jsonc"
          "*.code-snippets"
        ];
      };

      file_scan_exclusions = [
        "**/.git"
        "**/.svn"
        "**/.hg"
        "**/CVS"
        "**/.DS_Store"
        "**/Thumbs.db"
        "**/.classpath"
        "**/.settings"
        "**/out"
        "**/dist"
        "**/.husky"
        "**/.turbo"
        "**/.vscode*"
        "**/.next"
        "**/.storybook"
        "**/.tap"
        "**/.nyc_output"
        "**/report"
        "**/node_modules"
      ];

      telemetry = {
        diagnostics = false;
        metrics = false;
      };

      lsp = {
        hls.initialization_options.haskell.formattingProvider = "fourmolu";
        rust-analyzer.initialization_options = {
          checkOnSave = true;
          inlayHints = {
            implicitDrops.enable = true;
            maxLength = 100;
            closureReturnTypeHints.enable = "always";
            lifetimeElisionHints = {
              enable = "skip_trivial";
              useParameterNames = true;
            };
          };
        };
      };

      languages.Nix = {
        language_servers = [
          "nil"
          "!nixd"
        ];
        formatter.external.command = "nixfmt .";
      };
    };
  };
}
