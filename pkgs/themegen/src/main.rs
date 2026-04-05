mod cli;
mod color;
mod model;
mod palette;
mod source;
mod template;

use std::fs;

use anyhow::{Context, Result};
use clap::Parser;

use crate::cli::Cli;
use crate::color::{parse_hex_value, rgba_to_argb};
use crate::model::{Base16Schemes, Output, SourceInfo, ThemeSchemes};
use crate::palette::{build_base16, build_material_scheme, scheme_to_map};
use crate::source::extract_source_color;
use crate::template::{render_template, template_values};

fn main() -> Result<()> {
    let cli = Cli::parse();
    let image = image::open(&cli.image)
        .with_context(|| format!("failed to read image {}", cli.image.display()))?;

    let source = extract_source_color(&image)?;
    let material_light = scheme_to_map(build_material_scheme(
        source,
        cli.r#type.variant(),
        false,
        cli.material_contrast,
    ));
    let material_dark = scheme_to_map(build_material_scheme(
        source,
        cli.r#type.variant(),
        true,
        cli.material_contrast,
    ));
    let primary = material_light
        .get("primary")
        .context("generated material scheme is missing `primary`")
        .and_then(|color| parse_hex_value(color))
        .map(rgba_to_argb)?;
    let base16_light = build_base16(source, primary, true, cli.base16_contrast, cli.base16_mode);
    let base16_dark = build_base16(source, primary, false, cli.base16_contrast, cli.base16_mode);

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
