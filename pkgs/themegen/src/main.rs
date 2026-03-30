use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::{Parser, ValueEnum};
use image::{DynamicImage, GenericImageView, imageops::FilterType};
use material_colors::color::{Argb, Lab};
use material_colors::dynamic_color::variant::Variant;
use material_colors::hct::Hct;
use material_colors::scheme::Scheme;
use material_colors::theme::ThemeBuilder;
use serde::Serialize;

#[derive(Parser, Debug)]
#[command(name = "themegen")]
#[command(about = "Generate Material You and Base16 palettes from an image")]
struct Cli {
    image: PathBuf,

    #[arg(long, value_enum, default_value_t = SchemeType::TonalSpot)]
    r#type: SchemeType,

    #[arg(long)]
    template: Option<PathBuf>,
}

#[derive(Clone, Copy, Debug, ValueEnum)]
enum SchemeType {
    #[value(name = "scheme-content")]
    Content,
    #[value(name = "scheme-expressive")]
    Expressive,
    #[value(name = "scheme-fidelity")]
    Fidelity,
    #[value(name = "scheme-fruit-salad")]
    FruitSalad,
    #[value(name = "scheme-monochrome")]
    Monochrome,
    #[value(name = "scheme-neutral")]
    Neutral,
    #[value(name = "scheme-rainbow")]
    Rainbow,
    #[value(name = "scheme-tonal-spot")]
    TonalSpot,
    #[value(name = "scheme-vibrant")]
    Vibrant,
}

impl SchemeType {
    fn variant(self) -> Variant {
        match self {
            Self::Content => Variant::Content,
            Self::Expressive => Variant::Expressive,
            Self::Fidelity => Variant::Fidelity,
            Self::FruitSalad => Variant::FruitSalad,
            Self::Monochrome => Variant::Monochrome,
            Self::Neutral => Variant::Neutral,
            Self::Rainbow => Variant::Rainbow,
            Self::TonalSpot => Variant::TonalSpot,
            Self::Vibrant => Variant::Vibrant,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Content => "scheme-content",
            Self::Expressive => "scheme-expressive",
            Self::Fidelity => "scheme-fidelity",
            Self::FruitSalad => "scheme-fruit-salad",
            Self::Monochrome => "scheme-monochrome",
            Self::Neutral => "scheme-neutral",
            Self::Rainbow => "scheme-rainbow",
            Self::TonalSpot => "scheme-tonal-spot",
            Self::Vibrant => "scheme-vibrant",
        }
    }
}

#[derive(Serialize)]
struct Output {
    source: SourceInfo,
    material: ThemeSchemes,
    base16: Base16Schemes,
}

#[derive(Serialize)]
struct SourceInfo {
    image: String,
    r#type: String,
    color: String,
}

#[derive(Serialize)]
struct ThemeSchemes {
    light: BTreeMap<String, String>,
    dark: BTreeMap<String, String>,
}

#[derive(Serialize)]
struct Base16Schemes {
    light: Base16Palette,
    dark: Base16Palette,
}

#[derive(Serialize)]
struct Base16Palette {
    scheme: String,
    author: String,
    base00: String,
    base01: String,
    base02: String,
    base03: String,
    base04: String,
    base05: String,
    base06: String,
    base07: String,
    base08: String,
    base09: String,
    #[serde(rename = "base0A")]
    base0_a: String,
    #[serde(rename = "base0B")]
    base0_b: String,
    #[serde(rename = "base0C")]
    base0_c: String,
    #[serde(rename = "base0D")]
    base0_d: String,
    #[serde(rename = "base0E")]
    base0_e: String,
    #[serde(rename = "base0F")]
    base0_f: String,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let image = image::open(&cli.image)
        .with_context(|| format!("failed to read image {}", cli.image.display()))?;

