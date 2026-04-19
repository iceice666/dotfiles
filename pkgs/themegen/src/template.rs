use std::collections::BTreeMap;

use anyhow::{bail, Context, Result};

use crate::color::{
    argb_to_rgba, ensure_readable, format_number, hct_to_rgba, hsv_to_rgba, interpolate, mix,
    normalize_hue, oklch_to_rgba, parse_hex_value, rgba_to_argb, rgba_to_hct, rgba_to_hsv,
    rgba_to_oklch, HctColor, HsvColor, OklchColor, RgbaColor,
};
use crate::model::{Base16Palette, PaletteOutput, SyntaxPalette};

pub(crate) fn template_values(output: &PaletteOutput) -> BTreeMap<String, String> {
    let mut values = BTreeMap::new();

    values.insert("input.kind".to_string(), output.input.kind.clone());
    values.insert("input.value".to_string(), output.input.value.clone());
    values.insert("scheme".to_string(), output.scheme.clone());
    values.insert("seed.color".to_string(), output.seed.color.clone());

    extend_prefixed(&mut values, "color.light", &output.color.light);
    extend_prefixed(&mut values, "color.dark", &output.color.dark);
    extend_base16(&mut values, "base16.light", &output.base16.light);
    extend_base16(&mut values, "base16.dark", &output.base16.dark);
    extend_syntax(&mut values, "syntax.light", &output.syntax.light);
    extend_syntax(&mut values, "syntax.dark", &output.syntax.dark);

    values
}

fn extend_prefixed(
    values: &mut BTreeMap<String, String>,
    prefix: &str,
    palette: &BTreeMap<String, String>,
) {
    for (name, color) in palette {
        values.insert(format!("{prefix}.{name}"), color.clone());
    }
}

fn extend_base16(values: &mut BTreeMap<String, String>, prefix: &str, palette: &Base16Palette) {
    values.insert(format!("{prefix}.base00"), palette.base00.clone());
    values.insert(format!("{prefix}.base01"), palette.base01.clone());
    values.insert(format!("{prefix}.base02"), palette.base02.clone());
    values.insert(format!("{prefix}.base03"), palette.base03.clone());
    values.insert(format!("{prefix}.base04"), palette.base04.clone());
    values.insert(format!("{prefix}.base05"), palette.base05.clone());
    values.insert(format!("{prefix}.base06"), palette.base06.clone());
    values.insert(format!("{prefix}.base07"), palette.base07.clone());
    values.insert(format!("{prefix}.base08"), palette.base08.clone());
    values.insert(format!("{prefix}.base09"), palette.base09.clone());
    values.insert(format!("{prefix}.base0A"), palette.base0_a.clone());
    values.insert(format!("{prefix}.base0B"), palette.base0_b.clone());
    values.insert(format!("{prefix}.base0C"), palette.base0_c.clone());
    values.insert(format!("{prefix}.base0D"), palette.base0_d.clone());
    values.insert(format!("{prefix}.base0E"), palette.base0_e.clone());
    values.insert(format!("{prefix}.base0F"), palette.base0_f.clone());
}

fn extend_syntax(values: &mut BTreeMap<String, String>, prefix: &str, palette: &SyntaxPalette) {
    values.insert(format!("{prefix}.boolean"), palette.boolean.clone());
    values.insert(format!("{prefix}.comment"), palette.comment.clone());
    values.insert(format!("{prefix}.emphasis"), palette.emphasis.clone());
    values.insert(format!("{prefix}.function"), palette.function.clone());
    values.insert(format!("{prefix}.keyword"), palette.keyword.clone());
    values.insert(format!("{prefix}.link"), palette.link.clone());
    values.insert(format!("{prefix}.literal"), palette.literal.clone());
    values.insert(format!("{prefix}.number"), palette.number.clone());
    values.insert(format!("{prefix}.operator"), palette.operator.clone());
    values.insert(format!("{prefix}.predictive"), palette.predictive.clone());
    values.insert(format!("{prefix}.punctuation"), palette.punctuation.clone());
    values.insert(format!("{prefix}.string"), palette.string.clone());
    values.insert(
        format!("{prefix}.stringRegex"),
        palette.string_regex.clone(),
    );
    values.insert(
        format!("{prefix}.stringSpecial"),
        palette.string_special.clone(),
    );
    values.insert(format!("{prefix}.title"), palette.title.clone());
    values.insert(format!("{prefix}.type"), palette.type_name.clone());
    values.insert(format!("{prefix}.variable"), palette.variable.clone());
}

