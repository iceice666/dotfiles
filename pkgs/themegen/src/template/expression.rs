use std::collections::HashMap;

use anyhow::{bail, Context, Result};

use crate::color::{
    argb_to_rgba, ensure_readable, format_number, hct_to_rgba, interpolate, mix, normalize_hue,
    oklch_to_rgba, parse_hex_value, rgba_to_argb, rgba_to_hct, rgba_to_oklch, HctColor,
    OklchColor, RgbaColor,
};

pub(super) fn evaluate_header_expression(
    expression: &str,
    values: &HashMap<String, String>,
) -> Result<String> {
    if !expression.contains('(') {
        return lookup(expression, values);
    }

    let (name, args) = parse_function_call(expression)?;

    match name {
        "alpha" => {
            expect_arg_count(name, &args, 3)?;
            let color = lookup_color(args[0], values)?.with_alpha(parse_alpha(args[1])?);
            render_color(color.to_hex(), parse_format(args[2])?)
        }
        "mix" => {
            expect_arg_count(name, &args, 5)?;
            let amount = parse_number("amount", args[2])?.clamp(0.0, 1.0);
            let color = match parse_space(args[3])? {
                ColorSpace::Hex => ColorValue::Hex(mix_hex(
                    lookup_color(args[0], values)?.to_hex(),
                    lookup_color(args[1], values)?.to_hex(),
                    amount,
                )),
                ColorSpace::Hct => ColorValue::Hct(mix_hct(
                    lookup_color(args[0], values)?.to_hct(),
                    lookup_color(args[1], values)?.to_hct(),
                    amount,
                )),
                ColorSpace::Oklch => ColorValue::Oklch(mix_oklch(
                    lookup_color(args[0], values)?.to_oklch(),
                    lookup_color(args[1], values)?.to_oklch(),
                    amount,
                )),
            };

            render_color(color.to_hex(), parse_format(args[4])?)
        }
        "lightness_add" => {
            expect_arg_count(name, &args, 4)?;
            expect_space(name, args[2], ColorSpace::Oklch)?;
            let mut color = lookup_color(args[0], values)?.to_oklch();
            color.lightness =
                (color.lightness + parse_number("delta", args[1])?).clamp(0.0, 1.0);
            render_color(oklch_to_rgba(color), parse_format(args[3])?)
        }
        "tone" => {
            expect_arg_count(name, &args, 4)?;
            expect_space(name, args[2], ColorSpace::Hct)?;
            let mut color = lookup_color(args[0], values)?.to_hct();
            color.tone = parse_number("tone", args[1])?.clamp(0.0, 100.0);
            render_color(hct_to_rgba(color), parse_format(args[3])?)
        }
        "readable" => {
            expect_arg_count(name, &args, 5)?;
            expect_space(name, args[3], ColorSpace::Hct)?;
            let color = readable_hct(
                lookup_color(args[0], values)?.to_hct(),
                lookup_color(args[1], values)?.to_hex(),
                parse_number("ratio", args[2])?,
            );
            render_color(hct_to_rgba(color), parse_format(args[4])?)
        }
        "readable_alpha" => {
            expect_arg_count(name, &args, 6)?;
            expect_space(name, args[4], ColorSpace::Hct)?;
            let color = readable_hct(
                lookup_color(args[0], values)?.to_hct(),
                lookup_color(args[1], values)?.to_hex(),
                parse_number("ratio", args[2])?,
            )
            .with_alpha(parse_alpha(args[3])?);
            render_color(hct_to_rgba(color), parse_format(args[5])?)
        }
        "tone_alpha" => {
            expect_arg_count(name, &args, 5)?;
            expect_space(name, args[3], ColorSpace::Hct)?;
            let mut color = lookup_color(args[0], values)?.to_hct();
            color.tone = parse_number("tone", args[1])?.clamp(0.0, 100.0);
            color = color.with_alpha(parse_alpha(args[2])?);
            render_color(hct_to_rgba(color), parse_format(args[4])?)
        }
        "tone_readable" => {
            expect_arg_count(name, &args, 6)?;
            expect_space(name, args[4], ColorSpace::Hct)?;
            let mut color = lookup_color(args[0], values)?.to_hct();
            color.tone = parse_number("tone", args[1])?.clamp(0.0, 100.0);
            let color = readable_hct(
                color,
                lookup_color(args[2], values)?.to_hex(),
                parse_number("ratio", args[3])?,
            );
            render_color(hct_to_rgba(color), parse_format(args[5])?)
        }
        _ => bail!("unknown themegen header function `{name}`"),
    }
}

pub(super) fn lookup(name: &str, values: &HashMap<String, String>) -> Result<String> {
    values
        .get(name.trim())
        .cloned()
        .with_context(|| format!("unknown template placeholder `{}`", name.trim()))
}

