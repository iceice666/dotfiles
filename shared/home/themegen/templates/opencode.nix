{ lib, pkgs }:

let
  t = import ./lib.nix { inherit lib; };
  color = t.color;
  base16 = t.base16;

  syntaxDark = t.syntax "dark";
  syntaxLight = t.syntax "light";

  pair = dark: light: { inherit dark light; };

  defs = t.flattenPairs {
    primary = pair (t.render color.dark.primary) (t.render color.light.primary);
    secondary = pair (t.render color.dark.secondary) (t.render color.light.secondary);
    tertiary = pair (t.render color.dark.tertiary) (t.render color.light.tertiary);
    error = pair (t.render color.dark.error) (t.render color.light.error);
    warning = pair (t.render base16.dark.base0A) (t.render base16.light.base0A);
    text = pair (t.render color.dark.on_surface) (t.render color.light.on_surface);
    text_muted = pair (t.blend color.dark.on_surface_variant color.dark.on_surface 0.2) (
      t.blend color.light.on_surface_variant color.light.on_surface 0.2
    );
    background = pair "none" "none";
    surface_low = pair (t.blend color.dark.surface_container color.dark.surface_container_low 0.75) (
      t.blend color.light.surface_container color.light.surface_container_low 0.75
    );
    surface_panel = pair (t.blend color.dark.surface_container color.dark.surface_container_low 0.64) (
      t.blend color.light.surface_container color.light.surface_container_low 0.64
    );
    surface_element = pair (t.blend color.dark.surface_container_high color.dark.surface_container_low
      0.42
    ) (t.blend color.light.surface_container_high color.light.surface_container_low 0.42);
    border = pair (t.render color.dark.outline) (t.render color.light.outline);
    border_active = pair (t.render color.dark.primary) (t.render color.light.primary);
    border_subtle = pair (t.blend color.dark.outline_variant color.dark.surface_container_low 0.45) (
      t.blend color.light.outline_variant color.light.surface_container_low 0.45
    );
    created = pair (t.render color.dark.tertiary) (t.render color.light.tertiary);
    created_bg = pair (t.blend color.dark.tertiary_container color.dark.surface_container_low 0.58) (
      t.r
        (t.raw color.light.tertiary_container [
          (t.mix color.light.surface_container_low 0.59)
        ])
        [
          t.toOklch
          (t.chroma 0.055)
          (t.lightness 0.955)
          t.toHex
        ]
    );
    deleted = pair (t.render color.dark.error) (t.render color.light.error);
    deleted_bg = pair (t.blend color.dark.error_container color.dark.surface_container_low 0.5) (
      t.r
        (t.raw color.light.error_container [
          (t.mix color.light.surface_container_low 0.5)
        ])
        [
          t.toOklch
          (t.chroma 0.065)
          (t.lightness 0.952)
          t.toHex
        ]
    );
    modified = pair (t.render color.dark.secondary) (t.render color.light.secondary);
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

  theme = {
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
in
pkgs.writeText "themegen-opencode-colors.json" (
  builtins.toJSON {
    "$schema" = "https://opencode.ai/theme.json";
    inherit defs theme;
  }
  + "\n"
)
