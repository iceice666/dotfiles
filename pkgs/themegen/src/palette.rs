use std::collections::BTreeMap;

use anyhow::{Context, Result};
use apcach_rs::{
    apcach, cr_to_bg, max_chroma_capped, to_css, Color, ColorSpace, ContrastModel, CssFormat,
    SearchDirection,
};
use material_colors::color::Argb;
use material_colors::dynamic_color::variant::Variant;
use material_colors::dynamic_color::DynamicScheme;
use material_colors::hct::Hct;
use material_colors::scheme::Scheme;

use crate::cli::Base16Mode;
use crate::color::{ensure_readable, interpolate, normalize_hue, parse_hex_value, tone_color};
use crate::model::{Base16Palette, SyntaxPalette};

const FOLLOW_PALETTE_CHROMA_MULTIPLIERS: [f64; 8] = [0.85, 0.92, 0.75, 0.72, 1.0, 0.82, 0.72, 0.6];
const FOLLOW_PALETTE_LIGHT_TONES: [f64; 8] = [52.0, 48.0, 46.0, 42.0, 50.0, 48.0, 44.0, 38.0];
const FOLLOW_PALETTE_DARK_TONES: [f64; 8] = [66.0, 68.0, 70.0, 64.0, 72.0, 70.0, 68.0, 60.0];
const SEMANTIC_HUES: [f64; 8] = [0.0, 30.0, 60.0, 120.0, 180.0, 240.0, 300.0, 330.0];

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

pub(crate) fn build_syntax(
    source: Argb,
    palette: &BTreeMap<String, String>,
    _light: bool,
    contrast: f64,
) -> Result<SyntaxPalette> {
    let background = palette_color(palette, "surface_container_low")?;
    let on_surface = palette_color(palette, "on_surface")?.to_string();
    let on_surface_variant = palette_color(palette, "on_surface_variant")?.to_string();
    let neutral_hue = Hct::new(source).get_hue();

    Ok(SyntaxPalette {
        boolean: semantic_hex(background, 68.0, contrast, 72.0, 0.16)?,
        comment: semantic_hex(background, 42.0, contrast, 170.0, 0.05)?,
        emphasis: semantic_hex(background, 58.0, contrast, 320.0, 0.12)?,
        function: semantic_hex(background, 60.0, contrast, 250.0, 0.17)?,
        keyword: semantic_hex(background, 70.0, contrast, 315.0, 0.18)?,
        link: semantic_hex(background, 72.0, contrast, 220.0, 0.18)?,
        literal: semantic_hex(background, 70.0, contrast, 52.0, 0.18)?,
        number: semantic_hex(background, 68.0, contrast, 52.0, 0.17)?,
        operator: neutral_hex(background, 60.0, contrast, neutral_hue, 0.03, &on_surface)?,
        predictive: with_alpha(&on_surface_variant, 0x80)?,
        punctuation: neutral_hex(
            background,
            48.0,
            contrast,
            neutral_hue,
            0.02,
            &on_surface_variant,
        )?,
        string: semantic_hex(background, 68.0, contrast, 145.0, 0.18)?,
        string_regex: semantic_hex(background, 74.0, contrast, 195.0, 0.22)?,
        string_special: semantic_hex(background, 72.0, contrast, 176.0, 0.2)?,
        title: semantic_hex(background, 68.0, contrast, 18.0, 0.18)?,
        type_name: semantic_hex(background, 66.0, contrast, 285.0, 0.17)?,
        variable: semantic_hex(background, 60.0, contrast, 8.0, 0.16)?,
    })
}

pub(crate) fn build_base16(
    source: Argb,
    primary: Argb,
    palette: &BTreeMap<String, String>,
    syntax: &SyntaxPalette,
    light: bool,
    contrast: f64,
    mode: Base16Mode,
) -> Result<Base16Palette> {
    match mode {
        Base16Mode::SourceOffsets => Ok(build_legacy_base16(source, primary, light, contrast)),
        Base16Mode::FollowPalette => build_semantic_base16(source, palette, syntax, contrast),
    }
}

