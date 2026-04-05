use anyhow::{Context, Result, bail};
use material_colors::color::{Argb, Lab};
use material_colors::hct::Hct;
use palette::{FromColor, Hsv, LinSrgb, Oklch, Srgb};

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct RgbaColor {
    pub(crate) red: u8,
    pub(crate) green: u8,
    pub(crate) blue: u8,
    pub(crate) alpha: u8,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct HctColor {
    pub(crate) hue: f64,
    pub(crate) chroma: f64,
    pub(crate) tone: f64,
    pub(crate) alpha: f64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct HsvColor {
    pub(crate) hue: f64,
    pub(crate) saturation: f64,
    pub(crate) value: f64,
    pub(crate) alpha: f64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct OklchColor {
    pub(crate) lightness: f64,
    pub(crate) chroma: f64,
    pub(crate) hue: f64,
    pub(crate) alpha: f64,
}

pub(crate) fn parse_hex_value(value: &str) -> Result<RgbaColor> {
    let hex = value.strip_prefix('#').unwrap_or(value);

    let [red, green, blue, alpha] = match hex.len() {
        6 => [
            parse_hex_channel(&hex[0..2], value, "red")?,
            parse_hex_channel(&hex[2..4], value, "green")?,
            parse_hex_channel(&hex[4..6], value, "blue")?,
            255,
        ],
        8 => [
            parse_hex_channel(&hex[0..2], value, "red")?,
            parse_hex_channel(&hex[2..4], value, "green")?,
            parse_hex_channel(&hex[4..6], value, "blue")?,
            parse_hex_channel(&hex[6..8], value, "alpha")?,
        ],
        _ => bail!("expected RRGGBB or RRGGBBAA hex color, got `{value}`"),
    };

    Ok(RgbaColor {
        red,
        green,
        blue,
        alpha,
    })
}

fn parse_hex_channel(value: &str, raw: &str, channel: &str) -> Result<u8> {
    u8::from_str_radix(value, 16).with_context(|| format!("invalid {channel} channel in `{raw}`"))
}

pub(crate) fn tone_color(hue: f64, chroma: f64, tone: f64) -> Argb {
    let hct = Hct::from(normalize_hue(hue), chroma, tone.clamp(0.0, 100.0));
    Argb::from(hct)
}

pub(crate) fn normalize_hue(hue: f64) -> f64 {
    hue.rem_euclid(360.0)
}

pub(crate) fn ensure_readable(color: Argb, background: Argb, minimum_ratio: f64) -> Argb {
    let bg_lstar = background.as_lstar();
    let mut hct = Hct::new(color);

    for _ in 0..24 {
        if contrast_ratio(Argb::from(hct), background) >= minimum_ratio {
            return Argb::from(hct);
        }

        let direction = if bg_lstar > 50.0 { -4.0 } else { 4.0 };
        hct.set_tone((hct.get_tone() + direction).clamp(0.0, 100.0));
    }

    Argb::from(hct)
}

pub(crate) fn contrast_ratio(foreground: Argb, background: Argb) -> f64 {
    let foreground_luminance = relative_luminance(foreground);
    let background_luminance = relative_luminance(background);
    let lighter = foreground_luminance.max(background_luminance);
    let darker = foreground_luminance.min(background_luminance);

    (lighter + 0.05) / (darker + 0.05)
}

fn relative_luminance(color: Argb) -> f64 {
    let to_linear = |component: u8| {
        let value = f64::from(component) / 255.0;
        if value <= 0.04045 {
            value / 12.92
        } else {
            ((value + 0.055) / 1.055).powf(2.4)
        }
    };

    let red = to_linear(color.red);
    let green = to_linear(color.green);
    let blue = to_linear(color.blue);

    0.2126 * red + 0.7152 * green + 0.0722 * blue
}

pub(crate) fn mix(left: Argb, right: Argb, amount: f64) -> Argb {
    let amount = amount.clamp(0.0, 1.0);

    let left_lab = Lab::from(left);
    let right_lab = Lab::from(right);

    let blended = Lab::new(
        interpolate(left_lab.l, right_lab.l, amount),
        interpolate(left_lab.a, right_lab.a, amount),
        interpolate(left_lab.b, right_lab.b, amount),
    );

    Argb::from(blended)
}

pub(crate) fn interpolate(left: f64, right: f64, amount: f64) -> f64 {
    left + (right - left) * amount
}

pub(crate) fn rgba_to_argb(color: RgbaColor) -> Argb {
    Argb::new(255, color.red, color.green, color.blue)
}

pub(crate) fn argb_to_rgba(color: Argb) -> RgbaColor {
    RgbaColor {
        red: color.red,
        green: color.green,
        blue: color.blue,
        alpha: 255,
    }
}

pub(crate) fn rgba_to_hct(color: RgbaColor) -> HctColor {
    let hct = Hct::new(rgba_to_argb(color));

    HctColor {
        hue: hct.get_hue(),
        chroma: hct.get_chroma(),
        tone: hct.get_tone(),
        alpha: alpha_to_float(color.alpha),
    }
}

pub(crate) fn hct_to_rgba(color: HctColor) -> RgbaColor {
    let argb = tone_color(color.hue, color.chroma, color.tone);

    RgbaColor {
        red: argb.red,
        green: argb.green,
        blue: argb.blue,
        alpha: float_to_alpha(color.alpha),
    }
}

pub(crate) fn rgba_to_hsv(color: RgbaColor) -> HsvColor {
    let rgb = rgba_to_srgb(color).into_linear();
    let hsv = Hsv::from_color(rgb);

    HsvColor {
        hue: f64::from(hsv.hue.into_positive_degrees()),
        saturation: f64::from(hsv.saturation),
        value: f64::from(hsv.value),
        alpha: alpha_to_float(color.alpha),
    }
}

pub(crate) fn hsv_to_rgba(color: HsvColor) -> RgbaColor {
    let hsv = Hsv::new(
        normalize_hue(color.hue) as f32,
        color.saturation.clamp(0.0, 1.0) as f32,
        color.value.clamp(0.0, 1.0) as f32,
    );
    let rgb = Srgb::from_linear(LinSrgb::from_color(hsv));

    srgb_to_rgba(rgb, color.alpha)
}

pub(crate) fn rgba_to_oklch(color: RgbaColor) -> OklchColor {
    let rgb = rgba_to_srgb(color).into_linear();
    let oklch = Oklch::from_color(rgb);

    OklchColor {
        lightness: f64::from(oklch.l),
        chroma: f64::from(oklch.chroma),
        hue: f64::from(oklch.hue.into_positive_degrees()),
        alpha: alpha_to_float(color.alpha),
    }
}

pub(crate) fn oklch_to_rgba(color: OklchColor) -> RgbaColor {
    let oklch = Oklch::new(
        color.lightness.clamp(0.0, 1.0) as f32,
        color.chroma.max(0.0) as f32,
        normalize_hue(color.hue) as f32,
    );
    let rgb = Srgb::from_linear(LinSrgb::from_color(oklch));

    srgb_to_rgba(rgb, color.alpha)
}

pub(crate) fn format_number(value: f64) -> String {
    let mut rendered = format!("{value:.4}");

    while rendered.contains('.') && rendered.ends_with('0') {
        rendered.pop();
    }

    if rendered.ends_with('.') {
        rendered.pop();
    }

    if rendered == "-0" {
        "0".to_string()
    } else {
        rendered
    }
}

pub(crate) fn alpha_to_float(alpha: u8) -> f64 {
    f64::from(alpha) / 255.0
}

pub(crate) fn float_to_alpha(alpha: f64) -> u8 {
    (alpha.clamp(0.0, 1.0) * 255.0).round() as u8
}

fn rgba_to_srgb(color: RgbaColor) -> Srgb<f32> {
    Srgb::new(
        f32::from(color.red) / 255.0,
        f32::from(color.green) / 255.0,
        f32::from(color.blue) / 255.0,
    )
}

fn srgb_to_rgba(color: Srgb<f32>, alpha: f64) -> RgbaColor {
    RgbaColor {
        red: (color.red.clamp(0.0, 1.0) * 255.0).round() as u8,
        green: (color.green.clamp(0.0, 1.0) * 255.0).round() as u8,
        blue: (color.blue.clamp(0.0, 1.0) * 255.0).round() as u8,
        alpha: float_to_alpha(alpha),
    }
}
