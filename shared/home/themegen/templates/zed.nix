{ lib, pkgs }:

let
  theme = import ./lib.nix { inherit lib; };

  mkSyntaxEntry = color: fontStyle: fontWeight: {
    color = color;
    font_style = fontStyle;
    font_weight = fontWeight;
  };

  mkTheme =
    mode:
    let
      syntaxColors = lib.mapAttrs (_: value: theme.placeholder value) theme.syntax.${mode};
      terminal = theme.terminal mode;
      colors = theme.color.${mode};
      base16Colors = theme.base16.${mode};

      background =
        value:
        if mode == "light" then
          theme.placeholder (theme.lightBackgroundExpression value)
        else
          theme.placeholder value;
      alpha = value: amount: theme.renderAlpha value amount;
      mkState = name: stateColor: background: border: {
        "${name}" = stateColor;
        "${name}.background" = background;
        "${name}.border" = border;
      };

      warningBackground = theme.renderPipeline base16Colors.base0A [
        theme.toHct
        (theme.tone (if mode == "dark" then 28 else 90))
        (theme.withAlpha 80)
        theme.toHex
      ];

      warningBorder = theme.renderPipeline base16Colors.base0A [
        theme.toHct
        (theme.tone (if mode == "dark" then 74 else 36))
        (theme.readable colors.surface_container_low 3.2)
        theme.toHex
      ];
    in
    {
      name = "Themegen ${if mode == "dark" then "Dark" else "Light"}";
      appearance = mode;
      style = {
        accents = [
          (theme.placeholder colors.primary)
          (theme.placeholder colors.secondary)
          (theme.placeholder colors.tertiary)
        ];
        "background.appearance" = "opaque";
        border = theme.placeholder colors.outline_variant;
        "border.variant" = theme.placeholder colors.outline;
        "border.focused" = theme.placeholder colors.primary;
        "border.selected" = theme.placeholder colors.primary;
        "border.transparent" = alpha colors.outline_variant 40;
        "border.disabled" = alpha colors.outline_variant 60;
        "elevated_surface.background" = background colors.surface_container_high;
        "surface.background" = background colors.surface_container;
        background = background colors.background;
        "element.background" = background colors.surface_container;
        "element.hover" = theme.placeholder colors.surface_container_high;
        "element.active" = theme.placeholder colors.surface_container_highest;
        "element.selected" = theme.placeholder colors.secondary_container;
        "element.disabled" = theme.placeholder colors.surface_variant;
        "drop_target.background" = alpha colors.primary_container 80;
        "ghost_element.background" = null;
        "ghost_element.hover" = alpha colors.surface_container 80;
        "ghost_element.active" = theme.placeholder colors.surface_container_high;
        "ghost_element.selected" = alpha colors.secondary_container 80;
        "ghost_element.disabled" = alpha colors.surface_variant 60;
        text = theme.placeholder colors.on_surface;
        "text.muted" = theme.placeholder colors.on_surface_variant;
        "text.placeholder" = alpha colors.on_surface_variant 99;
        "text.disabled" = alpha colors.on_surface 60;
        "text.accent" = theme.placeholder colors.primary;
        icon = theme.placeholder colors.on_surface;
        "icon.muted" = theme.placeholder colors.on_surface_variant;
        "icon.disabled" = alpha colors.on_surface 60;
        "icon.placeholder" = alpha colors.on_surface_variant 80;
        "icon.accent" = theme.placeholder colors.primary;
        "status_bar.background" = background colors.surface;
        "title_bar.background" = background colors.surface;
        "title_bar.inactive_background" = background colors.surface_dim;
        "toolbar.background" = background colors.surface_container_low;
        "tab_bar.background" = background colors.surface_container;
        "tab.inactive_background" = background colors.surface_container;
        "tab.active_background" = background colors.surface_container_low;
        "search.match_background" = alpha colors.tertiary_container 80;
        "panel.background" = background colors.surface_container;
        "panel.focused_border" = theme.placeholder colors.primary;
        "panel.indent_guide" = alpha colors.outline_variant 60;
        "panel.indent_guide_active" = theme.placeholder colors.outline;
        "panel.indent_guide_hover" = alpha colors.outline 80;
        "pane.focused_border" = theme.placeholder colors.primary;
        "pane_group.border" = theme.placeholder colors.outline;
        "scrollbar.thumb.background" = alpha colors.on_surface_variant 80;
        "scrollbar.thumb.hover_background" = alpha colors.on_surface_variant "c0";
        "scrollbar.thumb.border" = alpha colors.outline_variant 40;
        "scrollbar.track.background" = background colors.surface_container;
        "scrollbar.track.border" = alpha colors.outline_variant 20;
        "editor.foreground" = theme.placeholder colors.on_surface;
        "editor.background" = background colors.surface_container_low;
        "editor.gutter.background" = background colors.surface_container_low;
        "editor.subheader.background" = background colors.surface_container;
        "editor.indent_guide" = alpha colors.outline_variant 60;
        "editor.indent_guide_active" = theme.placeholder colors.outline;
        "editor.active_line.background" = alpha colors.surface_container_high 80;
        "editor.highlighted_line.background" = alpha colors.surface_container_high 60;
        "editor.line_number" = theme.placeholder colors.on_surface_variant;
        "editor.active_line_number" = theme.placeholder colors.primary;
        "editor.invisible" = alpha colors.outline_variant 80;
        "editor.wrap_guide" = alpha colors.outline_variant 40;
        "editor.active_wrap_guide" = alpha colors.outline 80;
        "editor.document_highlight.bracket_background" = alpha colors.primary_container 60;
        "editor.document_highlight.read_background" = alpha colors.primary_container 60;
        "editor.document_highlight.write_background" = alpha colors.secondary_container 80;
        "terminal.background" = terminal.background;
        "terminal.ansi.background" = terminal.background;
        "terminal.foreground" = terminal.foreground;
        "terminal.bright_foreground" = terminal.brightForeground;
        "terminal.dim_foreground" = terminal.dimForeground;
        "terminal.ansi.black" = terminal.ansi.black;
        "terminal.ansi.bright_black" = terminal.ansi.brightBlack;
        "terminal.ansi.dim_black" = terminal.dim.black;
        "terminal.ansi.red" = terminal.ansi.red;
        "terminal.ansi.bright_red" = terminal.ansi.brightRed;
        "terminal.ansi.dim_red" = terminal.dim.red;
        "terminal.ansi.green" = terminal.ansi.green;
        "terminal.ansi.bright_green" = terminal.ansi.brightGreen;
        "terminal.ansi.dim_green" = terminal.dim.green;
        "terminal.ansi.yellow" = terminal.ansi.yellow;
        "terminal.ansi.bright_yellow" = terminal.ansi.brightYellow;
        "terminal.ansi.dim_yellow" = terminal.dim.yellow;
        "terminal.ansi.blue" = terminal.ansi.blue;
        "terminal.ansi.bright_blue" = terminal.ansi.brightBlue;
        "terminal.ansi.dim_blue" = terminal.dim.blue;
        "terminal.ansi.magenta" = terminal.ansi.magenta;
        "terminal.ansi.bright_magenta" = terminal.ansi.brightMagenta;
        "terminal.ansi.dim_magenta" = terminal.dim.magenta;
        "terminal.ansi.cyan" = terminal.ansi.cyan;
        "terminal.ansi.bright_cyan" = terminal.ansi.brightCyan;
        "terminal.ansi.dim_cyan" = terminal.dim.cyan;
        "terminal.ansi.white" = terminal.ansi.white;
        "terminal.ansi.bright_white" = terminal.ansi.brightWhite;
        "terminal.ansi.dim_white" = terminal.dim.white;
        "link_text.hover" = theme.placeholder colors.primary;
      }
      // lib.optionalAttrs (mode == "light") {
        "status_bar.foreground" = theme.placeholder colors.on_surface;
        "title_bar.foreground" = theme.placeholder colors.on_surface;
        "title_bar.inactive_foreground" = theme.placeholder colors.on_surface_variant;
        "panel.foreground" = theme.placeholder colors.on_surface;
        "tab.active_foreground" = theme.placeholder colors.on_surface;
        "tab.inactive_foreground" = theme.placeholder colors.on_surface_variant;
      }
      // theme.mergeAll [
        (mkState "conflict" (theme.placeholder colors.error) (alpha colors.error_container 80) (
          theme.placeholder colors.on_error_container
        ))
        (mkState "created" (theme.placeholder colors.tertiary) (alpha colors.tertiary_container 80) (
          theme.placeholder colors.on_tertiary_container
        ))
        (mkState "deleted" (theme.placeholder colors.error) (alpha colors.error_container 80) (
          theme.placeholder colors.on_error_container
        ))
        (mkState "error" (theme.placeholder colors.error) (alpha colors.error_container 80) (
          theme.placeholder colors.on_error_container
        ))
        (mkState "hidden" (theme.placeholder colors.outline_variant) (alpha colors.surface_variant 40) (
          alpha colors.outline_variant 60
        ))
        (mkState "hint" (theme.placeholder colors.primary) (alpha colors.primary_container 80) (
          theme.placeholder colors.on_primary_container
        ))
        (mkState "ignored" (alpha colors.on_surface_variant 60) (alpha colors.surface_variant 40) (
          alpha colors.outline_variant 40
        ))
        (mkState "info" (theme.placeholder colors.primary) (alpha colors.primary_container 80) (
          theme.placeholder colors.on_primary_container
        ))
        (mkState "modified" (theme.placeholder colors.secondary) (alpha colors.secondary_container 80) (
          theme.placeholder colors.on_secondary_container
        ))
        (mkState "renamed" (theme.placeholder colors.secondary) (alpha colors.secondary_container 80) (
          theme.placeholder colors.on_secondary_container
        ))
        (mkState "success" (theme.placeholder colors.tertiary) (alpha colors.tertiary_container 80) (
          theme.placeholder colors.on_tertiary_container
        ))
        (mkState "unreachable" (alpha colors.on_surface_variant 60) (alpha colors.surface_variant 40) (
          alpha colors.outline_variant 60
        ))
        (mkState "warning" (theme.placeholder base16Colors.base0A) warningBackground warningBorder)
      ]
      // {
        predictive = syntaxColors.predictive;
        "predictive.border" = theme.placeholder colors.outline;
        "predictive.background" = alpha colors.surface_container_highest 80;
        players = [
          {
            cursor = theme.placeholder colors.primary;
            background = alpha colors.primary_container 80;
            selection = alpha colors.primary_container 60;
          }
          {
            cursor = theme.placeholder colors.secondary;
            background = alpha colors.secondary_container 80;
            selection = alpha colors.secondary_container 60;
          }
        ];
        syntax = rec {
          boolean = mkSyntaxEntry syntaxColors.literal null null;
          comment = mkSyntaxEntry syntaxColors.comment "italic" null;
          "comment.doc" = mkSyntaxEntry syntaxColors.comment "italic" null;
          constant = mkSyntaxEntry syntaxColors.literal null null;
          constructor = mkSyntaxEntry syntaxColors.type null null;
          emphasis = mkSyntaxEntry syntaxColors.emphasis "italic" null;
          "emphasis.strong" = mkSyntaxEntry syntaxColors.emphasis null 700;
          function = mkSyntaxEntry syntaxColors.function null null;
          keyword = mkSyntaxEntry syntaxColors.keyword null null;
          number = mkSyntaxEntry syntaxColors.literal null null;
          operator = mkSyntaxEntry syntaxColors.operator null null;
          property = mkSyntaxEntry syntaxColors.variable null null;
          punctuation = mkSyntaxEntry syntaxColors.punctuation null null;
          "punctuation.bracket" = mkSyntaxEntry (theme.placeholder colors.on_surface) null null;
          "punctuation.delimiter" = mkSyntaxEntry syntaxColors.punctuation null null;
          "punctuation.list_marker" = mkSyntaxEntry syntaxColors.punctuation null null;
          "punctuation.special" = mkSyntaxEntry syntaxColors.number null null;
          string = mkSyntaxEntry syntaxColors.string null null;
          "string.escape" = mkSyntaxEntry syntaxColors.stringSpecial null null;
          "string.regex" = mkSyntaxEntry syntaxColors.stringRegex null null;
          "string.special" = mkSyntaxEntry syntaxColors.stringSpecial null null;
          "string.special.symbol" = mkSyntaxEntry syntaxColors.stringSpecial null null;
          tag = mkSyntaxEntry syntaxColors.variable null null;
          "text.literal" = mkSyntaxEntry syntaxColors.string null null;
          type = mkSyntaxEntry syntaxColors.type null null;
          variable = mkSyntaxEntry syntaxColors.variable null null;
          "variable.special" = mkSyntaxEntry syntaxColors.number null null;
          attribute = mkSyntaxEntry syntaxColors.title null null;
          embedded = mkSyntaxEntry syntaxColors.string null null;
          enum = mkSyntaxEntry syntaxColors.type null null;
          hint = mkSyntaxEntry (theme.placeholder colors.primary) null null;
          label = mkSyntaxEntry syntaxColors.variable null null;
          lifetime.color = constant.color;
          link_text = mkSyntaxEntry (theme.placeholder colors.primary) null null;
          link_uri = mkSyntaxEntry syntaxColors.link null null;
          namespace = mkSyntaxEntry syntaxColors.type null null;
          predictive = mkSyntaxEntry syntaxColors.predictive null null;
          preproc = mkSyntaxEntry syntaxColors.number null null;
          primary = mkSyntaxEntry (theme.placeholder colors.on_surface) null null;
          "punctuation.markup" = mkSyntaxEntry syntaxColors.number null null;
          selector = mkSyntaxEntry syntaxColors.variable null null;
          "selector.pseudo" = mkSyntaxEntry syntaxColors.number null null;
          title = mkSyntaxEntry syntaxColors.title null null;
          variant = mkSyntaxEntry syntaxColors.type null null;
        }
        // lib.optionalAttrs (mode == "light") {
          "keyword.control" = mkSyntaxEntry syntaxColors.keyword null null;
        };
      };
    };

  zedThemes = pkgs.writeText "themegen-zed-themes.json" (
    builtins.toJSON {
      "$schema" = "https://zed.dev/schema/themes/v0.2.0.json";
      name = "themegen";
      author = "themegen";
      themes = [
        (mkTheme "dark")
        (mkTheme "light")
      ];
    }
    + "\n"
  );
in
{
  generated = [
    (theme.mkRenderedFile {
      template = zedThemes;
      output = "zed/themes/themegen.json";
    })
  ];

  homeFiles = [
    (theme.mkHomeFile {
      target = ".config/zed/themes/themegen.json";
      source = "zed/themes/themegen.json";
    })
  ];
}
