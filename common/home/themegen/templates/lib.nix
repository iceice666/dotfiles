{ lib, ... }:

let
  inherit (lib)
    concatMap
    concatStringsSep
    foldl'
    ;

  concatLines = lines: concatStringsSep "\n" lines + "\n";

  placeholder = value: "{{${value}}}";

  mkCopiedFile =
    {
      source,
      output,
    }:
    {
      inherit output source;
      type = "copy";
    };

  mkHomeFile =
    {
      target,
      source,
      platforms ? [ ],
    }:
    {
      inherit platforms source target;
    };

  mkRenderedFile =
    {
      template,
      output,
    }:
    {
      inherit output template;
      type = "render";
    };

  call = name: args: "${name}(${concatStringsSep ", " (map toString args)})";

  appendStep = value: step: "${value} | ${step}";
  appendCall =
    name: args: value:
    appendStep value (call name args);

  applyPipeline = value: steps: lib.pipe value steps;
  renderPipeline = value: steps: placeholder (applyPipeline value steps);
  templateExpression = value: steps: applyPipeline value steps;

  chroma = amount: appendCall "chroma" [ amount ];
  lightness = amount: appendCall "lightness" [ amount ];
  mix =
    value: amount:
    appendCall "mix" [
      value
      amount
    ];
  readable =
    background: ratio:
    appendCall "readable" [
      background
      ratio
    ];
  rotate = amount: appendCall "rotate" [ amount ];
  toHct = appendCall "to_hct" [ ];
  toHex = appendCall "to_hex" [ ];
  toOklch = appendCall "to_oklch" [ ];
  tone = amount: appendCall "tone" [ amount ];
  withAlpha = amount: appendCall "with_alpha" [ amount ];

  modes = [
    "dark"
    "light"
  ];

  colorTokens = [
    "background"
    "error"
    "error_container"
    "on_error_container"
    "on_primary"
    "on_primary_container"
    "on_secondary_container"
    "on_surface"
    "on_surface_variant"
    "on_tertiary_container"
    "outline"
    "outline_variant"
    "primary"
    "primary_container"
    "primary_fixed_dim"
    "secondary"
    "secondary_container"
    "surface"
    "surface_container"
    "surface_container_high"
    "surface_container_highest"
    "surface_container_low"
    "surface_dim"
    "surface_variant"
    "tertiary"
    "tertiary_container"
  ];

  base16Tokens = [
    "base08"
    "base0A"
    "base0B"
    "base0C"
    "base0D"
    "base0E"
  ];

  syntaxTokens = [
    "boolean"
    "comment"
    "emphasis"
    "function"
    "keyword"
    "link"
    "literal"
    "number"
    "operator"
    "predictive"
    "punctuation"
    "string"
    "stringRegex"
    "stringSpecial"
    "title"
    "type"
    "variable"
  ];

  mkRefs =
    prefix: names:
    builtins.listToAttrs (
      map (name: {
        inherit name;
        value = "${prefix}.${name}";
      }) names
    );

  mkModeRefs =
    prefix: names:
    builtins.listToAttrs (
      map (mode: {
        name = mode;
        value = mkRefs "${prefix}.${mode}" names;
      }) modes
    );

  color = mkModeRefs "color" colorTokens;
  base16 = mkModeRefs "base16" base16Tokens;
  syntax = mkModeRefs "syntax" syntaxTokens;

  seed = "seed.color";
  lightBackgroundExpression =
    value:
    templateExpression value [
      toHct
      (mix (applyPipeline seed [ toHct ]) 0.08)
      toHex
    ];

  renderMix =
    left: right: amount:
    renderPipeline left [
      (mix right amount)
      toHex
    ];
  renderAlpha =
    value: amount:
    renderPipeline value [
      (withAlpha amount)
      toHex
    ];

  terminal =
    mode:
    let
      colors = color.${mode};
      base16Colors = base16.${mode};

      renderColor = value: placeholder value;
      renderBase = value: placeholder value;
      mixBase16 = value: renderMix value colors.surface_container_low 0.35;

      ansi = rec {
        black = renderColor (if mode == "dark" then colors.surface_dim else colors.on_surface);
        red = renderBase base16Colors.base08;
        green = renderBase base16Colors.base0B;
        yellow = renderBase base16Colors.base0A;
        blue = renderBase base16Colors.base0D;
        magenta = renderBase base16Colors.base0E;
        cyan = renderBase base16Colors.base0C;
        white = renderColor (if mode == "dark" then colors.on_surface else colors.surface_dim);
        brightBlack = renderColor (
          if mode == "dark" then colors.surface_container_high else colors.on_surface
        );
        brightRed = red;
        brightGreen = green;
        brightYellow = yellow;
        brightBlue = blue;
        brightMagenta = magenta;
        brightCyan = cyan;
        brightWhite = renderColor (
          if mode == "dark" then colors.on_surface else colors.surface_container_high
        );
      };
    in
    rec {
      background =
        if mode == "light" then
          placeholder (lightBackgroundExpression colors.surface_container_low)
        else
          renderColor colors.surface_container_low;
      brightForeground = renderColor colors.on_surface;
      cursor = renderColor colors.primary;
      cursorText = renderColor colors.on_primary;
      dimForeground = renderColor colors.on_surface_variant;
      foreground = renderColor colors.on_surface;
      selectionBackground = renderColor colors.secondary_container;
      selectionForeground = renderColor colors.on_secondary_container;

      inherit ansi;

      ansi16 = [
        ansi.black
        ansi.red
        ansi.green
        ansi.yellow
        ansi.blue
        ansi.magenta
        ansi.cyan
        ansi.white
        ansi.brightBlack
        ansi.brightRed
        ansi.brightGreen
        ansi.brightYellow
        ansi.brightBlue
        ansi.brightMagenta
        ansi.brightCyan
        ansi.brightWhite
      ];

      dim = {
        black = renderColor (if mode == "dark" then colors.surface else colors.on_surface_variant);
        red = mixBase16 base16Colors.base08;
        green = mixBase16 base16Colors.base0B;
        yellow = mixBase16 base16Colors.base0A;
        blue = mixBase16 base16Colors.base0D;
        magenta = mixBase16 base16Colors.base0E;
        cyan = mixBase16 base16Colors.base0C;
        white = renderColor (if mode == "dark" then colors.on_surface_variant else colors.surface);
      };
    };

  flattenPairs =
    values:
    builtins.listToAttrs (
      concatMap (name: [
        {
          name = "${name}_dark";
          value = values.${name}.dark;
        }
        {
          name = "${name}_light";
          value = values.${name}.light;
        }
      ]) (builtins.attrNames values)
    );

  mergeAll = foldl' (acc: attrs: acc // attrs) { };
in
{
  inherit
    applyPipeline
    base16
    chroma
    color
    concatLines
    flattenPairs
    lightness
    lightBackgroundExpression
    mergeAll
    mix
    mkCopiedFile
    mkHomeFile
    mkRenderedFile
    placeholder
    readable
    renderAlpha
    renderMix
    renderPipeline
    rotate
    seed
    syntax
    templateExpression
    terminal
    toHct
    toHex
    toOklch
    tone
    withAlpha
    ;
}
