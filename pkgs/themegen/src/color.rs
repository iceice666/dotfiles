use anyhow::{Context, Result, bail};
use material_colors::color::{Argb, Lab};
use material_colors::hct::Hct;

pub(crate) fn parse_hex_color(value: &str) -> Result<Argb> {
    let hex = value
        .strip_prefix('#')
        .with_context(|| format!("expected #RRGGBB color, got `{value}`"))?;

    if hex.len() != 6 {
        bail!("expected #RRGGBB color, got `{value}`");
    }

    let red = u8::from_str_radix(&hex[0..2], 16)
        .with_context(|| format!("invalid red channel in `{value}`"))?;
    let green = u8::from_str_radix(&hex[2..4], 16)
        .with_context(|| format!("invalid green channel in `{value}`"))?;
    let blue = u8::from_str_radix(&hex[4..6], 16)
        .with_context(|| format!("invalid blue channel in `{value}`"))?;

    Ok(Argb::new(255, red, green, blue))
}

pub(crate) fn tone_color(hue: f64, chroma: f64, tone: f64) -> Argb {
    let hct = Hct::from(normalize_hue(hue), chroma, tone.clamp(0.0, 100.0));
    Argb::from(hct)
}

fn normalize_hue(hue: f64) -> f64 {
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
