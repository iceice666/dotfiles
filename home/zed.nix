{pkgs, ...}: let
  themeRepo = pkgs.fetchFromGitHub {
    owner = "iceice666";
    repo = "SoftColors";
    rev = "master";
    sha256 = "sha256-3ThNMY3nrCxnkGjnb58dyGbSb9cag8J0r0TbNIRWPL8=";
  };
in {
  home.file.".config/zed/themes/soft_color.json".source = "${themeRepo}/themes/zed.jsonc";

  programs.zed-editor = {
    enable = true;

    extensions = [
      "nix"
      "ocaml"
      "dockerfile"
      "docker-compose"
      "nu"
    ];

    userSettings = {
      autosave = "on_focus_change";
      buffer_font_family = "CaskaydiaCove Nerd Font";
      buffer_font_size = 16;
      ui_font_size = 16;
      terminal = {
        line_height = {
          custom = 1.20;
        };
      };

      theme = {
        mode = "system";
        light = "Rose Quartz";
        dark = "Rosé Pine";
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
