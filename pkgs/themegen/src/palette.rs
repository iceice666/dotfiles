use std::collections::BTreeMap;

use material_colors::color::Argb;
use material_colors::dynamic_color::DynamicScheme;
use material_colors::dynamic_color::variant::Variant;
use material_colors::hct::Hct;
use material_colors::scheme::Scheme;

use crate::color::{ensure_readable, interpolate, mix, tone_color};
use crate::model::Base16Palette;

pub(crate) fn scheme_to_map(scheme: Scheme) -> BTreeMap<String, String> {
    scheme
        .into_iter()
        .map(|(name, color)| (name, color.to_hex_with_pound()))
        .collect()
}

pub(crate) fn build_material_scheme(
    source: Argb,
    variant: Variant,
    is_dark: bool,
    contrast: f64,
) -> Scheme {
    let dynamic = DynamicScheme::by_variant(source, &variant, is_dark, Some(contrast));
    Scheme::from(dynamic)
}

pub(crate) fn build_base16(source: Argb, light: bool, contrast: f64) -> Base16Palette {
    let base = Hct::new(source);
    let hue = base.get_hue();
    let chroma = base.get_chroma().max(20.0);
    let text_low_ratio = contrast_target(2.0, contrast, 1.5, 3.5);
    let text_mid_ratio = contrast_target(4.0, contrast, 2.5, 7.0);
    let text_high_ratio = contrast_target(6.0, contrast, 3.5, 10.0);
    let text_max_ratio = contrast_target(8.0, contrast, 4.5, 12.0);
    let accent_ratio = contrast_target(3.0, contrast, 2.0, 5.5);

    let neutral_hue = hue;
    let neutral_chroma = (chroma * 0.12).clamp(4.0, 10.0);

    let (surface_tones, text_tones) = if light {
        ([98.0, 95.0, 90.0, 80.0], [36.0, 22.0, 14.0, 8.0])
    } else {
        ([10.0, 14.0, 20.0, 28.0], [60.0, 72.0, 84.0, 94.0])
    };

    let accents = [
        accent(hue + 8.0, chroma * 0.85, if light { 52.0 } else { 66.0 }),
        accent(hue + 32.0, chroma * 0.92, if light { 48.0 } else { 68.0 }),
        accent(hue + 78.0, chroma * 0.75, if light { 46.0 } else { 70.0 }),
        accent(hue + 138.0, chroma * 0.72, if light { 42.0 } else { 64.0 }),
        accent(hue, chroma, if light { 50.0 } else { 72.0 }),
        accent(hue + 292.0, chroma * 0.82, if light { 48.0 } else { 70.0 }),
        accent(hue + 18.0, chroma * 0.55, if light { 34.0 } else { 52.0 }),
    ];

    let base00 = tone_color(neutral_hue, neutral_chroma, surface_tones[0]);
    let base01 = tone_color(neutral_hue, neutral_chroma + 1.5, surface_tones[1]);
    let base02 = tone_color(neutral_hue, neutral_chroma + 2.5, surface_tones[2]);
    let base03 = tone_color(neutral_hue, neutral_chroma + 4.0, surface_tones[3]);
    let base04 = tone_color(neutral_hue, neutral_chroma + 2.0, text_tones[0]);
    let base05 = tone_color(neutral_hue, neutral_chroma + 1.0, text_tones[1]);
    let base06 = tone_color(neutral_hue, neutral_chroma, text_tones[2]);
    let base07 = tone_color(neutral_hue, neutral_chroma, text_tones[3]);

    Base16Palette {
        base00: base00.to_hex_with_pound(),
        base01: base01.to_hex_with_pound(),
        base02: base02.to_hex_with_pound(),
        base03: base03.to_hex_with_pound(),
        base04: ensure_readable(base04, base00, text_low_ratio).to_hex_with_pound(),
        base05: ensure_readable(base05, base00, text_mid_ratio).to_hex_with_pound(),
        base06: ensure_readable(base06, base00, text_high_ratio).to_hex_with_pound(),
        base07: ensure_readable(base07, base00, text_max_ratio).to_hex_with_pound(),
        base08: ensure_readable(accents[0], base00, accent_ratio).to_hex_with_pound(),
        base09: ensure_readable(accents[1], base00, accent_ratio).to_hex_with_pound(),
        base0_a: ensure_readable(accents[2], base00, accent_ratio).to_hex_with_pound(),
        base0_b: ensure_readable(accents[3], base00, accent_ratio).to_hex_with_pound(),
        base0_c: ensure_readable(accents[4], base00, accent_ratio).to_hex_with_pound(),
        base0_d: ensure_readable(accents[5], base00, accent_ratio).to_hex_with_pound(),
        base0_e: ensure_readable(accents[6], base00, accent_ratio).to_hex_with_pound(),
        base0_f: ensure_readable(mix(accents[0], accents[1], 0.5), base00, accent_ratio)
            .to_hex_with_pound(),
    }
}

fn contrast_target(standard: f64, contrast: f64, minimum: f64, maximum: f64) -> f64 {
    if contrast < 0.0 {
        interpolate(standard, minimum, -contrast)
    } else {
        interpolate(standard, maximum, contrast)
    }
}

fn accent(hue: f64, chroma: f64, tone: f64) -> Argb {
    tone_color(hue, chroma.clamp(18.0, 84.0), tone)
}
