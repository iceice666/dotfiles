use std::collections::BTreeMap;

use material_colors::color::Argb;
use material_colors::dynamic_color::variant::Variant;
use material_colors::dynamic_color::DynamicScheme;
use material_colors::hct::Hct;
use material_colors::scheme::Scheme;

use crate::cli::Base16Mode;
use crate::color::{ensure_readable, interpolate, mix, normalize_hue, tone_color};
use crate::model::Base16Palette;

const SEMANTIC_HUES: [f64; 8] = [0.0, 30.0, 60.0, 120.0, 180.0, 240.0, 300.0, 330.0];
const FOLLOW_PALETTE_CHROMA_MULTIPLIERS: [f64; 8] = [0.85, 0.92, 0.75, 0.72, 1.0, 0.82, 0.72, 0.6];
const FOLLOW_PALETTE_LIGHT_TONES: [f64; 8] = [52.0, 48.0, 46.0, 42.0, 50.0, 48.0, 44.0, 38.0];
const FOLLOW_PALETTE_DARK_TONES: [f64; 8] = [66.0, 68.0, 70.0, 64.0, 72.0, 70.0, 68.0, 60.0];

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

pub(crate) fn build_base16(
    source: Argb,
    primary: Argb,
    light: bool,
    contrast: f64,
    mode: Base16Mode,
) -> Base16Palette {
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

    let accents = build_accents(hue, Hct::new(primary).get_hue(), chroma, light, mode);

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
        base0_f: ensure_readable(accents[7], base00, accent_ratio).to_hex_with_pound(),
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

fn build_accents(
    source_hue: f64,
    primary_hue: f64,
    chroma: f64,
    light: bool,
    mode: Base16Mode,
) -> [Argb; 8] {
    match mode {
        Base16Mode::SourceOffsets => source_offset_accents(source_hue, chroma, light),
        Base16Mode::FollowPalette => follow_palette_accents(primary_hue, chroma, light),
    }
}

fn source_offset_accents(hue: f64, chroma: f64, light: bool) -> [Argb; 8] {
    let red = accent(hue + 8.0, chroma * 0.85, if light { 52.0 } else { 66.0 });
    let orange = accent(hue + 32.0, chroma * 0.92, if light { 48.0 } else { 68.0 });

    [
        red,
        orange,
        accent(hue + 78.0, chroma * 0.75, if light { 46.0 } else { 70.0 }),
        accent(hue + 138.0, chroma * 0.72, if light { 42.0 } else { 64.0 }),
        accent(hue, chroma, if light { 50.0 } else { 72.0 }),
        accent(hue + 292.0, chroma * 0.82, if light { 48.0 } else { 70.0 }),
        accent(hue + 18.0, chroma * 0.55, if light { 34.0 } else { 52.0 }),
        mix(red, orange, 0.5),
    ]
}

fn follow_palette_accents(primary_hue: f64, chroma: f64, light: bool) -> [Argb; 8] {
    let generated = std::array::from_fn(|index| normalize_hue(primary_hue + index as f64 * 45.0));
    let rotation = best_rotation(generated);
    let tones = if light {
        FOLLOW_PALETTE_LIGHT_TONES
    } else {
        FOLLOW_PALETTE_DARK_TONES
    };

    std::array::from_fn(|index| {
        let hue = generated[(index + rotation) % generated.len()];
        accent(
            hue,
            chroma * FOLLOW_PALETTE_CHROMA_MULTIPLIERS[index],
            tones[index],
        )
    })
}

fn best_rotation(hues: [f64; 8]) -> usize {
    (0..hues.len())
        .min_by(|left, right| rotation_score(hues, *left).total_cmp(&rotation_score(hues, *right)))
        .unwrap_or(0)
}

fn rotation_score(hues: [f64; 8], rotation: usize) -> f64 {
    SEMANTIC_HUES
        .iter()
        .enumerate()
        .map(|(index, semantic_hue)| {
            hue_distance(hues[(index + rotation) % hues.len()], *semantic_hue)
        })
        .sum()
}

fn hue_distance(left: f64, right: f64) -> f64 {
    let delta = (normalize_hue(left) - normalize_hue(right)).abs();
    delta.min(360.0 - delta)
}

#[cfg(test)]
mod tests {
    use super::{build_base16, hue_distance, SEMANTIC_HUES};
    use crate::cli::Base16Mode;
    use crate::color::{contrast_ratio, parse_hex_value, rgba_to_argb, tone_color};
    use material_colors::color::Argb;
    use material_colors::hct::Hct;

    #[test]
    fn follow_palette_aligns_named_slots_to_semantic_hues() {
        let palette = build_base16(
            tone_color(28.0, 48.0, 58.0),
            tone_color(310.0, 52.0, 62.0),
            false,
            0.0,
            Base16Mode::FollowPalette,
        );

        assert!(hue_distance(color_hue(&palette.base08), SEMANTIC_HUES[0]) <= 12.0);
        assert!(hue_distance(color_hue(&palette.base0_b), SEMANTIC_HUES[3]) <= 20.0);
        assert!(hue_distance(color_hue(&palette.base0_d), SEMANTIC_HUES[5]) <= 24.0);
    }

    #[test]
    fn follow_palette_keeps_anchor_hue_in_generated_slots() {
        let anchor_hue = 310.0;
        let palette = build_base16(
            tone_color(28.0, 48.0, 58.0),
            tone_color(anchor_hue, 52.0, 62.0),
            true,
            0.0,
            Base16Mode::FollowPalette,
        );

        let accent_hues = [
            color_hue(&palette.base08),
            color_hue(&palette.base09),
            color_hue(&palette.base0_a),
            color_hue(&palette.base0_b),
            color_hue(&palette.base0_c),
            color_hue(&palette.base0_d),
            color_hue(&palette.base0_e),
            color_hue(&palette.base0_f),
        ];

        assert!(accent_hues
            .into_iter()
            .any(|hue| hue_distance(hue, anchor_hue) <= 16.0));
    }

    #[test]
    fn follow_palette_accents_stay_readable() {
        let palette = build_base16(
            tone_color(200.0, 42.0, 50.0),
            tone_color(18.0, 56.0, 64.0),
            false,
            0.0,
            Base16Mode::FollowPalette,
        );
        let background = color_argb(&palette.base00);

        for accent in [
            &palette.base08,
            &palette.base09,
            &palette.base0_a,
            &palette.base0_b,
            &palette.base0_c,
            &palette.base0_d,
            &palette.base0_e,
            &palette.base0_f,
        ] {
            assert!(contrast_ratio(color_argb(accent), background) >= 3.0);
        }
    }

    fn color_hue(hex: &str) -> f64 {
        Hct::new(color_argb(hex)).get_hue()
    }

    fn color_argb(hex: &str) -> Argb {
        rgba_to_argb(parse_hex_value(hex).expect("valid generated hex color"))
    }
}
