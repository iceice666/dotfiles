{ lib, pkgs }:

let
  theme = import ./lib.nix { inherit lib; };

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
      colors = theme.color.${mode};
      base16Colors = theme.base16.${mode};
      syntax = lib.mapAttrs (_: value: theme.placeholder value) theme.syntax.${mode};
      terminal = theme.terminal mode;

      background =
        value:
        if mode == "light" then
          theme.placeholder (theme.lightBackgroundExpression value)
        else
          theme.placeholder value;
      alpha = value: amount: theme.renderAlpha value amount;

      themeName = "Themegen ${if mode == "dark" then "Dark" else "Light"}";
      warning = theme.placeholder base16Colors.base0A;
    in
    {
      "$schema" = "vscode://schemas/color-theme";
      name = themeName;
      type = mode;
      semanticHighlighting = true;
      colors = {
        disabledForeground = alpha colors.on_surface_variant 80;
        descriptionForeground = theme.placeholder colors.on_surface_variant;
        errorForeground = theme.placeholder colors.error;
        "focusBorder" = theme.placeholder colors.primary;
        "foreground" = theme.placeholder colors.on_surface;
        "icon.foreground" = theme.placeholder colors.on_surface;
        "selection.background" = alpha colors.primary_container 80;
        "sash.hoverBorder" = theme.placeholder colors.primary;
        "textBlockQuote.background" = alpha colors.surface_variant 60;
        "textBlockQuote.border" = alpha colors.outline_variant 80;
        "textCodeBlock.background" = background colors.surface_container_high;
        "textLink.foreground" = theme.placeholder colors.primary;
        "textLink.activeForeground" = theme.placeholder colors.primary;
        "textPreformat.foreground" = syntax.string;
        "textSeparator.foreground" = alpha colors.outline_variant 60;
        "widget.shadow" = alpha colors.outline_variant 40;

        "button.background" = theme.placeholder colors.primary;
        "button.foreground" = theme.placeholder colors.on_primary;
        "button.hoverBackground" = alpha colors.primary 90;
        "button.secondaryBackground" = background colors.secondary_container;
        "button.secondaryForeground" = theme.placeholder colors.on_secondary_container;
        "button.secondaryHoverBackground" = alpha colors.secondary_container 90;

        "badge.background" = theme.placeholder colors.primary;
        "badge.foreground" = theme.placeholder colors.on_primary;
        "progressBar.background" = theme.placeholder colors.primary;

        "dropdown.background" = background colors.surface_container_high;
        "dropdown.border" = alpha colors.outline_variant 80;
        "dropdown.foreground" = theme.placeholder colors.on_surface;
        "input.background" = background colors.surface_container_high;
        "input.border" = alpha colors.outline_variant 80;
        "input.foreground" = theme.placeholder colors.on_surface;
        "input.placeholderForeground" = alpha colors.on_surface_variant 99;
        "inputOption.activeBackground" = alpha colors.primary_container 80;
        "inputOption.activeBorder" = theme.placeholder colors.primary;
        "inputValidation.errorBackground" = alpha colors.error_container 80;
        "inputValidation.errorBorder" = theme.placeholder colors.error;
        "inputValidation.infoBackground" = alpha colors.primary_container 80;
        "inputValidation.infoBorder" = theme.placeholder colors.primary;
        "inputValidation.warningBackground" = alpha base16Colors.base0A 80;
        "inputValidation.warningBorder" = warning;

        "scrollbar.shadow" = alpha colors.outline_variant 30;
        "scrollbarSlider.background" = alpha colors.on_surface_variant 80;
        "scrollbarSlider.hoverBackground" = alpha colors.on_surface_variant "c0";
        "scrollbarSlider.activeBackground" = alpha colors.on_surface "c0";

        "list.activeSelectionBackground" = alpha colors.primary_container 80;
        "list.activeSelectionForeground" = theme.placeholder colors.on_surface;
        "list.focusBackground" = alpha colors.primary_container 80;
        "list.focusForeground" = theme.placeholder colors.on_surface;
        "list.highlightForeground" = theme.placeholder colors.primary;
        "list.hoverBackground" = alpha colors.surface_container_high 80;
        "list.hoverForeground" = theme.placeholder colors.on_surface;
        "list.inactiveSelectionBackground" = alpha colors.surface_container_high 90;
        "list.inactiveSelectionForeground" = theme.placeholder colors.on_surface;
        "list.warningForeground" = warning;
        "list.errorForeground" = theme.placeholder colors.error;
        "tree.indentGuidesStroke" = alpha colors.outline_variant 60;

        "activityBar.background" = background colors.surface_container_low;
        "activityBar.foreground" = theme.placeholder colors.on_surface;
        "activityBar.inactiveForeground" = theme.placeholder colors.on_surface_variant;
        "activityBar.activeBorder" = theme.placeholder colors.primary;
        "activityBarBadge.background" = theme.placeholder colors.primary;
        "activityBarBadge.foreground" = theme.placeholder colors.on_primary;

        "sideBar.background" = background colors.surface_container;
        "sideBar.border" = alpha colors.outline_variant 40;
        "sideBar.foreground" = theme.placeholder colors.on_surface;
        "sideBarSectionHeader.background" = background colors.surface_container_low;
        "sideBarSectionHeader.foreground" = theme.placeholder colors.on_surface;
        "sideBarTitle.foreground" = theme.placeholder colors.on_surface;

        "titleBar.activeBackground" = background colors.surface;
        "titleBar.activeForeground" = theme.placeholder colors.on_surface;
        "titleBar.border" = alpha colors.outline_variant 40;
        "titleBar.inactiveBackground" = background colors.surface_dim;
        "titleBar.inactiveForeground" = theme.placeholder colors.on_surface_variant;

        "statusBar.background" = background colors.surface;
        "statusBar.border" = alpha colors.outline_variant 40;
        "statusBar.foreground" = theme.placeholder colors.on_surface;
        "statusBar.debuggingBackground" = alpha colors.tertiary_container 90;
        "statusBar.debuggingForeground" = theme.placeholder colors.on_tertiary_container;
        "statusBar.noFolderBackground" = background colors.surface;
        "statusBar.noFolderForeground" = theme.placeholder colors.on_surface;
        "statusBarItem.hoverBackground" = alpha colors.surface_container_high 80;
        "statusBarItem.prominentBackground" = alpha colors.surface_container_highest 80;

        "panel.background" = background colors.surface_container;
        "panel.border" = alpha colors.outline_variant 40;
        "panelInput.border" = alpha colors.outline_variant 80;
        "panelTitle.activeBorder" = theme.placeholder colors.primary;
        "panelTitle.activeForeground" = theme.placeholder colors.on_surface;
        "panelTitle.inactiveForeground" = theme.placeholder colors.on_surface_variant;

        "editorGroup.border" = alpha colors.outline_variant 40;
        "editorGroupHeader.tabsBackground" = background colors.surface_container;
        "tab.activeBackground" = background colors.surface_container_low;
        "tab.activeBorderTop" = theme.placeholder colors.primary;
        "tab.activeForeground" = theme.placeholder colors.on_surface;
        "tab.border" = alpha colors.outline_variant 40;
        "tab.hoverBackground" = alpha colors.surface_container_high 80;
        "tab.inactiveBackground" = background colors.surface_container;
        "tab.inactiveForeground" = theme.placeholder colors.on_surface_variant;
        "tab.unfocusedActiveBorderTop" = alpha colors.primary 80;

        "editor.background" = background colors.surface_container_low;
        "editor.foreground" = theme.placeholder colors.on_surface;
        "editor.findMatchBackground" = alpha colors.tertiary_container 90;
        "editor.findMatchBorder" = theme.placeholder colors.tertiary;
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
        "editorCodeLens.foreground" = theme.placeholder colors.on_surface_variant;
        "editorCursor.background" = theme.placeholder colors.on_primary;
        "editorCursor.foreground" = theme.placeholder colors.primary;
        "editorError.foreground" = theme.placeholder colors.error;
        "editorHint.foreground" = theme.placeholder colors.primary;
        "editorIndentGuide.activeBackground1" = alpha colors.outline 80;
        "editorIndentGuide.background1" = alpha colors.outline_variant 60;
        "editorInfo.foreground" = theme.placeholder colors.primary;
        "editorLineNumber.activeForeground" = theme.placeholder colors.primary;
        "editorLineNumber.foreground" = theme.placeholder colors.on_surface_variant;
        "editorLink.activeForeground" = theme.placeholder colors.primary;
        "editorRuler.foreground" = alpha colors.outline_variant 50;
        "editorStickyScroll.background" = background colors.surface_container;
        "editorStickyScroll.border" = alpha colors.outline_variant 40;
        "editorWarning.foreground" = warning;
        "editorWhitespace.foreground" = alpha colors.outline_variant 80;

        "editorHoverWidget.background" = background colors.surface_container_high;
        "editorHoverWidget.border" = alpha colors.outline_variant 80;
        "editorHoverWidget.foreground" = theme.placeholder colors.on_surface;

        "editorSuggestWidget.background" = background colors.surface_container_high;
        "editorSuggestWidget.border" = alpha colors.outline_variant 80;
        "editorSuggestWidget.foreground" = theme.placeholder colors.on_surface;
        "editorSuggestWidget.highlightForeground" = theme.placeholder colors.primary;
        "editorSuggestWidget.selectedBackground" = alpha colors.primary_container 80;

        "peekView.border" = theme.placeholder colors.primary;
        "peekViewEditor.background" = background colors.surface_container_low;
        "peekViewResult.background" = background colors.surface_container;
        "peekViewResult.matchHighlightBackground" = alpha colors.tertiary_container 80;
        "peekViewResult.selectionBackground" = alpha colors.primary_container 80;
        "peekViewTitle.background" = alpha colors.primary_container 80;
        "peekViewTitleLabel.foreground" = theme.placeholder colors.on_primary_container;

        "minimap.selectionHighlight" = alpha colors.primary_container 80;
        "minimap.findMatchHighlight" = alpha colors.tertiary_container 90;

        "diffEditor.insertedTextBackground" = alpha colors.tertiary_container 80;
        "diffEditor.removedTextBackground" = alpha colors.error_container 80;
        "diffEditorGutter.insertedLineBackground" = alpha colors.tertiary_container 80;
        "diffEditorGutter.removedLineBackground" = alpha colors.error_container 80;

        "gitDecoration.addedResourceForeground" = theme.placeholder colors.tertiary;
        "gitDecoration.deletedResourceForeground" = theme.placeholder colors.error;
        "gitDecoration.modifiedResourceForeground" = theme.placeholder colors.secondary;
        "gitDecoration.renamedResourceForeground" = theme.placeholder colors.primary;
        "gitDecoration.untrackedResourceForeground" = theme.placeholder colors.tertiary;

        "notifications.background" = background colors.surface_container_high;
        "notifications.border" = alpha colors.outline_variant 40;
        "notifications.foreground" = theme.placeholder colors.on_surface;
        "notificationCenterHeader.background" = background colors.surface_container_low;
        "notificationCenterHeader.foreground" = theme.placeholder colors.on_surface;

        "pickerGroup.border" = alpha colors.outline_variant 60;
        "pickerGroup.foreground" = theme.placeholder colors.primary;
        "quickInput.background" = background colors.surface_container_high;
        "quickInput.foreground" = theme.placeholder colors.on_surface;
        "quickInputTitle.background" = background colors.surface_container_low;

        "problemsErrorIcon.foreground" = theme.placeholder colors.error;
        "problemsInfoIcon.foreground" = theme.placeholder colors.primary;
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
        (mkTokenColor "Invalid" [ "invalid" ] (theme.placeholder colors.error) null)
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
        "*.unsafe" = mkSemanticColor (theme.placeholder colors.error);
        "*.mutable" = mkSemanticColor syntax.variable // {
          underline = true;
        };
        "method.consuming" = mkSemanticColor syntax.function // {
          italic = true;
        };
        "variable.consuming" = mkSemanticColor syntax.variable // {
          strikethrough = true;
        };
        "parameter.consuming" = mkSemanticColor syntax.variable // {
          strikethrough = true;
        };
        lifetime = mkSemanticColor syntax.number;
        builtinAttribute = mkSemanticColor syntax.number;
        attributeBracket = mkSemanticColor syntax.number;
        deriveHelper = mkSemanticColor syntax.number;
      };
    };

  darkTheme = pkgs.writeText "themegen-vscode-dark.json" ((builtins.toJSON (mkTheme "dark")) + "\n");
  lightTheme = pkgs.writeText "themegen-vscode-light.json" (
    (builtins.toJSON (mkTheme "light")) + "\n"
  );
  vscodeManifest = builtins.toFile "themegen-vscode-package.json" (
    builtins.toJSON {
      name = "themegen";
      publisher = "themegen";
      displayName = "Themegen";
      version = "0.0.1";
      engines.vscode = "^1.74.0";
      categories = [ "Themes" ];
      contributes.themes = [
        {
          label = "Themegen Dark";
          uiTheme = "vs-dark";
          path = "./themes/themegen-dark-color-theme.json";
        }
        {
          label = "Themegen Light";
          uiTheme = "vs";
          path = "./themes/themegen-light-color-theme.json";
        }
      ];
    }
    + "\n"
  );
in
{
  generated = [
    (theme.mkRenderedFile {
      template = darkTheme;
      output = "vscode/extensions/themegen.themegen/themes/themegen-dark-color-theme.json";
    })
    (theme.mkRenderedFile {
      template = lightTheme;
      output = "vscode/extensions/themegen.themegen/themes/themegen-light-color-theme.json";
    })
    (theme.mkCopiedFile {
      source = vscodeManifest;
      output = "vscode/extensions/themegen.themegen/package.json";
    })
  ];

  homeFiles = [
    (theme.mkHomeFile {
      target = ".vscode-oss/extensions/themegen.themegen";
      source = "vscode/extensions/themegen.themegen";
    })
  ];
}
