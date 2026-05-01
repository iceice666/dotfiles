{ lib, pkgs }:

let
  theme = import ./lib.nix { inherit lib; };
  color = theme.color;
  base16 = theme.base16;

  syntaxDark = lib.mapAttrs (_: value: theme.placeholder value) theme.syntax.dark;
  syntaxLight = lib.mapAttrs (_: value: theme.placeholder value) theme.syntax.light;

  pair = dark: light: { inherit dark light; };

  defs = theme.flattenPairs {
    primary = pair (theme.placeholder color.dark.primary) (theme.placeholder color.light.primary);
    secondary = pair (theme.placeholder color.dark.secondary) (theme.placeholder color.light.secondary);
    tertiary = pair (theme.placeholder color.dark.tertiary) (theme.placeholder color.light.tertiary);
    error = pair (theme.placeholder color.dark.error) (theme.placeholder color.light.error);
    warning = pair (theme.placeholder base16.dark.base0A) (theme.placeholder base16.light.base0A);
    text = pair (theme.placeholder color.dark.on_surface) (theme.placeholder color.light.on_surface);
    text_muted = pair (theme.renderMix color.dark.on_surface_variant color.dark.on_surface 0.2) (
      theme.renderMix color.light.on_surface_variant color.light.on_surface 0.2
    );
    background = pair "none" "none";
    surface_low = pair (theme.renderMix color.dark.surface_container color.dark.surface_container_low
      0.75
    ) (theme.renderMix color.light.surface_container color.light.surface_container_low 0.75);
    surface_panel = pair (theme.renderMix color.dark.surface_container color.dark.surface_container_low
      0.64
    ) (theme.renderMix color.light.surface_container color.light.surface_container_low 0.64);
    surface_element = pair (theme.renderMix color.dark.surface_container_high
      color.dark.surface_container_low
      0.42
    ) (theme.renderMix color.light.surface_container_high color.light.surface_container_low 0.42);
    border = pair (theme.placeholder color.dark.outline) (theme.placeholder color.light.outline);
    border_active = pair (theme.placeholder color.dark.primary) (theme.placeholder color.light.primary);
    border_subtle = pair (theme.renderMix color.dark.outline_variant color.dark.surface_container_low
      0.45
    ) (theme.renderMix color.light.outline_variant color.light.surface_container_low 0.45);
    created = pair (theme.placeholder color.dark.tertiary) (theme.placeholder color.light.tertiary);
    created_bg =
      pair (theme.renderMix color.dark.tertiary_container color.dark.surface_container_low 0.58)
        (
          theme.renderPipeline
            (theme.templateExpression color.light.tertiary_container [
              (theme.mix color.light.surface_container_low 0.59)
            ])
            [
              theme.toOklch
              (theme.chroma 0.055)
              (theme.lightness 0.955)
              theme.toHex
            ]
        );
    deleted = pair (theme.placeholder color.dark.error) (theme.placeholder color.light.error);
    deleted_bg =
      pair (theme.renderMix color.dark.error_container color.dark.surface_container_low 0.5)
        (
          theme.renderPipeline
            (theme.templateExpression color.light.error_container [
              (theme.mix color.light.surface_container_low 0.5)
            ])
            [
              theme.toOklch
              (theme.chroma 0.065)
              (theme.lightness 0.952)
              theme.toHex
            ]
        );
    modified = pair (theme.placeholder color.dark.secondary) (theme.placeholder color.light.secondary);
    syntax_comment = pair syntaxDark.comment syntaxLight.comment;
    syntax_emphasis = pair syntaxDark.emphasis syntaxLight.emphasis;
    syntax_function = pair syntaxDark.function syntaxLight.function;
    syntax_keyword = pair syntaxDark.keyword syntaxLight.keyword;
    syntax_number = pair syntaxDark.number syntaxLight.number;
    syntax_operator = pair syntaxDark.operator syntaxLight.operator;
    syntax_punctuation = pair syntaxDark.punctuation syntaxLight.punctuation;
    syntax_string = pair syntaxDark.string syntaxLight.string;
    syntax_type = pair syntaxDark.type syntaxLight.type;
    syntax_variable = pair syntaxDark.variable syntaxLight.variable;
    syntax_title = pair syntaxDark.title syntaxLight.title;
    syntax_link = pair syntaxDark.link syntaxLight.link;
  };

  ref = name: {
    dark = "${name}_dark";
    light = "${name}_light";
  };

  themeSpec = {
    primary = ref "primary";
    secondary = ref "secondary";
    accent = ref "tertiary";
    error = ref "error";
    warning = ref "warning";
    success = ref "created";
    info = ref "primary";
    text = ref "text";
    textMuted = ref "text_muted";
    background = ref "background";
    backgroundPanel = ref "surface_panel";
    backgroundElement = ref "surface_element";
    border = ref "border";
    borderActive = ref "border_active";
    borderSubtle = ref "border_subtle";
    diffAdded = ref "created";
    diffRemoved = ref "deleted";
    diffContext = ref "text_muted";
    diffHunkHeader = ref "modified";
    diffHighlightAdded = ref "created";
    diffHighlightRemoved = ref "deleted";
    diffAddedBg = ref "created_bg";
    diffRemovedBg = ref "deleted_bg";
    diffContextBg = ref "surface_low";
    diffLineNumber = ref "text_muted";
    diffAddedLineNumberBg = ref "created_bg";
    diffRemovedLineNumberBg = ref "deleted_bg";
    markdownText = ref "text";
    markdownHeading = ref "syntax_title";
    markdownLink = ref "syntax_link";
    markdownLinkText = ref "primary";
    markdownCode = ref "syntax_string";
    markdownBlockQuote = ref "text_muted";
    markdownEmph = ref "syntax_emphasis";
    markdownStrong = ref "syntax_title";
    markdownHorizontalRule = ref "border_subtle";
    markdownListItem = ref "primary";
    markdownListEnumeration = ref "modified";
    markdownImage = ref "primary";
    markdownImageText = ref "modified";
    markdownCodeBlock = ref "text";
    syntaxComment = ref "syntax_comment";
    syntaxKeyword = ref "syntax_keyword";
    syntaxFunction = ref "syntax_function";
    syntaxVariable = ref "syntax_variable";
    syntaxString = ref "syntax_string";
    syntaxNumber = ref "syntax_number";
    syntaxType = ref "syntax_type";
    syntaxOperator = ref "syntax_operator";
    syntaxPunctuation = ref "syntax_punctuation";
  };

  themeJson = pkgs.writeText "themegen-opencode-colors.json" (
    builtins.toJSON {
      "$schema" = "https://opencode.ai/theme.json";
      defs = defs;
      theme = themeSpec;
    }
    + "\n"
  );
in
{
  generated = [
    (theme.mkRenderedFile {
      template = themeJson;
      output = "opencode/themes/themegen.json";
    })
  ];

  homeFiles = [
    (theme.mkHomeFile {
      target = ".config/opencode/themes/themegen.json";
      source = "opencode/themes/themegen.json";
    })
  ];
}
