{ lib, ... }:

let
  inherit (lib)
    concatMap
    concatStringsSep
    foldl'
    optionals
    ;

  concatLines = lines: concatStringsSep "\n" lines + "\n";

  render = expression: "{{${expression}}}";

  call = name: args: "${name}(${concatStringsSep ", " (map toString args)})";

  pipeExpr = expression: steps: concatStringsSep " | " ([ expression ] ++ steps);

  renderPipe = expression: steps: render (pipeExpr expression steps);

  colorExpr = mode: token: "color.${mode}.${token}";
  base16Expr = mode: token: "base16.${mode}.${token}";

  seedExpr = "seed.color";

  withAlphaStep = amount: call "with_alpha" [ amount ];
  mixStep =
    expression: amount:
    call "mix" [
      expression
      amount
    ];
  readableStep =
    expression: ratio:
    call "readable" [
      expression
      ratio
    ];
  rotateStep = amount: call "rotate" [ amount ];
  chromaStep = amount: call "chroma" [ amount ];
  lightnessStep = amount: call "lightness" [ amount ];
  toneStep = amount: call "tone" [ amount ];
  toHexStep = call "to_hex" [ ];
  toHctStep = call "to_hct" [ ];
  toOklchStep = call "to_oklch" [ ];

  mix =
    left: right: amount:
    renderPipe left [
      (mixStep right amount)
      toHexStep
    ];
  alpha =
    expression: amount:
    renderPipe expression [
      (withAlphaStep amount)
      toHexStep
    ];

  syntax =
    mode:
    let
      background = colorExpr mode "surface_container_low";

      mk =
        {
          rotate ? null,
          chroma,
          lightness,
          ratio,
        }:
        renderPipe seedExpr (
          [ toOklchStep ]
          ++ optionals (rotate != null) [ (rotateStep rotate) ]
          ++ [
            (chromaStep chroma)
            (lightnessStep lightness)
            (readableStep background ratio)
            toHexStep
          ]
        );
    in
    rec {
      boolean = mk {
        chroma = 0.18;
        lightness = if mode == "dark" then 0.78 else 0.46;
        ratio = 4.5;
      };
      comment = mk {
        rotate = 170;
        chroma = 0.08;
        lightness = if mode == "dark" then 0.66 else 0.56;
        ratio = 3.2;
      };
      emphasis = mk {
        rotate = 170;
        chroma = 0.1;
        lightness = if mode == "dark" then 0.74 else 0.5;
        ratio = 4.5;
      };
      function = mk {
        rotate = -80;
        chroma = 0.12;
        lightness = if mode == "dark" then 0.72 else 0.5;
        ratio = 3.2;
      };
      keyword = mk {
        rotate = -52;
        chroma = 0.16;
        lightness = if mode == "dark" then 0.78 else 0.44;
        ratio = 4.5;
      };
      link = mk {
        rotate = 145;
        chroma = 0.24;
        lightness = if mode == "dark" then 0.84 else 0.38;
        ratio = 4.5;
      };
      number = boolean;
      operator = render (colorExpr mode "on_surface");
      predictive = alpha (colorExpr mode "on_surface_variant") 80;
      punctuation = render (colorExpr mode "on_surface_variant");
      string = mk {
        rotate = 145;
        chroma = 0.2;
        lightness = if mode == "dark" then 0.79 else 0.44;
        ratio = 4.5;
      };
      stringRegex = mk {
        rotate = 145;
        chroma = 0.26;
        lightness = if mode == "dark" then 0.83 else 0.4;
        ratio = 4.5;
      };
      title = emphasis;
      type = mk {
        rotate = -32;
        chroma = 0.16;
        lightness = if mode == "dark" then 0.8 else 0.42;
        ratio = 4.5;
      };
      variable = mk {
        rotate = 18;
        chroma = 0.14;
        lightness = if mode == "dark" then 0.8 else 0.42;
        ratio = 4.5;
      };
    };

  terminal =
    mode:
    let
      color = token: render (colorExpr mode token);
      base16 = token: render (base16Expr mode token);
      mixBase16 = token: mix (base16Expr mode token) (colorExpr mode "surface_container_low") 0.35;

      ansi = rec {
        black = color (if mode == "dark" then "surface_dim" else "on_surface");
        red = base16 "base08";
        green = base16 "base0B";
        yellow = base16 "base0A";
        blue = base16 "base0D";
        magenta = base16 "base0E";
        cyan = base16 "base0C";
        white = color (if mode == "dark" then "on_surface" else "surface_dim");
        brightBlack = color (if mode == "dark" then "surface_container_high" else "on_surface");
        brightRed = red;
        brightGreen = green;
        brightYellow = yellow;
        brightBlue = blue;
        brightMagenta = magenta;
        brightCyan = cyan;
        brightWhite = color (if mode == "dark" then "on_surface" else "surface_container_high");
      };
    in
    rec {
      background = color "surface_container_low";
      brightForeground = color "on_surface";
      cursor = color "primary";
      cursorText = color "on_primary";
      dimForeground = color "on_surface_variant";
      foreground = color "on_surface";
      selectionBackground = color "secondary_container";
      selectionForeground = color "on_secondary_container";

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
        black = color (if mode == "dark" then "surface" else "on_surface_variant");
        red = mixBase16 "base08";
        green = mixBase16 "base0B";
        yellow = mixBase16 "base0A";
        blue = mixBase16 "base0D";
        magenta = mixBase16 "base0E";
        cyan = mixBase16 "base0C";
        white = color (if mode == "dark" then "on_surface_variant" else "surface");
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
    alpha
    base16Expr
    call
    colorExpr
    concatLines
    flattenPairs
    mergeAll
    mix
    pipeExpr
    render
    renderPipe
    seedExpr
    syntax
    terminal
    toHexStep
    toHctStep
    toneStep
    withAlphaStep
    ;
}