pub(crate) fn render_template(template: &str, values: &BTreeMap<String, String>) -> Result<String> {
    let mut rendered = String::with_capacity(template.len());
    let mut rest = template;

    while let Some(start) = rest.find("{{") {
        rendered.push_str(&rest[..start]);
        let after_start = &rest[start + 2..];
        let end = after_start
            .find("}}")
            .context("unclosed template placeholder")?;
        let raw_key = &after_start[..end];
        let key = raw_key.trim();
        let value = render_placeholder(key, values)
            .with_context(|| format!("failed to render template placeholder {{{{{raw_key}}}}}"))?;
        rendered.push_str(&value);
        rest = &after_start[end + 2..];
    }

    rendered.push_str(rest);

    Ok(rendered)
}

fn render_placeholder(placeholder: &str, values: &BTreeMap<String, String>) -> Result<String> {
    if placeholder.is_empty() {
        return Ok(String::new());
    }

    let steps = split_top_level(placeholder, '|')?;
    let base = steps.first().context("empty template expression")?;
    let mut value = evaluate_expression(base, values)?;

    for step in steps.iter().skip(1) {
        value = apply_function(value, step, values)?;
    }

    render_value(value)
}

#[derive(Clone, Debug, PartialEq)]
enum Value {
    String(String),
    Number(f64),
    Color(ColorValue),
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum ColorValue {
    Hex(RgbaColor),
    Hct(HctColor),
    Hsv(HsvColor),
    Oklch(OklchColor),
}

impl ColorValue {
    fn to_hex(self) -> RgbaColor {
        match self {
            Self::Hex(color) => color,
            Self::Hct(color) => hct_to_rgba(color),
            Self::Hsv(color) => hsv_to_rgba(color),
            Self::Oklch(color) => oklch_to_rgba(color),
        }
    }

    fn to_hct(self) -> HctColor {
        match self {
            Self::Hex(color) => rgba_to_hct(color),
            Self::Hct(color) => color,
            Self::Hsv(color) => rgba_to_hct(hsv_to_rgba(color)),
            Self::Oklch(color) => rgba_to_hct(oklch_to_rgba(color)),
        }
    }

    fn to_hsv(self) -> HsvColor {
        match self {
            Self::Hex(color) => rgba_to_hsv(color),
            Self::Hct(color) => rgba_to_hsv(hct_to_rgba(color)),
            Self::Hsv(color) => color,
            Self::Oklch(color) => rgba_to_hsv(oklch_to_rgba(color)),
        }
    }

    fn to_oklch(self) -> OklchColor {
        match self {
            Self::Hex(color) => rgba_to_oklch(color),
            Self::Hct(color) => rgba_to_oklch(hct_to_rgba(color)),
            Self::Hsv(color) => rgba_to_oklch(hsv_to_rgba(color)),
            Self::Oklch(color) => color,
        }
    }

