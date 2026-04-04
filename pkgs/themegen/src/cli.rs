use std::path::PathBuf;

use clap::{Parser, ValueEnum};
use material_colors::dynamic_color::variant::Variant;

#[derive(Parser, Debug)]
#[command(name = "themegen")]
#[command(about = "Generate Material You and Base16 palettes from an image")]
pub(crate) struct Cli {
    pub(crate) image: PathBuf,

    #[arg(long, value_enum, default_value_t = SchemeType::TonalSpot)]
    pub(crate) r#type: SchemeType,

    #[arg(long)]
    pub(crate) template: Option<PathBuf>,

    #[arg(long, default_value_t = 0.0, value_parser = parse_contrast)]
    pub(crate) material_contrast: f64,

    #[arg(long, default_value_t = 0.0, value_parser = parse_contrast)]
    pub(crate) base16_contrast: f64,
}

fn parse_contrast(value: &str) -> Result<f64, String> {
    let contrast = value
        .parse::<f64>()
        .map_err(|_| format!("invalid contrast value `{value}`"))?;

    if (-1.0..=1.0).contains(&contrast) {
        Ok(contrast)
    } else {
        Err(format!("contrast must be between -1 and 1, got {contrast}"))
    }
}

#[derive(Clone, Copy, Debug, ValueEnum)]
pub(crate) enum SchemeType {
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
    pub(crate) fn variant(self) -> Variant {
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

    pub(crate) fn label(self) -> &'static str {
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