    let source = extract_source_color(&image)?;
    let theme = ThemeBuilder::with_source(source)
        .variant(cli.r#type.variant())
        .build();

    let material_light = scheme_to_map(theme.schemes.light);
    let material_dark = scheme_to_map(theme.schemes.dark);
    let base16_light = build_base16(source, true);
    let base16_dark = build_base16(source, false);

    if let Some(template_path) = cli.template {
        let template = fs::read_to_string(&template_path)
            .with_context(|| format!("failed to read template {}", template_path.display()))?;
        let values = template_values(
            &cli.image,
            cli.r#type,
            source,
            &material_light,
            &material_dark,
            &base16_light,
            &base16_dark,
        );

        print!("{}", render_template(&template, &values)?);
        return Ok(());
    }

    let output = Output {
        source: SourceInfo {
            image: cli.image.display().to_string(),
            r#type: cli.r#type.label().to_string(),
            color: source.to_hex_with_pound(),
        },
        material: ThemeSchemes {
            light: material_light,
            dark: material_dark,
        },
        base16: Base16Schemes {
            light: base16_light,
            dark: base16_dark,
        },
    };

    serde_json::to_writer_pretty(std::io::stdout(), &output).context("failed to write JSON")?;
    println!();

    Ok(())
}

fn template_values(
    image: &PathBuf,
    scheme_type: SchemeType,
    source: Argb,
    material_light: &BTreeMap<String, String>,
    material_dark: &BTreeMap<String, String>,
    base16_light: &Base16Palette,
    base16_dark: &Base16Palette,
) -> BTreeMap<String, String> {
    let mut values = BTreeMap::new();

    values.insert("source.image".to_string(), image.display().to_string());
    values.insert("source.type".to_string(), scheme_type.label().to_string());
    values.insert("source.color".to_string(), source.to_hex_with_pound());

    extend_prefixed(&mut values, "material.light", material_light);
    extend_prefixed(&mut values, "material.dark", material_dark);
    extend_prefixed(&mut values, "color.light", material_light);
    extend_prefixed(&mut values, "color.dark", material_dark);
    extend_base16(&mut values, "base16.light", base16_light);
    extend_base16(&mut values, "base16.dark", base16_dark);

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
    values.insert(format!("{prefix}.scheme"), palette.scheme.clone());
    values.insert(format!("{prefix}.author"), palette.author.clone());
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

fn render_template(template: &str, values: &BTreeMap<String, String>) -> Result<String> {
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
        let value = values
            .get(key)
            .with_context(|| format!("unknown template placeholder {{{{{raw_key}}}}}"))?;
        rendered.push_str(value);
        rest = &after_start[end + 2..];
    }

    rendered.push_str(rest);

    Ok(rendered)
}

fn extract_source_color(image: &DynamicImage) -> Result<Argb> {
    let resized = image.resize(256, 256, FilterType::Triangle);
    let rgba = resized.to_rgba8();
    let mut bins = BTreeMap::<u16, Bin>::new();

    for pixel in rgba.pixels() {
        let [r, g, b, a] = pixel.0;
        if a < 200 {
            continue;
        }

        let rgb = Argb::new(255, r, g, b);
        let hct = Hct::new(rgb);
        let chroma = hct.get_chroma();
        let tone = hct.get_tone();

        if chroma < 8.0 || !(8.0..=96.0).contains(&tone) {
            continue;
        }

        let key = quantize_key(hct.get_hue(), chroma, tone);
        bins.entry(key)
            .and_modify(|bin| bin.add(rgb, chroma, tone))
            .or_insert_with(|| Bin::new(rgb, chroma, tone));
    }

    let best = bins
        .into_values()
        .max_by(|left, right| left.score().total_cmp(&right.score()))
        .map(Bin::color)
        .unwrap_or_else(|| fallback_source_color(image));

    Ok(best)
}

fn fallback_source_color(image: &DynamicImage) -> Argb {
    let pixel = image.get_pixel(image.width() / 2, image.height() / 2).0;
    Argb::new(255, pixel[0], pixel[1], pixel[2])
}

fn quantize_key(hue: f64, chroma: f64, tone: f64) -> u16 {
    let hue_bucket = (hue / 12.0).round() as u16;
    let chroma_bucket = (chroma / 8.0).round() as u16;
    let tone_bucket = (tone / 8.0).round() as u16;

    (hue_bucket << 8) | (chroma_bucket << 4) | tone_bucket
}

#[derive(Clone, Copy)]
struct Bin {
    red: f64,
    green: f64,
    blue: f64,
    count: f64,
    chroma_sum: f64,
    tone_sum: f64,
}

impl Bin {
    fn new(color: Argb, chroma: f64, tone: f64) -> Self {
        Self {
            red: f64::from(color.red),
            green: f64::from(color.green),
            blue: f64::from(color.blue),
            count: 1.0,
            chroma_sum: chroma,
            tone_sum: tone,
        }
    }