    fn with_alpha(self, alpha: f64) -> Self {
        let alpha = alpha.clamp(0.0, 1.0);

        match self {
            Self::Hex(color) => Self::Hex(RgbaColor {
                alpha: (alpha * 255.0).round() as u8,
                ..color
            }),
            Self::Hct(color) => Self::Hct(HctColor { alpha, ..color }),
            Self::Hsv(color) => Self::Hsv(HsvColor { alpha, ..color }),
            Self::Oklch(color) => Self::Oklch(OklchColor { alpha, ..color }),
        }
    }
}

fn evaluate_expression(expression: &str, values: &BTreeMap<String, String>) -> Result<Value> {
    let expression = expression.trim();

    if expression.is_empty() {
        return Ok(Value::String(String::new()));
    }

    let steps = split_top_level(expression, '|')?;
    let mut value = evaluate_atom(
        steps
            .first()
            .copied()
            .context("empty template expression")?,
        values,
    )?;

    for step in steps.iter().skip(1) {
        value = apply_function(value, step, values)?;
    }

    Ok(value)
}

fn evaluate_atom(expression: &str, values: &BTreeMap<String, String>) -> Result<Value> {
    if let Some((name, args)) = parse_function_call(expression)? {
        let args = args
            .into_iter()
            .map(|arg| evaluate_expression(arg, values))
            .collect::<Result<Vec<_>>>()?;
        return apply_constructor(name, &args);
    }

    if let Ok(number) = expression.parse::<f64>() {
        return Ok(Value::Number(number));
    }

    if let Some(value) = values.get(expression) {
        return Ok(Value::String(value.clone()));
    }

    if expression.contains('.') {
        return values
            .get(expression)
            .cloned()
            .map(Value::String)
            .with_context(|| format!("unknown template placeholder `{expression}`"));
    }

    Ok(Value::String(expression.to_string()))
}

fn render_value(value: Value) -> Result<String> {
    Ok(match value {
        Value::String(value) => value,
        Value::Number(value) => format_number(value),
        Value::Color(ColorValue::Hex(color)) => render_hex(color),
        Value::Color(ColorValue::Hct(color)) => {
            render_color_call("HCT", &[color.hue, color.chroma, color.tone], color.alpha)
        }
        Value::Color(ColorValue::Hsv(color)) => render_color_call(
            "HSV",
            &[color.hue, color.saturation, color.value],
            color.alpha,
        ),
        Value::Color(ColorValue::Oklch(color)) => render_color_call(
            "OKLCH",
            &[color.lightness, color.chroma, color.hue],
            color.alpha,
        ),
    })
}

fn render_color_call(name: &str, components: &[f64], alpha: f64) -> String {
    let mut parts = components
        .iter()
        .map(|component| format_number(*component))
        .collect::<Vec<_>>();

    if (alpha - 1.0).abs() > f64::EPSILON {
        parts.push(format_alpha_percent(alpha));
    }

    format!("{name}({})", parts.join(", "))
}

fn format_alpha_percent(alpha: f64) -> String {
    format!("{}%", format_number(alpha * 100.0))
}

fn render_hex(color: RgbaColor) -> String {
    if color.alpha == 255 {
        format!("#{:02x}{:02x}{:02x}", color.red, color.green, color.blue)
    } else {
        format!(
            "#{:02x}{:02x}{:02x}{:02x}",
            color.red, color.green, color.blue, color.alpha
        )
    }
}

fn apply_function(
    receiver: Value,
    operation: &str,
    values: &BTreeMap<String, String>,
) -> Result<Value> {
    let (name, args) = parse_function_call(operation)?
        .with_context(|| format!("expected function call, got `{operation}`"))?;

    if name == "with_alpha" {
        return Ok(Value::Color(expect_color(receiver)?.with_alpha(
            parse_with_alpha_arg(single_raw_arg(name, &args)?, values)?,
        )));
    }

    let args = args
        .into_iter()
        .map(|arg| evaluate_expression(arg, values))
        .collect::<Result<Vec<_>>>()?;

    match name {
        "to_hex" => Ok(Value::Color(ColorValue::Hex(
            expect_color(receiver)?.to_hex(),
        ))),
        "to_hct" => Ok(Value::Color(ColorValue::Hct(
            expect_color(receiver)?.to_hct(),
        ))),
        "to_hsv" => Ok(Value::Color(ColorValue::Hsv(
            expect_color(receiver)?.to_hsv(),
        ))),
        "to_oklch" => Ok(Value::Color(ColorValue::Oklch(
            expect_color(receiver)?.to_oklch(),
        ))),
        _ => Ok(Value::Color(apply_color_operation(
            expect_color(receiver)?,
            name,
            &args,
        )?)),
    }
}

fn apply_constructor(name: &str, args: &[Value]) -> Result<Value> {
    Ok(Value::Color(match name {
        "HEX" => ColorValue::Hex(parse_hex_constructor(args)?),
        "HCT" => ColorValue::Hct(parse_hct_constructor(args)?),
        "HSV" => ColorValue::Hsv(parse_hsv_constructor(args)?),
        "OKLCH" => ColorValue::Oklch(parse_oklch_constructor(args)?),
        _ => bail!("unknown function `{name}`"),
    }))
}

fn parse_hex_constructor(args: &[Value]) -> Result<RgbaColor> {
    if args.len() != 1 {
        bail!("`HEX` expects 1 argument, got {}", args.len());
    }

    let Value::String(value) = &args[0] else {
        bail!("`HEX` expects a hex string argument");
    };

    parse_hex_value(value)
}

fn parse_hct_constructor(args: &[Value]) -> Result<HctColor> {
    let alpha = parse_optional_alpha("HCT", args, 3, 4)?;

    Ok(HctColor {
        hue: as_number("hue", &args[0])?,
        chroma: as_number("chroma", &args[1])?.max(0.0),
        tone: as_number("tone", &args[2])?.clamp(0.0, 100.0),
        alpha,
    })
}

fn parse_hsv_constructor(args: &[Value]) -> Result<HsvColor> {
    let alpha = parse_optional_alpha("HSV", args, 3, 4)?;

    Ok(HsvColor {
        hue: as_number("hue", &args[0])?,
        saturation: as_number("saturation", &args[1])?.clamp(0.0, 1.0),
        value: as_number("value", &args[2])?.clamp(0.0, 1.0),
        alpha,
    })
}

fn parse_oklch_constructor(args: &[Value]) -> Result<OklchColor> {
    let alpha = parse_optional_alpha("OKLCH", args, 3, 4)?;

    Ok(OklchColor {
        lightness: as_number("lightness", &args[0])?.clamp(0.0, 1.0),
        chroma: as_number("chroma", &args[1])?.max(0.0),
        hue: as_number("hue", &args[2])?,
        alpha,
    })
}

fn parse_optional_alpha(name: &str, args: &[Value], minimum: usize, maximum: usize) -> Result<f64> {
    if !(minimum..=maximum).contains(&args.len()) {
        bail!(
            "`{name}` expects {minimum} or {maximum} arguments, got {}",
            args.len()
        );
    }

    if args.len() == maximum {
        parse_alpha_value("alpha", &args[maximum - 1], false)
    } else {
        Ok(1.0)
    }
}

fn parse_with_alpha_arg(arg: &str, values: &BTreeMap<String, String>) -> Result<f64> {
    let arg = arg.trim();

    if let Ok(alpha) = parse_hex_alpha(arg) {
        return Ok(alpha);
    }

    parse_alpha_value("alpha", &evaluate_expression(arg, values)?, true)
}

fn parse_alpha_value(label: &str, value: &Value, allow_hex: bool) -> Result<f64> {
    match value {
        Value::String(value) => {
            let value = value.trim();

            if allow_hex {
                if let Ok(alpha) = parse_hex_alpha(value) {
                    return Ok(alpha);
                }
            }

            parse_percent_alpha(label, value, allow_hex)
        }
        Value::Number(value) => bail!(
            "invalid {label} `{}`; expected {}",
            format_number(*value),
            alpha_syntax_hint(allow_hex)
        ),
        Value::Color(_) => bail!("expected {label} as {}", alpha_syntax_hint(allow_hex)),
    }
}

fn parse_percent_alpha(label: &str, value: &str, allow_hex: bool) -> Result<f64> {
    let Some(percent) = value.strip_suffix('%') else {
        bail!(
            "invalid {label} `{value}`; expected {}",
            alpha_syntax_hint(allow_hex)
        );
    };

    let percent = percent
        .trim()
        .parse::<f64>()
        .with_context(|| format!("invalid {label} `{value}`"))?;

    Ok(percent.clamp(0.0, 100.0) / 100.0)
}

fn parse_hex_alpha(value: &str) -> Result<f64> {
    if value.len() != 2 {
        bail!("expected 2-digit hex alpha");
    }

    Ok(f64::from(
        u8::from_str_radix(value, 16).with_context(|| format!("invalid alpha `{value}`"))?,
    ) / 255.0)
}

fn alpha_syntax_hint(allow_hex: bool) -> &'static str {
    if allow_hex {
        "0% to 100% or 2-digit hex alpha"
    } else {
        "0% to 100%"
    }
}

