use std::path::PathBuf;

use clap::{ArgGroup, Args, Parser, Subcommand, ValueEnum};
use material_colors::dynamic_color::variant::Variant;
use serde::Deserialize;

use crate::color::parse_hex_value;

#[derive(Parser, Debug)]
#[command(name = "themegen")]
#[command(about = "Generate Material You and Base16 palettes from an image or source color")]
pub(crate) struct Cli {
    #[command(subcommand)]
    pub(crate) command: Command,
}

#[derive(Debug, Subcommand)]
pub(crate) enum Command {
    #[command(about = "Print the generated palette")]
    Palette(PaletteCommand),
    #[command(about = "Render one or more templates to files")]
    Render(RenderCommand),
}

#[derive(Debug, Args)]
#[command(group(ArgGroup::new("input").required(true).args(["image", "source"]))) ]
pub(crate) struct CommonOptions {
    #[arg(long, group = "input", value_name = "PATH")]
    pub(crate) image: Option<PathBuf>,

    #[arg(long, group = "input", value_name = "HEX", value_parser = parse_source_color)]
    pub(crate) source: Option<String>,

    #[arg(long, value_enum, default_value_t = SchemeType::TonalSpot)]
    pub(crate) scheme: SchemeType,

    #[arg(long, default_value_t = 0.0, value_parser = parse_contrast)]
    pub(crate) material_contrast: f64,

    #[arg(long, default_value_t = 0.0, value_parser = parse_contrast)]
    pub(crate) base16_contrast: f64,

    #[arg(long, value_enum, default_value_t = Base16Mode::SourceOffsets)]
    pub(crate) base16_mode: Base16Mode,
}

#[derive(Debug, Args)]
pub(crate) struct PaletteCommand {
    #[command(flatten)]
    pub(crate) common: CommonOptions,

    #[arg(long, value_enum, default_value_t = PaletteFormat::Text)]
    pub(crate) format: PaletteFormat,
}

#[derive(Debug, Args)]
#[command(group(ArgGroup::new("render_source").required(true).args(["render", "config"]))) ]
pub(crate) struct RenderCommand {
    #[command(flatten)]
    pub(crate) common: CommonOptions,

    #[arg(long, value_name = "TEMPLATE=OUTPUT", value_parser = parse_render_target)]
    pub(crate) render: Vec<RenderTarget>,

    #[arg(long, value_name = "PATH")]
    pub(crate) config: Option<PathBuf>,
}

fn parse_source_color(value: &str) -> Result<String, String> {
    let color = parse_hex_value(value).map_err(|error| error.to_string())?;

    if color.alpha != 255 {
        return Err(format!(
            "source color must be opaque RRGGBB or #RRGGBB, got `{value}`"
        ));
    }

    Ok(format!(
        "#{:02x}{:02x}{:02x}",
        color.red, color.green, color.blue
    ))
}

pub(crate) fn parse_contrast(value: &str) -> Result<f64, String> {
    let contrast = value
        .parse::<f64>()
        .map_err(|_| format!("invalid contrast value `{value}`"))?;

    if (-1.0..=1.0).contains(&contrast) {
        Ok(contrast)
    } else {
        Err(format!("contrast must be between -1 and 1, got {contrast}"))
    }
}

