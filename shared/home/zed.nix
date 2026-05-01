{ pkgs, unstablePkgs, ... }:

{
  programs.zed-editor = {
    enable = true;
    package = pkgs.zed-bin;
    extraPackages = with pkgs; [
      nil
      nixfmt
    ];

    userKeymaps = [
      {
        context = "vim_mode == visual";
        bindings = {
          "shift-s" = [
            "vim::PushAddSurrounds"
            { }
          ];
        };
      }
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
        light = "Themegen Light";
        dark = "Themegen Dark";
      };
      semantic_tokens = "combined";
      icon_theme = {
        mode = "system";
        light = "Colored Zed Icons Theme Light";
        dark = "Colored Zed Icons Theme Dark";
      };

      global_lsp_settings = {
        semantic_token_rules = [
          {
            token_type = "comment";
            token_modifiers = [ "documentation" ];
            style = [
              "comment.doc"
              "comment"
            ];
          }
          {
            token_type = "variable";
            token_modifiers = [ "constant" ];
            style = [
              "constant"
              "variable"
            ];
          }
          {
            token_type = "variable";
            token_modifiers = [ "readonly" ];
            style = [
              "constant"
              "variable"
            ];
          }
          {
            token_type = "property";
            token_modifiers = [ "readonly" ];
            style = [
              "constant"
              "property"
            ];
          }
          {
            token_type = "function";
            token_modifiers = [ "defaultLibrary" ];
            style = [ "function" ];
          }
          {
            token_type = "method";
            token_modifiers = [ "defaultLibrary" ];
            style = [ "function" ];
          }
          {
            token_type = "type";
            token_modifiers = [ "defaultLibrary" ];
            style = [ "type" ];
          }
          {
            token_type = "variable";
            token_modifiers = [ "defaultLibrary" ];
            style = [ "variable" ];
          }
          {
            token_type = "class";
            style = [ "type" ];
          }
          {
            token_type = "comment";
            style = [ "comment" ];
          }
          {
            token_type = "decorator";
            style = [
              "preproc"
              "attribute"
            ];
          }
          {
            token_type = "enum";
            style = [
              "enum"
              "type"
            ];
          }
          {
            token_type = "enumMember";
            style = [
              "constant"
              "enum"
            ];
          }
          {
            token_type = "event";
            style = [
              "label"
              "variable"
            ];
          }
          {
            token_type = "function";
            style = [ "function" ];
          }
          {
            token_type = "interface";
            style = [ "type" ];
          }
          {
            token_type = "keyword";
            style = [ "keyword" ];
          }
          {
            token_type = "label";
            style = [
              "label"
              "variable"
            ];
          }
          {
            token_type = "macro";
            style = [ "preproc" ];
          }
          {
            token_type = "method";
            style = [ "function" ];
          }
          {
            token_type = "namespace";
            style = [
              "namespace"
              "type"
            ];
          }
          {
            token_type = "number";
            style = [
              "number"
              "constant"
            ];
          }
          {
            token_type = "operator";
            style = [ "operator" ];
          }
          {
            token_type = "parameter";
            style = [ "variable" ];
          }
          {
            token_type = "property";
            style = [
              "property"
              "variable"
            ];
          }
          {
            token_type = "regexp";
            style = [
              "string.regex"
              "string"
            ];
          }
          {
            token_type = "string";
            style = [ "string" ];
          }
          {
            token_type = "struct";
            style = [ "type" ];
          }
          {
            token_type = "type";
            style = [ "type" ];
          }
          {
            token_type = "typeParameter";
            style = [ "type" ];
          }
          {
            token_type = "variable";
            style = [ "variable" ];
          }
        ];
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
            "gleam"
            "dockerfile"
            "docker-compose"
            "toml"
            "haskell"
            "make"
            "zig"
            "rainbow-csv"
            "colored-zed-icons-theme"
            "fish"
            "just"
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
        "**/dist*"
        "**/.husky"
        "**/.turbo"
        "**/.vscode*"
        "**/.next"
        "**/.storybook"
        "**/.tap"
        "**/.nyc_output"
        "**/.direnv"
        "**/.devenv"
        "**/report"
        "**/node_modules"
      ];

      telemetry = {
        diagnostics = false;
        metrics = false;
      };

      lsp = {
        rust-analyzer.initialization_options = {
          checkOnSave = true;
          inlayHints = {
            implicitDrops.enable = true;
            maxLength = 30;
            closureReturnTypeHints.enable = "always";
            lifetimeElisionHints = {
              enable = "skip_trivial";
              useParameterNames = true;
            };
          };
        };

        zls.binary = {
          ignore_system_version = true;
          path = "${if pkgs.stdenv.hostPlatform.isLinux then pkgs.mise else unstablePkgs.mise-bin}/bin/mise";
          arguments = [
            "x"
            "--"
            "zls"
          ];
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