fn as_number(label: &str, value: &Value) -> Result<f64> {
    match value {
        Value::Number(value) => Ok(*value),
        Value::String(value) => value
            .parse::<f64>()
            .with_context(|| format!("invalid {label} `{value}`")),
        Value::Color(_) => bail!("expected numeric {label}"),
    }
}

fn expect_color(value: Value) -> Result<ColorValue> {
    match value {
        Value::Color(color) => Ok(color),
        Value::String(value) => parse_hex_value(&value)
            .map(ColorValue::Hex)
            .with_context(|| format!("`{value}` is not a color value")),
        Value::Number(value) => bail!("`{value}` is not a color value"),
    }
}

fn apply_color_operation(color: ColorValue, name: &str, args: &[Value]) -> Result<ColorValue> {
    match (color, name) {
        (ColorValue::Hct(color), "rotate") => Ok(ColorValue::Hct(HctColor {
            hue: color.hue + as_number("degrees", single_arg(name, args)?)?,
            ..color
        })),
        (ColorValue::Hct(color), "chroma") => Ok(ColorValue::Hct(HctColor {
            chroma: as_number("chroma", single_arg(name, args)?)?.max(0.0),
            ..color
        })),
        (ColorValue::Hct(color), "chroma_add") => Ok(ColorValue::Hct(HctColor {
            chroma: (color.chroma + as_number("delta", single_arg(name, args)?)?).max(0.0),
            ..color
        })),
        (ColorValue::Hct(color), "tone") => Ok(ColorValue::Hct(HctColor {
            tone: as_number("tone", single_arg(name, args)?)?.clamp(0.0, 100.0),
            ..color
        })),
        (ColorValue::Hct(color), "tone_add") => Ok(ColorValue::Hct(HctColor {
            tone: (color.tone + as_number("delta", single_arg(name, args)?)?).clamp(0.0, 100.0),
            ..color
        })),
        (ColorValue::Hct(color), "readable") => {
            if args.len() != 2 {
                bail!("`readable` expects 2 arguments, got {}", args.len());
            }

            let background = expect_color(args[0].clone())?.to_hex();
            let ratio = as_number("ratio", &args[1])?;
            let readable = ensure_readable(
                rgba_to_argb(hct_to_rgba(color)),
                rgba_to_argb(background),
                ratio,
            );
            let mut readable_hct = rgba_to_hct(argb_to_rgba(readable));
            readable_hct.alpha = color.alpha;
            Ok(ColorValue::Hct(readable_hct))
        }
        (ColorValue::Hex(color), "mix") => {
            let other = expect_same_format(args, ColorKind::Hex)?;
            Ok(ColorValue::Hex(mix_hex(
                color,
                other.to_hex(),
                mix_amount(args)?,
            )))
        }
        (ColorValue::Hct(color), "mix") => {
            let other = expect_same_format(args, ColorKind::Hct)?;
            Ok(ColorValue::Hct(mix_hct(
                color,
                other.to_hct(),
                mix_amount(args)?,
            )))
        }
        (ColorValue::Hsv(color), "mix") => {
            let other = expect_same_format(args, ColorKind::Hsv)?;
            Ok(ColorValue::Hsv(mix_hsv(
                color,
                other.to_hsv(),
                mix_amount(args)?,
            )))
        }
        (ColorValue::Oklch(color), "mix") => {
            let other = expect_same_format(args, ColorKind::Oklch)?;
            Ok(ColorValue::Oklch(mix_oklch(
                color,
                other.to_oklch(),
                mix_amount(args)?,
            )))
        }
        (ColorValue::Oklch(color), "rotate") => Ok(ColorValue::Oklch(OklchColor {
            hue: color.hue + as_number("degrees", single_arg(name, args)?)?,
            ..color
        })),
        (ColorValue::Oklch(color), "chroma") => Ok(ColorValue::Oklch(OklchColor {
            chroma: as_number("chroma", single_arg(name, args)?)?.max(0.0),
            ..color
        })),
        (ColorValue::Oklch(color), "chroma_add") => Ok(ColorValue::Oklch(OklchColor {
            chroma: (color.chroma + as_number("delta", single_arg(name, args)?)?).max(0.0),
            ..color
        })),
        (ColorValue::Oklch(color), "lightness") => Ok(ColorValue::Oklch(OklchColor {
            lightness: as_number("lightness", single_arg(name, args)?)?.clamp(0.0, 1.0),
            ..color
        })),
        (ColorValue::Oklch(color), "lightness_add") => Ok(ColorValue::Oklch(OklchColor {
            lightness: (color.lightness + as_number("delta", single_arg(name, args)?)?)
                .clamp(0.0, 1.0),
            ..color
        })),
        (ColorValue::Oklch(color), "readable") => {
            if args.len() != 2 {
                bail!("`readable` expects 2 arguments, got {}", args.len());
            }

            // Enforce contrast in rendered RGB space, then convert back to OKLCH.
            let background = expect_color(args[0].clone())?.to_hex();
            let ratio = as_number("ratio", &args[1])?;
            let readable = ensure_readable(
                rgba_to_argb(oklch_to_rgba(color)),
                rgba_to_argb(background),
                ratio,
            );
            let mut readable_oklch = rgba_to_oklch(argb_to_rgba(readable));
            readable_oklch.alpha = color.alpha;
            Ok(ColorValue::Oklch(readable_oklch))
        }
        (ColorValue::Hex(_), _) => bail!("`{name}` is not available for HEX colors"),
        (ColorValue::Hct(_), _) => bail!("unknown HCT operation `{name}`"),
        (ColorValue::Hsv(_), _) => bail!("`{name}` is not available for HSV colors"),
        (ColorValue::Oklch(_), _) => bail!("`{name}` is not available for OKLCH colors"),
    }
}