fn build_semantic_base16(
    source: Argb,
    palette: &BTreeMap<String, String>,
    syntax: &SyntaxPalette,
    contrast: f64,
) -> Result<Base16Palette> {
    let base00 = palette_color(palette, "surface_container_low")?.to_string();
    let base01 = palette_color(palette, "surface_container")?.to_string();
    let base02 = palette_color(palette, "surface_container_high")?.to_string();
    let base03 = palette_color(palette, "outline_variant")?.to_string();
    let neutral_hue = Hct::new(source).get_hue();
    let on_surface = palette_color(palette, "on_surface")?;

    Ok(Base16Palette {
        base00: base00.clone(),
        base01,
        base02,
        base03,
        base04: neutral_hex(&base00, 45.0, contrast, neutral_hue, 0.02, on_surface)?,
        base05: neutral_hex(&base00, 60.0, contrast, neutral_hue, 0.018, on_surface)?,
        base06: neutral_hex(&base00, 75.0, contrast, neutral_hue, 0.012, on_surface)?,
        base07: neutral_hex(&base00, 90.0, contrast, neutral_hue, 0.0, on_surface)?,
        base08: semantic_hex(&base00, 68.0, contrast, 25.0, 0.18)?,
        base09: syntax.title.clone(),
        base0_a: syntax.literal.clone(),
        base0_b: syntax.string.clone(),
        base0_c: syntax.link.clone(),
        base0_d: syntax.function.clone(),
        base0_e: syntax.keyword.clone(),
        base0_f: syntax.variable.clone(),
    })
}

fn semantic_hex(
    background: &str,
    target: f64,
    contrast: f64,
    hue: f64,
    cap: f64,
) -> Result<String> {
    let color = apcach(
        cr_to_bg(
            hex_to_apcach_color(background)?,
            apca_target(target, contrast),
            ContrastModel::Apca,
            SearchDirection::Auto,
        ),
        max_chroma_capped(cap),
        normalize_hue(hue),
        100.0,
        ColorSpace::Srgb,
    )
    .with_context(|| format!("failed to compose APCA color for hue {hue}"))?;

    to_css(color, CssFormat::Hex).context("failed to format APCA color as hex")
}

fn neutral_hex(
    background: &str,
    target: f64,
    contrast: f64,
    hue: f64,
    cap: f64,
    fallback: &str,
) -> Result<String> {
    semantic_hex(background, target, contrast, hue, cap).or_else(|_| Ok(fallback.to_string()))
}

fn palette_color<'a>(palette: &'a BTreeMap<String, String>, name: &str) -> Result<&'a str> {
    palette
        .get(name)
        .map(String::as_str)
        .with_context(|| format!("generated material scheme is missing `{name}`"))
}

fn hex_to_apcach_color(hex: &str) -> Result<Color> {
    let rgba = parse_hex_value(hex)?;
    Ok(Color::srgb(
        f64::from(rgba.red) / 255.0,
        f64::from(rgba.green) / 255.0,
        f64::from(rgba.blue) / 255.0,
    ))
}

fn with_alpha(hex: &str, alpha: u8) -> Result<String> {
    let rgba = parse_hex_value(hex)?;
    Ok(format!(
        "#{:02x}{:02x}{:02x}{alpha:02x}",
        rgba.red, rgba.green, rgba.blue
    ))
}

fn apca_target(standard: f64, contrast: f64) -> f64 {
    if contrast < 0.0 {
        interpolate(standard, (standard - 18.0).max(18.0), -contrast)
    } else {
        interpolate(standard, (standard + 18.0).min(96.0), contrast)
    }
}

