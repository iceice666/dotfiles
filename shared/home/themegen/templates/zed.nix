{ lib, pkgs }:

let
  t = import ./lib.nix { inherit lib; };

  mkSyntaxEntry = color: fontStyle: fontWeight: {
    color = color;
    font_style = fontStyle;
    font_weight = fontWeight;
  };

  mkTheme =
    mode:
    let
      syntax = t.syntax mode;
      terminal = t.terminal mode;

      color = token: t.render (t.colorExpr mode token);
      colorExpr = token: t.colorExpr mode token;
      base16 = token: t.render (t.base16Expr mode token);
      base16Expr = token: t.base16Expr mode token;
      alpha = token: amount: t.alpha (colorExpr token) amount;

      mkState = name: stateColor: background: border: {
        "${name}" = stateColor;
        "${name}.background" = background;
        "${name}.border" = border;
      };

      warningBackground = t.renderPipe (base16Expr "base0A") [
        t.toHctStep
        (t.toneStep (if mode == "dark" then 28 else 90))
        (t.withAlphaStep 80)
        t.toHexStep
      ];

      warningBorder = t.renderPipe (base16Expr "base0A") [
        t.toHctStep
        (t.toneStep (if mode == "dark" then 74 else 36))
        (t.call "readable" [
          (colorExpr "surface_container_low")
          3.2
        ])
        t.toHexStep
      ];
    in
    {
      name = "Themegen ${if mode == "dark" then "Dark" else "Light"}";
      appearance = mode;
      style = {
        accents = [
          (color "primary")
          (color "secondary")
          (color "tertiary")
        ];
        "background.appearance" = "opaque";
        border = color "outline_variant";
        "border.variant" = color "outline";
        "border.focused" = color "primary";
        "border.selected" = color "primary";
        "border.transparent" = alpha "outline_variant" 40;
        "border.disabled" = alpha "outline_variant" 60;
        "elevated_surface.background" = color "surface_container_high";
        "surface.background" = color "surface_container";
        background = color "background";
        "element.background" = color "surface_container";
        "element.hover" = color "surface_container_high";
        "element.active" = color "surface_container_highest";
        "element.selected" = color "secondary_container";
        "element.disabled" = color "surface_variant";
        "drop_target.background" = alpha "primary_container" 80;
        "ghost_element.background" = null;
        "ghost_element.hover" = alpha "surface_container" 80;
        "ghost_element.active" = color "surface_container_high";
        "ghost_element.selected" = alpha "secondary_container" 80;
        "ghost_element.disabled" = alpha "surface_variant" 60;
        text = color "on_surface";
        "text.muted" = color "on_surface_variant";
        "text.placeholder" = alpha "on_surface_variant" 99;
        "text.disabled" = alpha "on_surface" 60;
        "text.accent" = color "primary";
        icon = color "on_surface";
        "icon.muted" = color "on_surface_variant";
        "icon.disabled" = alpha "on_surface" 60;
        "icon.placeholder" = alpha "on_surface_variant" 80;
        "icon.accent" = color "primary";
        "status_bar.background" = color "surface";
        "title_bar.background" = color "surface";
        "title_bar.inactive_background" = color "surface_dim";
        "toolbar.background" = color "surface_container_low";
        "tab_bar.background" = color "surface_container";
        "tab.inactive_background" = color "surface_container";
        "tab.active_background" = color "surface_container_low";
        "search.match_background" = alpha "tertiary_container" 80;
        "panel.background" = color "surface_container";
        "panel.focused_border" = color "primary";
        "panel.indent_guide" = alpha "outline_variant" 60;
        "panel.indent_guide_active" = color "outline";
        "panel.indent_guide_hover" = alpha "outline" 80;
        "pane.focused_border" = color "primary";
        "pane_group.border" = color "outline";
        "scrollbar.thumb.background" = alpha "on_surface_variant" 80;
        "scrollbar.thumb.hover_background" = alpha "on_surface_variant" "c0";
        "scrollbar.thumb.border" = alpha "outline_variant" 40;
        "scrollbar.track.background" = color "surface_container";
        "scrollbar.track.border" = alpha "outline_variant" 20;
        "editor.foreground" = color "on_surface";
        "editor.background" = color "surface_container_low";
        "editor.gutter.background" = color "surface_container_low";
        "editor.subheader.background" = color "surface_container";
        "editor.indent_guide" = alpha "outline_variant" 60;
        "editor.indent_guide_active" = color "outline";
        "editor.active_line.background" = alpha "surface_container_high" 80;
        "editor.highlighted_line.background" = alpha "surface_container_high" 60;
        "editor.line_number" = color "on_surface_variant";
        "editor.active_line_number" = color "primary";
        "editor.invisible" = alpha "outline_variant" 80;
        "editor.wrap_guide" = alpha "outline_variant" 40;
        "editor.active_wrap_guide" = alpha "outline" 80;
        "editor.document_highlight.bracket_background" = alpha "primary_container" 60;
        "editor.document_highlight.read_background" = alpha "primary_container" 60;
        "editor.document_highlight.write_background" = alpha "secondary_container" 80;
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
        "link_text.hover" = color "primary";
      }
      // lib.optionalAttrs (mode == "light") {
        "status_bar.foreground" = color "on_surface";
        "title_bar.foreground" = color "on_surface";
        "title_bar.inactive_foreground" = color "on_surface_variant";
        "panel.foreground" = color "on_surface";
        "tab.active_foreground" = color "on_surface";
        "tab.inactive_foreground" = color "on_surface_variant";
      }
      // t.mergeAll [
        (mkState "conflict" (color "error") (alpha "error_container" 80) (color "on_error_container"))
        (mkState "created" (color "tertiary") (alpha "tertiary_container" 80) (
          color "on_tertiary_container"
        ))
        (mkState "deleted" (color "error") (alpha "error_container" 80) (color "on_error_container"))
        (mkState "error" (color "error") (alpha "error_container" 80) (color "on_error_container"))
        (mkState "hidden" (color "outline_variant") (alpha "surface_variant" 40) (
          alpha "outline_variant" 60
        ))
        (mkState "hint" (color "primary") (alpha "primary_container" 80) (color "on_primary_container"))
        (mkState "ignored" (alpha "on_surface_variant" 60) (alpha "surface_variant" 40) (
          alpha "outline_variant" 40
        ))
        (mkState "info" (color "primary") (alpha "primary_container" 80) (color "on_primary_container"))
        (mkState "modified" (color "secondary") (alpha "secondary_container" 80) (
          color "on_secondary_container"
        ))
        (mkState "renamed" (color "secondary") (alpha "secondary_container" 80) (
          color "on_secondary_container"
        ))
        (mkState "success" (color "tertiary") (alpha "tertiary_container" 80) (
          color "on_tertiary_container"
        ))
        (mkState "unreachable" (alpha "on_surface_variant" 60) (alpha "surface_variant" 40) (
          alpha "outline_variant" 60
        ))
        (mkState "warning" (base16 "base0A") warningBackground warningBorder)
      ]
      // {
        predictive = syntax.predictive;
        "predictive.border" = color "outline";
        "predictive.background" = alpha "surface_container_highest" 80;
        players = [
          {
            cursor = color "primary";
            background = alpha "primary_container" 80;
            selection = alpha "primary_container" 60;
          }
          {
            cursor = color "secondary";
            background = alpha "secondary_container" 80;
            selection = alpha "secondary_container" 60;
          }
        ];
        syntax = {
          boolean = mkSyntaxEntry syntax.boolean null null;
          comment = mkSyntaxEntry syntax.comment "italic" null;
          "comment.doc" = mkSyntaxEntry syntax.comment "italic" null;
          constant = mkSyntaxEntry syntax.number null null;
          constructor = mkSyntaxEntry syntax.type null null;
          emphasis = mkSyntaxEntry syntax.emphasis "italic" null;
          "emphasis.strong" = mkSyntaxEntry syntax.emphasis null 700;
          function = mkSyntaxEntry syntax.function null null;
          keyword = mkSyntaxEntry syntax.keyword null null;
          number = mkSyntaxEntry syntax.number null null;
          operator = mkSyntaxEntry syntax.operator null null;
          property = mkSyntaxEntry syntax.variable null null;
          punctuation = mkSyntaxEntry syntax.punctuation null null;
          "punctuation.bracket" = mkSyntaxEntry (color "on_surface") null null;
          "punctuation.delimiter" = mkSyntaxEntry syntax.punctuation null null;
          "punctuation.list_marker" = mkSyntaxEntry syntax.punctuation null null;
          "punctuation.special" = mkSyntaxEntry syntax.number null null;
          string = mkSyntaxEntry syntax.string null null;
          "string.escape" = mkSyntaxEntry syntax.link null null;
          "string.regex" = mkSyntaxEntry syntax.stringRegex null null;
          "string.special" = mkSyntaxEntry syntax.link null null;
          "string.special.symbol" = mkSyntaxEntry syntax.link null null;
          tag = mkSyntaxEntry syntax.variable null null;
          "text.literal" = mkSyntaxEntry syntax.string null null;
          type = mkSyntaxEntry syntax.type null null;
          variable = mkSyntaxEntry syntax.variable null null;
          "variable.special" = mkSyntaxEntry syntax.number null null;
          attribute = mkSyntaxEntry syntax.title null null;
          embedded = mkSyntaxEntry syntax.string null null;
          enum = mkSyntaxEntry syntax.type null null;
          hint = mkSyntaxEntry (color "primary") null null;
          label = mkSyntaxEntry syntax.variable null null;
          link_text = mkSyntaxEntry (color "primary") null null;
          link_uri = mkSyntaxEntry syntax.link null null;
          namespace = mkSyntaxEntry syntax.type null null;
          predictive = mkSyntaxEntry syntax.predictive null null;
          preproc = mkSyntaxEntry syntax.number null null;
          primary = mkSyntaxEntry (color "on_surface") null null;
          "punctuation.markup" = mkSyntaxEntry syntax.number null null;
          selector = mkSyntaxEntry syntax.variable null null;
          "selector.pseudo" = mkSyntaxEntry syntax.number null null;
          title = mkSyntaxEntry syntax.title null null;
          variant = mkSyntaxEntry syntax.type null null;
        }
        // lib.optionalAttrs (mode == "light") {
          "keyword.control" = mkSyntaxEntry syntax.keyword null null;
          lifetime = mkSyntaxEntry syntax.type null null;
        };
      };
    };
in
pkgs.writeText "themegen-zed-themes.json" (
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
)