fn parse_render_target(value: &str) -> Result<RenderTarget, String> {
    let (template, output) = value
        .split_once('=')
        .ok_or_else(|| format!("render target must be TEMPLATE=OUTPUT, got `{value}`"))?;

    if template.is_empty() || output.is_empty() {
        return Err(format!(
            "render target must include both template and output paths, got `{value}`"
        ));
    }

    Ok(RenderTarget {
        template: PathBuf::from(template),
        output: PathBuf::from(output),
    })
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub(crate) enum SchemeType {
    #[value(name = "content")]
    Content,
    #[value(name = "expressive")]
    Expressive,
    #[value(name = "fidelity")]
    Fidelity,
    #[value(name = "fruit-salad")]
    FruitSalad,
    #[value(name = "monochrome")]
    Monochrome,
    #[value(name = "neutral")]
    Neutral,
    #[value(name = "rainbow")]
    Rainbow,
    #[value(name = "tonal-spot")]
    TonalSpot,
    #[value(name = "vibrant")]
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
            Self::Content => "content",
            Self::Expressive => "expressive",
            Self::Fidelity => "fidelity",
            Self::FruitSalad => "fruit-salad",
            Self::Monochrome => "monochrome",
            Self::Neutral => "neutral",
            Self::Rainbow => "rainbow",
            Self::TonalSpot => "tonal-spot",
            Self::Vibrant => "vibrant",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub(crate) enum Base16Mode {
    #[value(name = "source-offsets")]
    SourceOffsets,
    #[value(name = "follow-palette")]
    FollowPalette,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub(crate) enum PaletteFormat {
    #[value(name = "text")]
    Text,
    #[value(name = "json")]
    Json,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq)]
#[serde(deny_unknown_fields)]
pub(crate) struct RenderTarget {
    pub(crate) template: PathBuf,
    pub(crate) output: PathBuf,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct RenderConfig {
    pub(crate) renders: Vec<RenderTarget>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_palette_image_input() {
        let cli = Cli::try_parse_from(["themegen", "palette", "--image", "wallpaper.png"]).unwrap();

        let Command::Palette(command) = cli.command else {
            panic!("expected palette command");
        };

        assert_eq!(command.common.image, Some(PathBuf::from("wallpaper.png")));
        assert_eq!(command.common.source, None);
        assert_eq!(command.common.scheme, SchemeType::TonalSpot);
        assert_eq!(command.format, PaletteFormat::Text);
    }

    #[test]
    fn parses_source_input_and_scheme() {
        let cli = Cli::try_parse_from([
            "themegen",
            "palette",
            "--source",
            "336699",
            "--scheme",
            "expressive",
        ])
        .unwrap();

        let Command::Palette(command) = cli.command else {
            panic!("expected palette command");
        };

        assert_eq!(command.common.source.as_deref(), Some("#336699"));
        assert_eq!(command.common.scheme, SchemeType::Expressive);
    }

    #[test]
    fn parses_repeated_render_targets() {
        let cli = Cli::try_parse_from([
            "themegen",
            "render",
            "--image",
            "wallpaper.png",
            "--render",
            "ghostty=ghostty-dark",
            "--render",
            "zed=zed.json",
        ])
        .unwrap();

        let Command::Render(command) = cli.command else {
            panic!("expected render command");
        };

        assert_eq!(command.render.len(), 2);
        assert_eq!(command.render[0].template, PathBuf::from("ghostty"));
        assert_eq!(command.render[0].output, PathBuf::from("ghostty-dark"));
        assert_eq!(command.render[1].template, PathBuf::from("zed"));
        assert_eq!(command.render[1].output, PathBuf::from("zed.json"));
    }

    #[test]
    fn rejects_missing_render_source() {
        let error = Cli::try_parse_from(["themegen", "render", "--image", "wallpaper.png"])
            .unwrap_err()
            .to_string();

        assert!(error.contains("--render <TEMPLATE=OUTPUT>"));
        assert!(error.contains("--config <PATH>"));
    }

    #[test]
    fn rejects_removed_type_flag() {
        assert!(Cli::try_parse_from([
            "themegen",
            "palette",
            "--image",
            "wallpaper.png",
            "--type",
            "scheme-tonal-spot",
        ])
        .is_err());
    }

    #[test]
    fn rejects_removed_positional_image() {
        assert!(Cli::try_parse_from(["themegen", "palette", "wallpaper.png"]).is_err());
    }

    #[test]
    fn rejects_alpha_source_color() {
        let error = Cli::try_parse_from(["themegen", "palette", "--source", "33669980"])
            .unwrap_err()
            .to_string();

        assert!(error.contains("source color must be opaque"));
    }

    #[test]
    fn rejects_invalid_render_target() {
        let error = Cli::try_parse_from([
            "themegen",
            "render",
            "--image",
            "wallpaper.png",
            "--render",
            "ghostty",
        ])
        .unwrap_err()
        .to_string();

        assert!(error.contains("TEMPLATE=OUTPUT"));
    }

    #[test]
    fn parses_render_config_json_shape() {
        let config: RenderConfig = serde_json::from_str(
            r#"{
                "renders": [
                    { "template": "ghostty", "output": "ghostty-dark" },
                    { "template": "zed", "output": "zed.json" }
                ]
            }"#,
        )
        .unwrap();

        assert_eq!(config.renders.len(), 2);
        assert_eq!(config.renders[0].template, PathBuf::from("ghostty"));
        assert_eq!(config.renders[1].output, PathBuf::from("zed.json"));
    }
}