#[derive(Clone, Copy)]
enum ColorKind {
    Hex,
    Hct,
    Hsv,
    Oklch,
}

fn expect_same_format(args: &[Value], kind: ColorKind) -> Result<ColorValue> {
    if args.len() != 2 {
        bail!("`mix` expects 2 arguments, got {}", args.len());
    }

    let other = expect_color(args[0].clone())?;
    let same = matches!(
        (kind, other),
        (ColorKind::Hex, ColorValue::Hex(_))
            | (ColorKind::Hct, ColorValue::Hct(_))
            | (ColorKind::Hsv, ColorValue::Hsv(_))
            | (ColorKind::Oklch, ColorValue::Oklch(_))
    );

    if same {
        Ok(other)
    } else {
        bail!("`mix` requires colors in the same format")
    }
}

fn mix_amount(args: &[Value]) -> Result<f64> {
    as_number("amount", &args[1]).map(|value| value.clamp(0.0, 1.0))
}

fn mix_hex(left: RgbaColor, right: RgbaColor, amount: f64) -> RgbaColor {
    let mixed = mix(rgba_to_argb(left), rgba_to_argb(right), amount);

    RgbaColor {
        alpha: interpolate(f64::from(left.alpha), f64::from(right.alpha), amount).round() as u8,
        ..argb_to_rgba(mixed)
    }
}