fn build_legacy_base16(source: Argb, primary: Argb, light: bool, contrast: f64) -> Base16Palette {
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

    let accents = follow_palette_accents(Hct::new(primary).get_hue(), chroma, light);

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
    use super::{
        build_base16, build_syntax, hex_to_apcach_color, hue_distance, palette_color, SEMANTIC_HUES,
    };
    use crate::cli::Base16Mode;
    use crate::color::{parse_hex_value, rgba_to_argb, tone_color};
    use apcach_rs::{calc_contrast, ColorSpace, ContrastModel};
    use material_colors::color::Argb;
    use material_colors::hct::Hct;
    use std::collections::BTreeMap;

    fn test_palette(
        background: &str,
        on_surface: &str,
        on_surface_variant: &str,
    ) -> BTreeMap<String, String> {
        BTreeMap::from([
            ("surface_container_low".to_string(), background.to_string()),
            (
                "surface_container".to_string(),
                if background == "#11131a" {
                    "#171b22"
                } else {
                    "#eef1f8"
                }
                .to_string(),
            ),
            (
                "surface_container_high".to_string(),
                if background == "#11131a" {
                    "#20252d"
                } else {
                    "#e2e7ef"
                }
                .to_string(),
            ),
            (
                "outline_variant".to_string(),
                if background == "#11131a" {
                    "#444746"
                } else {
                    "#c1c6d0"
                }
                .to_string(),
            ),
            ("on_surface".to_string(), on_surface.to_string()),
            (
                "on_surface_variant".to_string(),
                on_surface_variant.to_string(),
            ),
        ])
    }

    #[test]
    fn follow_palette_aligns_named_slots_to_semantic_hues() {
        let palette = build_base16(
            tone_color(28.0, 48.0, 58.0),
            tone_color(310.0, 52.0, 62.0),
            &test_palette("#11131a", "#e2e2e9", "#c4c6d0"),
            &build_syntax(
                tone_color(28.0, 48.0, 58.0),
                &test_palette("#11131a", "#e2e2e9", "#c4c6d0"),
                false,
                0.0,
            )
            .unwrap(),
            false,
            0.0,
            Base16Mode::SourceOffsets,
        )
        .unwrap();

        assert!(hue_distance(color_hue(&palette.base08), SEMANTIC_HUES[0]) <= 12.0);
        assert!(hue_distance(color_hue(&palette.base0_b), SEMANTIC_HUES[3]) <= 20.0);
        assert!(hue_distance(color_hue(&palette.base0_d), SEMANTIC_HUES[5]) <= 24.0);
    }

    #[test]
    fn apca_syntax_stays_readable_on_dark_background() {
        let palette = test_palette("#11131a", "#e2e2e9", "#c4c6d0");
        let syntax = build_syntax(tone_color(200.0, 42.0, 50.0), &palette, false, 0.0).unwrap();
        let background =
            hex_to_apcach_color(palette_color(&palette, "surface_container_low").unwrap()).unwrap();

        for accent in [
            syntax.boolean,
            syntax.function,
            syntax.keyword,
            syntax.link,
            syntax.number,
            syntax.string,
            syntax.string_regex,
            syntax.type_name,
            syntax.variable,
        ] {
            let contrast = calc_contrast(
                hex_to_apcach_color(&accent).unwrap(),
                background,
                ContrastModel::Apca,
                ColorSpace::Srgb,
            )
            .unwrap();

            assert!(contrast >= 50.0, "{accent} had APCA contrast {contrast}");
        }
    }

    #[test]
    fn semantic_base16_uses_generated_semantic_roles() {
        let source = tone_color(200.0, 42.0, 50.0);
        let palette = test_palette("#11131a", "#e2e2e9", "#c4c6d0");
        let syntax = build_syntax(source, &palette, false, 0.0).unwrap();
        let base16 = build_base16(
            source,
            tone_color(18.0, 56.0, 64.0),
            &palette,
            &syntax,
            false,
            0.0,
            Base16Mode::FollowPalette,
        )
        .unwrap();

        assert_eq!(base16.base0_b, syntax.string);
        assert_eq!(base16.base0_d, syntax.function);
        assert_eq!(base16.base0_e, syntax.keyword);
    }

    fn color_hue(hex: &str) -> f64 {
        Hct::new(color_argb(hex)).get_hue()
    }

    fn color_argb(hex: &str) -> Argb {
        rgba_to_argb(parse_hex_value(hex).expect("valid generated hex color"))
    }
}