    fn add(&mut self, color: Argb, chroma: f64, tone: f64) {
        self.red += f64::from(color.red);
        self.green += f64::from(color.green);
        self.blue += f64::from(color.blue);
        self.count += 1.0;
        self.chroma_sum += chroma;
        self.tone_sum += tone;
    }

    fn color(self) -> Argb {
        Argb::new(
            255,
            (self.red / self.count).round() as u8,
            (self.green / self.count).round() as u8,
            (self.blue / self.count).round() as u8,
        )
    }

    fn score(self) -> f64 {
        let chroma = self.chroma_sum / self.count;
        let tone = self.tone_sum / self.count;
        let tone_balance = 1.0 - ((tone - 55.0).abs() / 55.0).min(1.0);

        self.count.powf(1.15) * (1.0 + chroma / 48.0) * (0.5 + tone_balance)
    }
}

fn scheme_to_map(scheme: Scheme) -> BTreeMap<String, String> {
    scheme
        .into_iter()
        .map(|(name, color)| (name, color.to_hex_with_pound()))
        .collect()
}

fn build_base16(source: Argb, light: bool) -> Base16Palette {
    let base = Hct::new(source);
    let hue = base.get_hue();
    let chroma = base.get_chroma().max(20.0);

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

    let palette = Base16Palette {
        scheme: if light {
            "themegen-dank16-light".to_string()
        } else {
            "themegen-dank16-dark".to_string()
        },
        author: "OpenCode".to_string(),
        base00: base00.to_hex_with_pound(),
        base01: base01.to_hex_with_pound(),
        base02: base02.to_hex_with_pound(),
        base03: base03.to_hex_with_pound(),
        base04: ensure_readable(base04, base00, 2.0).to_hex_with_pound(),
        base05: ensure_readable(base05, base00, 4.0).to_hex_with_pound(),
        base06: ensure_readable(base06, base00, 6.0).to_hex_with_pound(),
        base07: ensure_readable(base07, base00, 8.0).to_hex_with_pound(),
        base08: ensure_readable(accents[0], base00, 3.0).to_hex_with_pound(),
        base09: ensure_readable(accents[1], base00, 3.0).to_hex_with_pound(),
        base0_a: ensure_readable(accents[2], base00, 3.0).to_hex_with_pound(),
        base0_b: ensure_readable(accents[3], base00, 3.0).to_hex_with_pound(),
        base0_c: ensure_readable(accents[4], base00, 3.0).to_hex_with_pound(),
        base0_d: ensure_readable(accents[5], base00, 3.0).to_hex_with_pound(),
        base0_e: ensure_readable(accents[6], base00, 3.0).to_hex_with_pound(),
        base0_f: ensure_readable(mix(accents[0], accents[1], 0.5), base00, 3.0).to_hex_with_pound(),
    };

    palette
}

fn accent(hue: f64, chroma: f64, tone: f64) -> Argb {
    tone_color(hue, chroma.clamp(18.0, 84.0), tone)
}

fn tone_color(hue: f64, chroma: f64, tone: f64) -> Argb {
    let hct = Hct::from(normalize_hue(hue), chroma, tone.clamp(0.0, 100.0));
    Argb::from(hct)
}

fn normalize_hue(hue: f64) -> f64 {
    hue.rem_euclid(360.0)
}

fn ensure_readable(color: Argb, background: Argb, minimum_ratio: f64) -> Argb {
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

fn contrast_ratio(foreground: Argb, background: Argb) -> f64 {
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

fn mix(left: Argb, right: Argb, amount: f64) -> Argb {
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

fn interpolate(left: f64, right: f64, amount: f64) -> f64 {
    left + (right - left) * amount
}