fn mix_hct(left: HctColor, right: HctColor, amount: f64) -> HctColor {
    HctColor {
        hue: interpolate_hue(left.hue, right.hue, amount),
        chroma: interpolate(left.chroma, right.chroma, amount),
        tone: interpolate(left.tone, right.tone, amount),
        alpha: interpolate(left.alpha, right.alpha, amount),
    }
}

fn mix_hsv(left: HsvColor, right: HsvColor, amount: f64) -> HsvColor {
    HsvColor {
        hue: interpolate_hue(left.hue, right.hue, amount),
        saturation: interpolate(left.saturation, right.saturation, amount),
        value: interpolate(left.value, right.value, amount),
        alpha: interpolate(left.alpha, right.alpha, amount),
    }
}

fn mix_oklch(left: OklchColor, right: OklchColor, amount: f64) -> OklchColor {
    OklchColor {
        lightness: interpolate(left.lightness, right.lightness, amount),
        chroma: interpolate(left.chroma, right.chroma, amount),
        hue: interpolate_hue(left.hue, right.hue, amount),
        alpha: interpolate(left.alpha, right.alpha, amount),
    }
}

fn interpolate_hue(left: f64, right: f64, amount: f64) -> f64 {
    let delta = (right - left + 180.0).rem_euclid(360.0) - 180.0;
    normalize_hue(left + delta * amount)
}