fn lookup_color(name: &str, values: &HashMap<String, String>) -> Result<ColorValue> {
    parse_hex_value(&lookup(name, values)?)
        .map(ColorValue::Hex)
        .with_context(|| format!("`{}` is not a color value", name.trim()))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ColorSpace {
    Hex,
    Hct,
    Oklch,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum OutputFormat {
    Hex,
    Raw,
    Rgba,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum ColorValue {
    Hex(RgbaColor),
    Hct(HctColor),
    Oklch(OklchColor),
}

impl ColorValue {
    fn to_hex(self) -> RgbaColor {
        match self {
            Self::Hex(color) => color,
            Self::Hct(color) => hct_to_rgba(color),
            Self::Oklch(color) => oklch_to_rgba(color),
        }
    }

    fn to_hct(self) -> HctColor {
        match self {
            Self::Hex(color) => rgba_to_hct(color),
            Self::Hct(color) => color,
            Self::Oklch(color) => rgba_to_hct(oklch_to_rgba(color)),
        }
    }

    fn to_oklch(self) -> OklchColor {
        match self {
            Self::Hex(color) => rgba_to_oklch(color),
            Self::Hct(color) => rgba_to_oklch(hct_to_rgba(color)),
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
            Self::Hct(color) => Self::Hct(color.with_alpha(alpha)),
            Self::Oklch(color) => Self::Oklch(OklchColor { alpha, ..color }),
        }
    }
}

trait HctAlpha {
    fn with_alpha(self, alpha: f64) -> Self;
}

impl HctAlpha for HctColor {
    fn with_alpha(self, alpha: f64) -> Self {
        Self { alpha, ..self }
    }
}

fn parse_function_call(expression: &str) -> Result<(&str, Vec<&str>)> {
    let Some(open) = expression.find('(') else {
        bail!("expected function call, got `{expression}`");
    };
    if !expression.ends_with(')') {
        bail!("expected closing `)` in `{expression}`");
    }

    let name = expression[..open].trim();
    if name.is_empty() {
        bail!("missing function name in `{expression}`");
    }

    let raw_args = expression[open + 1..expression.len() - 1].trim();
    let args = if raw_args.is_empty() {
        Vec::new()
    } else {
        raw_args.split(',').map(str::trim).collect()
    };

    Ok((name, args))
}

fn expect_arg_count(name: &str, args: &[&str], expected: usize) -> Result<()> {
    if args.len() != expected {
        bail!("`{name}` expects {expected} arguments, got {}", args.len());
    }

    Ok(())
}

fn parse_space(value: &str) -> Result<ColorSpace> {
    match value.trim() {
        "hex" => Ok(ColorSpace::Hex),
        "hct" => Ok(ColorSpace::Hct),
        "oklch" => Ok(ColorSpace::Oklch),
        value => bail!("unknown color space `{value}`"),
    }
}

fn expect_space(name: &str, value: &str, expected: ColorSpace) -> Result<()> {
    let actual = parse_space(value)?;
    if actual != expected {
        bail!("`{name}` expects color space `{expected:?}`, got `{actual:?}`");
    }

    Ok(())
}

fn parse_format(value: &str) -> Result<OutputFormat> {
    match value.trim() {
        "hex" => Ok(OutputFormat::Hex),
        "raw" => Ok(OutputFormat::Raw),
        "rgba" => Ok(OutputFormat::Rgba),
        value => bail!("unknown output format `{value}`"),
    }
}

fn parse_number(label: &str, value: &str) -> Result<f64> {
    value
        .trim()
        .parse::<f64>()
        .with_context(|| format!("invalid {label} `{}`", value.trim()))
}

fn parse_alpha(value: &str) -> Result<f64> {
    let value = value.trim();

    if let Some(hex) = value.strip_prefix("0x") {
        if hex.len() != 2 {
            bail!("invalid alpha `{value}`; expected 0xNN or N%");
        }

        return Ok(f64::from(
            u8::from_str_radix(hex, 16).with_context(|| format!("invalid alpha `{value}`"))?,
        ) / 255.0);
    }

    let Some(percent) = value.strip_suffix('%') else {
        bail!("invalid alpha `{value}`; expected 0xNN or N%");
    };
    Ok(percent
        .trim()
        .parse::<f64>()
        .with_context(|| format!("invalid alpha `{value}`"))?
        .clamp(0.0, 100.0)
        / 100.0)
}

fn render_color(color: RgbaColor, format: OutputFormat) -> Result<String> {
    Ok(match format {
        OutputFormat::Hex => render_hex(color),
        OutputFormat::Raw => render_raw_hex(color),
        OutputFormat::Rgba => render_rgba_function(color),
    })
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

fn render_raw_hex(color: RgbaColor) -> String {
    format!(
        "{:02x}{:02x}{:02x}{:02x}",
        color.red, color.green, color.blue, color.alpha
    )
}

fn render_rgba_function(color: RgbaColor) -> String {
    format!(
        "rgba({}, {}, {}, {})",
        color.red,
        color.green,
        color.blue,
        format_number(f64::from(color.alpha) / 255.0)
    )
}

fn readable_hct(color: HctColor, background: RgbaColor, ratio: f64) -> HctColor {
    let readable = ensure_readable(
        rgba_to_argb(hct_to_rgba(color)),
        rgba_to_argb(background),
        ratio,
    );
    let mut readable_hct = rgba_to_hct(argb_to_rgba(readable));
    readable_hct.alpha = color.alpha;
    readable_hct
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
