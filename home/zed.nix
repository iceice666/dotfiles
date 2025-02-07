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
      buffer_font_family = "CaskaydiaCove Nerd Font";
      buffer_font_size = 16;
      ui_font_size = 16;
      terminal = {
        line_height = "standard";
      };

      # Indentation, rainbow indentation
      indent_guides = {
        enabled = true;
        coloring = "indent_aware";
      };

      # Use Copilot Chat AI as default
      assistant = {
        default_model = {
          provider = "copilot_chat";
          model = "claude-3-5-sonnet";
        };
        version = 2;
      };

      inlay_hints = {
        enabled = true;
      };

      # File syntax highlighting
      file_types = {
        Dockerfile = ["Dockerfile" "Dockerfile.*"];
        JSON = ["json" "jsonc" "*.code-snippets"];
      };

      #File scan exclusions, hide on the file explorer and search
      file_scan_exclusions = [
        "**/.git"
        "**/.svn"
        "**/.hg"
        "**/CVS"
        "**/.DS_Store"
        "**/Thumbs.db"
        "**/.classpath"
        "**/.settings"
        # above is default from Zed
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

      # Turn off telemetry
      telemetry = {
        diagnostics = false;
        metrics = false;
      };

      inline_completions = {
        disabled_globs = [
          "**/.env*"
          "**/*.pem"
          "**/*.key"
          "**/*.cert"
          "**/*.crt"
          "**/secrets.yml"
        ];
      };

      vim_mode = true;

      # LSP
      languages = {
        Nix = {
          language_servers = [
            "nil"
            "!nixd"
          ];
          formatter = {
            external = {
              command = "just fmt";
            };
          };
        };
      };
    };
  };
}