fn parse_function_call(operation: &str) -> Result<Option<(&str, Vec<&str>)>> {
    let Some(open) = operation.find('(') else {
        return Ok(None);
    };

    if !operation.ends_with(')') {
        bail!("expected closing `)` in `{operation}`");
    }

    let name = operation[..open].trim();
    if name.is_empty() {
        bail!("missing function name in `{operation}`");
    }

    let args = operation[open + 1..operation.len() - 1].trim();
    let parsed = if args.is_empty() {
        Vec::new()
    } else {
        split_top_level(args, ',')?
    };

    Ok(Some((name, parsed)))
}

fn split_top_level(input: &str, separator: char) -> Result<Vec<&str>> {
    let mut parts = Vec::new();
    let mut depth = 0usize;
    let mut start = 0usize;

    for (index, ch) in input.char_indices() {
        match ch {
            '(' => depth += 1,
            ')' => {
                depth = depth
                    .checked_sub(1)
                    .with_context(|| format!("unexpected closing `)` in `{input}`"))?;
            }
            _ if ch == separator && depth == 0 => {
                parts.push(input[start..index].trim());
                start = index + ch.len_utf8();
            }
            _ => {}
        }
    }

    if depth != 0 {
        bail!("unclosed `(` in `{input}`");
    }

    parts.push(input[start..].trim());

    Ok(parts)
}

fn single_arg<'a>(name: &str, args: &'a [Value]) -> Result<&'a Value> {
    if args.len() != 1 {
        bail!("`{name}` expects 1 argument, got {}", args.len());
    }

    Ok(&args[0])
}

