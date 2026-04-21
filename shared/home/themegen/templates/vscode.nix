{ lib, pkgs }:

let
  t = import ./lib.nix { inherit lib; };

  mkSettings =
    foreground: fontStyle:
    { inherit foreground; } // lib.optionalAttrs (fontStyle != null) { inherit fontStyle; };

  mkTokenColor = name: scope: foreground: fontStyle: {
    inherit name scope;
    settings = mkSettings foreground fontStyle;
  };

  mkSemanticColor = foreground: {
    inherit foreground;
  };

  mkTheme =
    mode:
    let
      colors = t.color.${mode};
      base16Colors = t.base16.${mode};
      syntax = lib.mapAttrs (_: value: t.render value) t.syntax.${mode};
      terminal = t.terminal mode;

      background =
        value: if mode == "light" then t.render (t.seededLightBackground value) else t.render value;
      alpha = value: amount: t.alpha value amount;

      themeName = "Themegen ${if mode == "dark" then "Dark" else "Light"}";
      warning = t.render base16Colors.base0A;
    in
    {
      "$schema" = "vscode://schemas/color-theme";
      name = themeName;
      type = mode;
      semanticHighlighting = true;
      colors = {
        disabledForeground = alpha colors.on_surface_variant 80;
        descriptionForeground = t.render colors.on_surface_variant;
        errorForeground = t.render colors.error;
        "focusBorder" = t.render colors.primary;
        "foreground" = t.render colors.on_surface;
        "icon.foreground" = t.render colors.on_surface;
        "selection.background" = alpha colors.primary_container 80;
        "sash.hoverBorder" = t.render colors.primary;
        "textBlockQuote.background" = alpha colors.surface_variant 60;
        "textBlockQuote.border" = alpha colors.outline_variant 80;
        "textCodeBlock.background" = background colors.surface_container_high;
        "textLink.foreground" = t.render colors.primary;
        "textLink.activeForeground" = t.render colors.primary;
        "textPreformat.foreground" = syntax.string;
        "textSeparator.foreground" = alpha colors.outline_variant 60;
        "widget.shadow" = alpha colors.outline_variant 40;

        "button.background" = t.render colors.primary;
        "button.foreground" = t.render colors.on_primary;
        "button.hoverBackground" = alpha colors.primary 90;
        "button.secondaryBackground" = background colors.secondary_container;
        "button.secondaryForeground" = t.render colors.on_secondary_container;
        "button.secondaryHoverBackground" = alpha colors.secondary_container 90;

        "badge.background" = t.render colors.primary;
        "badge.foreground" = t.render colors.on_primary;
        "progressBar.background" = t.render colors.primary;

        "dropdown.background" = background colors.surface_container_high;
        "dropdown.border" = alpha colors.outline_variant 80;
        "dropdown.foreground" = t.render colors.on_surface;
        "input.background" = background colors.surface_container_high;
        "input.border" = alpha colors.outline_variant 80;
        "input.foreground" = t.render colors.on_surface;
        "input.placeholderForeground" = alpha colors.on_surface_variant 99;
        "inputOption.activeBackground" = alpha colors.primary_container 80;
        "inputOption.activeBorder" = t.render colors.primary;
        "inputValidation.errorBackground" = alpha colors.error_container 80;
        "inputValidation.errorBorder" = t.render colors.error;
        "inputValidation.infoBackground" = alpha colors.primary_container 80;
        "inputValidation.infoBorder" = t.render colors.primary;
        "inputValidation.warningBackground" = alpha base16Colors.base0A 80;
        "inputValidation.warningBorder" = warning;

        "scrollbar.shadow" = alpha colors.outline_variant 30;
        "scrollbarSlider.background" = alpha colors.on_surface_variant 80;
        "scrollbarSlider.hoverBackground" = alpha colors.on_surface_variant "c0";
        "scrollbarSlider.activeBackground" = alpha colors.on_surface "c0";

        "list.activeSelectionBackground" = alpha colors.primary_container 80;
        "list.activeSelectionForeground" = t.render colors.on_surface;
        "list.focusBackground" = alpha colors.primary_container 80;
        "list.focusForeground" = t.render colors.on_surface;
        "list.highlightForeground" = t.render colors.primary;
        "list.hoverBackground" = alpha colors.surface_container_high 80;
        "list.hoverForeground" = t.render colors.on_surface;
        "list.inactiveSelectionBackground" = alpha colors.surface_container_high 90;
        "list.inactiveSelectionForeground" = t.render colors.on_surface;
        "list.warningForeground" = warning;
        "list.errorForeground" = t.render colors.error;
        "tree.indentGuidesStroke" = alpha colors.outline_variant 60;

        "activityBar.background" = background colors.surface_container_low;
        "activityBar.foreground" = t.render colors.on_surface;
        "activityBar.inactiveForeground" = t.render colors.on_surface_variant;
        "activityBar.activeBorder" = t.render colors.primary;
        "activityBarBadge.background" = t.render colors.primary;
        "activityBarBadge.foreground" = t.render colors.on_primary;

        "sideBar.background" = background colors.surface_container;
        "sideBar.border" = alpha colors.outline_variant 40;
        "sideBar.foreground" = t.render colors.on_surface;
        "sideBarSectionHeader.background" = background colors.surface_container_low;
        "sideBarSectionHeader.foreground" = t.render colors.on_surface;
        "sideBarTitle.foreground" = t.render colors.on_surface;

        "titleBar.activeBackground" = background colors.surface;
        "titleBar.activeForeground" = t.render colors.on_surface;
        "titleBar.border" = alpha colors.outline_variant 40;
        "titleBar.inactiveBackground" = background colors.surface_dim;
        "titleBar.inactiveForeground" = t.render colors.on_surface_variant;

        "statusBar.background" = background colors.surface;
        "statusBar.border" = alpha colors.outline_variant 40;
        "statusBar.foreground" = t.render colors.on_surface;
        "statusBar.debuggingBackground" = alpha colors.tertiary_container 90;
        "statusBar.debuggingForeground" = t.render colors.on_tertiary_container;
        "statusBar.noFolderBackground" = background colors.surface;
        "statusBar.noFolderForeground" = t.render colors.on_surface;
        "statusBarItem.hoverBackground" = alpha colors.surface_container_high 80;
        "statusBarItem.prominentBackground" = alpha colors.surface_container_highest 80;

        "panel.background" = background colors.surface_container;
        "panel.border" = alpha colors.outline_variant 40;
        "panelInput.border" = alpha colors.outline_variant 80;
        "panelTitle.activeBorder" = t.render colors.primary;
        "panelTitle.activeForeground" = t.render colors.on_surface;
        "panelTitle.inactiveForeground" = t.render colors.on_surface_variant;

        "editorGroup.border" = alpha colors.outline_variant 40;
        "editorGroupHeader.tabsBackground" = background colors.surface_container;
        "tab.activeBackground" = background colors.surface_container_low;
        "tab.activeBorderTop" = t.render colors.primary;
        "tab.activeForeground" = t.render colors.on_surface;
        "tab.border" = alpha colors.outline_variant 40;
        "tab.hoverBackground" = alpha colors.surface_container_high 80;
        "tab.inactiveBackground" = background colors.surface_container;
        "tab.inactiveForeground" = t.render colors.on_surface_variant;
        "tab.unfocusedActiveBorderTop" = alpha colors.primary 80;

        "editor.background" = background colors.surface_container_low;
        "editor.foreground" = t.render colors.on_surface;
        "editor.findMatchBackground" = alpha colors.tertiary_container 90;
        "editor.findMatchBorder" = t.render colors.tertiary;
        "editor.findMatchHighlightBackground" = alpha colors.tertiary_container 60;
        "editor.findMatchHighlightBorder" = alpha colors.tertiary 80;
        "editor.hoverHighlightBackground" = alpha colors.primary_container 40;
        "editor.inactiveSelectionBackground" = alpha colors.surface_variant 80;
        "editor.lineHighlightBackground" = alpha colors.surface_container_high 80;
        "editor.rangeHighlightBackground" = alpha colors.secondary_container 60;
        "editor.selectionBackground" = alpha colors.primary_container 80;
        "editor.selectionHighlightBackground" = alpha colors.secondary_container 60;
        "editor.wordHighlightBackground" = alpha colors.primary_container 60;
        "editor.wordHighlightStrongBackground" = alpha colors.secondary_container 80;
        "editorBracketMatch.background" = alpha colors.primary_container 60;
        "editorBracketMatch.border" = alpha colors.primary 80;
        "editorCodeLens.foreground" = t.render colors.on_surface_variant;
        "editorCursor.background" = t.render colors.on_primary;
        "editorCursor.foreground" = t.render colors.primary;
        "editorError.foreground" = t.render colors.error;
        "editorHint.foreground" = t.render colors.primary;
        "editorIndentGuide.activeBackground1" = alpha colors.outline 80;
        "editorIndentGuide.background1" = alpha colors.outline_variant 60;
        "editorInfo.foreground" = t.render colors.primary;
        "editorLineNumber.activeForeground" = t.render colors.primary;
        "editorLineNumber.foreground" = t.render colors.on_surface_variant;
        "editorLink.activeForeground" = t.render colors.primary;
        "editorRuler.foreground" = alpha colors.outline_variant 50;
        "editorStickyScroll.background" = background colors.surface_container;
        "editorStickyScroll.border" = alpha colors.outline_variant 40;
        "editorWarning.foreground" = warning;
        "editorWhitespace.foreground" = alpha colors.outline_variant 80;

        "editorHoverWidget.background" = background colors.surface_container_high;
        "editorHoverWidget.border" = alpha colors.outline_variant 80;
        "editorHoverWidget.foreground" = t.render colors.on_surface;

        "editorSuggestWidget.background" = background colors.surface_container_high;
        "editorSuggestWidget.border" = alpha colors.outline_variant 80;
        "editorSuggestWidget.foreground" = t.render colors.on_surface;
        "editorSuggestWidget.highlightForeground" = t.render colors.primary;
        "editorSuggestWidget.selectedBackground" = alpha colors.primary_container 80;

        "peekView.border" = t.render colors.primary;
        "peekViewEditor.background" = background colors.surface_container_low;
        "peekViewResult.background" = background colors.surface_container;
        "peekViewResult.matchHighlightBackground" = alpha colors.tertiary_container 80;
        "peekViewResult.selectionBackground" = alpha colors.primary_container 80;
        "peekViewTitle.background" = alpha colors.primary_container 80;
        "peekViewTitleLabel.foreground" = t.render colors.on_primary_container;

        "minimap.selectionHighlight" = alpha colors.primary_container 80;
        "minimap.findMatchHighlight" = alpha colors.tertiary_container 90;

        "diffEditor.insertedTextBackground" = alpha colors.tertiary_container 80;
        "diffEditor.removedTextBackground" = alpha colors.error_container 80;
        "diffEditorGutter.insertedLineBackground" = alpha colors.tertiary_container 80;
        "diffEditorGutter.removedLineBackground" = alpha colors.error_container 80;

        "gitDecoration.addedResourceForeground" = t.render colors.tertiary;
        "gitDecoration.deletedResourceForeground" = t.render colors.error;
        "gitDecoration.modifiedResourceForeground" = t.render colors.secondary;
        "gitDecoration.renamedResourceForeground" = t.render colors.primary;
        "gitDecoration.untrackedResourceForeground" = t.render colors.tertiary;

        "notifications.background" = background colors.surface_container_high;
        "notifications.border" = alpha colors.outline_variant 40;
        "notifications.foreground" = t.render colors.on_surface;
        "notificationCenterHeader.background" = background colors.surface_container_low;
        "notificationCenterHeader.foreground" = t.render colors.on_surface;

        "pickerGroup.border" = alpha colors.outline_variant 60;
        "pickerGroup.foreground" = t.render colors.primary;
        "quickInput.background" = background colors.surface_container_high;
        "quickInput.foreground" = t.render colors.on_surface;
        "quickInputTitle.background" = background colors.surface_container_low;

        "problemsErrorIcon.foreground" = t.render colors.error;
        "problemsInfoIcon.foreground" = t.render colors.primary;
        "problemsWarningIcon.foreground" = warning;

        "terminal.background" = terminal.background;
        "terminal.foreground" = terminal.foreground;
        "terminal.selectionBackground" = terminal.selectionBackground;
        "terminalCursor.background" = terminal.cursorText;
        "terminalCursor.foreground" = terminal.cursor;
        "terminal.ansiBlack" = terminal.ansi.black;
        "terminal.ansiBlue" = terminal.ansi.blue;
        "terminal.ansiBrightBlack" = terminal.ansi.brightBlack;
        "terminal.ansiBrightBlue" = terminal.ansi.brightBlue;
        "terminal.ansiBrightCyan" = terminal.ansi.brightCyan;
        "terminal.ansiBrightGreen" = terminal.ansi.brightGreen;
        "terminal.ansiBrightMagenta" = terminal.ansi.brightMagenta;
        "terminal.ansiBrightRed" = terminal.ansi.brightRed;
        "terminal.ansiBrightWhite" = terminal.ansi.brightWhite;
        "terminal.ansiBrightYellow" = terminal.ansi.brightYellow;
        "terminal.ansiCyan" = terminal.ansi.cyan;
        "terminal.ansiGreen" = terminal.ansi.green;
        "terminal.ansiMagenta" = terminal.ansi.magenta;
        "terminal.ansiRed" = terminal.ansi.red;
        "terminal.ansiWhite" = terminal.ansi.white;
        "terminal.ansiYellow" = terminal.ansi.yellow;
      };
      tokenColors = [
        (mkTokenColor "Comments" [
          "comment"
          "punctuation.definition.comment"
        ] syntax.comment "italic")
        (mkTokenColor "Keywords" [
          "keyword"
          "keyword.control"
          "storage"
          "storage.type"
          "storage.modifier"
        ] syntax.keyword null)
        (mkTokenColor "Strings" [
          "string"
          "markup.inline.raw"
        ] syntax.string null)
        (mkTokenColor "String Escapes" [
          "constant.character.escape"
          "string.regexp"
          "string.regexp punctuation.definition.string.begin"
          "string.regexp punctuation.definition.string.end"
        ] syntax.stringRegex null)
        (mkTokenColor "Numbers and Constants" [
          "constant.numeric"
          "constant.language.boolean"
          "constant.language.null"
          "constant.character"
          "constant.other"
        ] syntax.number null)
        (mkTokenColor "Functions" [
          "entity.name.function"
          "support.function"
          "meta.function-call"
          "variable.function"
        ] syntax.function null)
        (mkTokenColor "Types" [
          "entity.name.type"
          "entity.name.class"
          "support.type"
          "support.class"
          "storage.type.annotation"
        ] syntax.type null)
        (mkTokenColor "Variables" [
          "variable"
          "meta.definition.variable name"
          "support.variable"
        ] syntax.variable null)
        (mkTokenColor "Properties" [
          "variable.other.property"
          "meta.property-name"
          "entity.other.attribute-name"
        ] syntax.title null)
        (mkTokenColor "Operators" [
          "keyword.operator"
          "punctuation.accessor"
        ] syntax.operator null)
        (mkTokenColor "Punctuation" [
          "punctuation"
          "meta.brace"
          "meta.delimiter"
        ] syntax.punctuation null)
        (mkTokenColor "Tags" [
          "entity.name.tag"
          "meta.tag.sgml"
        ] syntax.variable null)
        (mkTokenColor "Decorators" [
          "entity.name.function.decorator"
          "entity.name.type.module"
          "meta.annotation"
        ] syntax.number null)
        (mkTokenColor "Markdown Headings" [
          "markup.heading"
          "markup.heading entity.name"
        ] syntax.title null)
        (mkTokenColor "Markdown Emphasis" [
          "markup.italic"
          "markup.quote"
        ] syntax.emphasis "italic")
        (mkTokenColor "Links" [
          "markup.underline.link"
          "markup.link"
          "string.other.link"
        ] syntax.link null)
        (mkTokenColor "Invalid" [ "invalid" ] (t.render colors.error) null)
      ];
      semanticTokenColors = {
        class = mkSemanticColor syntax.type;
        comment = (mkSemanticColor syntax.comment) // {
          italic = true;
        };
        "comment.documentation" = (mkSemanticColor syntax.comment) // {
          italic = true;
        };
        decorator = mkSemanticColor syntax.number;
        enum = mkSemanticColor syntax.type;
        enumMember = mkSemanticColor syntax.number;
        event = mkSemanticColor syntax.variable;
        function = mkSemanticColor syntax.function;
        "function.defaultLibrary" = mkSemanticColor syntax.function;
        interface = mkSemanticColor syntax.type;
        keyword = mkSemanticColor syntax.keyword;
        label = mkSemanticColor syntax.variable;
        macro = mkSemanticColor syntax.number;
        method = mkSemanticColor syntax.function;
        "method.defaultLibrary" = mkSemanticColor syntax.function;
        namespace = mkSemanticColor syntax.type;
        number = mkSemanticColor syntax.number;
        operator = mkSemanticColor syntax.operator;
        parameter = mkSemanticColor syntax.variable;
        property = mkSemanticColor syntax.title;
        "property.readonly" = mkSemanticColor syntax.number;
        regexp = mkSemanticColor syntax.stringRegex;
        string = mkSemanticColor syntax.string;
        struct = mkSemanticColor syntax.type;
        type = mkSemanticColor syntax.type;
        "type.defaultLibrary" = mkSemanticColor syntax.type;
        typeParameter = mkSemanticColor syntax.type;
        variable = mkSemanticColor syntax.variable;
        "variable.defaultLibrary" = mkSemanticColor syntax.variable;
        "variable.readonly" = mkSemanticColor syntax.number;
      };
    };
in
{
  dark = pkgs.writeText "themegen-vscode-dark.json" ((builtins.toJSON (mkTheme "dark")) + "\n");
  light = pkgs.writeText "themegen-vscode-light.json" ((builtins.toJSON (mkTheme "light")) + "\n");
}