fn single_raw_arg<'a>(name: &str, args: &'a [&str]) -> Result<&'a str> {
    if args.len() != 1 {
        bail!("`{name}` expects 1 argument, got {}", args.len());
    }

    Ok(args[0])
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::color::{contrast_ratio, parse_hex_value};

    fn test_values() -> BTreeMap<String, String> {
        BTreeMap::from([
            ("input.kind".to_string(), "image".to_string()),
            ("input.value".to_string(), "/tmp/wallpaper.png".to_string()),
            ("scheme".to_string(), "tonal-spot".to_string()),
            (
                "color.light.surface_container_low".to_string(),
                "#f8f9ff".to_string(),
            ),
            (
                "color.dark.surface_container_low".to_string(),
                "#11131a".to_string(),
            ),
            ("color.light.primary".to_string(), "#3f6aa1".to_string()),
            ("color.dark.primary".to_string(), "#aac7ff".to_string()),
            (
                "color.dark.outline_variant".to_string(),
                "#444746".to_string(),
            ),
            ("syntax.dark.keyword".to_string(), "#f0a3ff".to_string()),
        ])
    }

    #[test]
    fn renders_plain_placeholders_unchanged() {
        let rendered =
            render_template("{{ color.light.primary }} {{ scheme }}", &test_values()).unwrap();

        assert_eq!(rendered, "#3f6aa1 tonal-spot");
    }

    #[test]
    fn renders_empty_expression_as_empty_string() {
        let rendered = render_template("a{{ }}b", &test_values()).unwrap();

        assert_eq!(rendered, "ab");
    }

    #[test]
    fn unknown_non_dotted_tokens_are_literals() {
        let rendered = render_template(
            "{{ value }} {{ color.dark.outline_variant }}",
            &test_values(),
        )
        .unwrap();

        assert_eq!(rendered, "value #444746");
    }

    #[test]
    fn applies_pipe_color_operations_in_hct() {
        let values = test_values();
        let rendered = render_template(
            "{{ color.dark.primary | to_hct() | rotate(145) | chroma(40) | tone(34) }}",
            &values,
        )
        .unwrap();

        assert!(rendered.starts_with("HCT("));
    }

    #[test]
    fn applies_pipe_color_operations_in_oklch() {
        let values = test_values();
        let rendered = render_template(
            "{{ color.dark.primary | to_oklch() | rotate(145) | chroma(0.18) | lightness(0.7) }}",
            &values,
        )
        .unwrap();

        assert!(rendered.starts_with("OKLCH("));
    }

    #[test]
    fn converts_between_formats() {
        let rendered = render_template("{{ HEX(ffff00) | to_hsv() }}", &test_values()).unwrap();

        assert!(rendered.starts_with("HSV("));
    }

    #[test]
    fn supports_nested_constructor_args() {
        let rendered =
            render_template("{{ HEX(ffcc00) | to_hsv() | to_hex() }}", &test_values()).unwrap();

        assert_eq!(rendered, "#ffcc00");
    }

    #[test]
    fn mix_and_readable_keep_contrast() {
        let values = test_values();
        let rendered = render_template(
            "{{ color.dark.primary | to_hct() | tone(74) | readable(color.dark.surface_container_low, 4.5) | to_hex() }}",
            &values,
        )
        .unwrap();

        let foreground = rgba_to_argb(parse_hex_value(&rendered).unwrap());
        let background = rgba_to_argb(
            parse_hex_value(values.get("color.dark.surface_container_low").unwrap()).unwrap(),
        );

        assert!(contrast_ratio(foreground, background) >= 4.5);
    }

    #[test]
    fn oklch_readable_keeps_contrast() {
        let values = test_values();
        let rendered = render_template(
            "{{ color.dark.primary | to_oklch() | lightness(0.74) | readable(color.dark.surface_container_low, 4.5) | to_hex() }}",
            &values,
        )
        .unwrap();

        let foreground = rgba_to_argb(parse_hex_value(&rendered).unwrap());
        let background = rgba_to_argb(
            parse_hex_value(values.get("color.dark.surface_container_low").unwrap()).unwrap(),
        );

        assert!(contrast_ratio(foreground, background) >= 4.5);
    }

    #[test]
    fn with_alpha_updates_hex_output() {
        let rendered = render_template(
            "{{ color.dark.outline_variant | with_alpha(40) | to_hex() }}",
            &test_values(),
        )
        .unwrap();

        assert_eq!(rendered, "#44474640");
    }

    #[test]
    fn with_alpha_accepts_percentages() {
        let rendered = render_template(
            "{{ color.dark.outline_variant | with_alpha(25%) | to_hex() }}",
            &test_values(),
        )
        .unwrap();

        assert_eq!(rendered, "#44474640");
    }

    #[test]
    fn constructors_render_alpha_as_percentages() {
        let rendered = render_template("{{ HCT(210, 32, 44, 25%) }}", &test_values()).unwrap();

        assert_eq!(rendered, "HCT(210, 32, 44, 25%)");
    }

    #[test]
    fn rejects_legacy_float_alpha_syntax() {
        let error = format!(
            "{:#}",
            render_template(
                "{{ color.dark.outline_variant | with_alpha(0.251) | to_hex() }}",
                &test_values()
            )
            .unwrap_err()
        );

        assert!(error.contains("expected 0% to 100% or 2-digit hex alpha"));
    }

    #[test]
    fn reports_invalid_operations() {
        let error = format!(
            "{:#}",
            render_template(
                "{{ color.dark.primary | to_hsv() | tone(45) }}",
                &test_values()
            )
            .unwrap_err()
        );

        assert!(error.contains("`tone` is not available for HSV colors"));
    }

    #[test]
    fn rejects_removed_source_namespace() {
        let error = format!(
            "{:#}",
            render_template("{{ source.color }}", &test_values()).unwrap_err()
        );

        assert!(error.contains("unknown template placeholder `source.color`"));
    }

    #[test]
    fn rejects_mixed_format_helpers() {
        let error = format!(
            "{:#}",
            render_template(
                "{{ HEX(ff0000) | to_hsv() | mix(HEX(00ff00), 0.5) }}",
                &test_values()
            )
            .unwrap_err()
        );

        assert!(error.contains("`mix` requires colors in the same format"));
    }

    #[test]
    fn rejects_unknown_dotted_paths() {
        let error = format!(
            "{:#}",
            render_template("{{ color.dark.missing }}", &test_values()).unwrap_err()
        );

        assert!(error.contains("unknown template placeholder `color.dark.missing`"));
    }
}
