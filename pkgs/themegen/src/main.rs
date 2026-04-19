mod cli;
mod color;
mod model;
mod palette;
mod source;
mod template;

use std::collections::BTreeSet;
use std::fmt::Write as _;
use std::fs;
use std::io::{self, IsTerminal};
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use clap::Parser;

use crate::cli::{
    Cli, Command, CommonOptions, PaletteCommand, PaletteFormat, RenderCommand, RenderConfig,
    RenderTarget,
};
use crate::color::{parse_hex_value, rgba_to_argb};
use crate::model::{
    Base16Palette, Base16Schemes, InputInfo, PaletteOutput, SeedInfo, SyntaxPalette, SyntaxSchemes,
    ThemeSchemes,
};
use crate::palette::{build_base16, build_material_scheme, build_syntax, scheme_to_map};
use crate::source::extract_source_color;
use crate::template::{render_template, template_values};

const NAME_COLUMN_WIDTH: usize = 26;
const COLOR_COLUMN_WIDTH: usize = 7;
const COLUMN_GAP: usize = 2;
const SWATCH_GAP: usize = 2;
const SWATCH_WIDTH: usize = 8;

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Palette(command) => handle_palette(command),
        Command::Render(command) => handle_render(command),
    }
}

fn handle_palette(command: PaletteCommand) -> Result<()> {
    let output = build_palette_output(&command.common)?;

    match command.format {
        PaletteFormat::Json => {
            serde_json::to_writer_pretty(io::stdout(), &output).context("failed to write JSON")?;
            println!();
        }
        PaletteFormat::Text => {
            print!("{}", render_palette_text(&output)?);
        }
    }

    Ok(())
}

fn handle_render(command: RenderCommand) -> Result<()> {
    let output = build_palette_output(&command.common)?;
    let jobs = prepare_render_jobs(load_render_targets(&command)?)?;
    let values = template_values(&output);

    for job in jobs {
        let rendered = render_template(&job.template, &values).with_context(|| {
            format!("failed to render template {}", job.template_path.display())
        })?;

        if let Some(parent) = job.output.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }

        fs::write(&job.output, rendered)
            .with_context(|| format!("failed to write {}", job.output.display()))?;
    }

    Ok(())
}

fn build_palette_output(common: &CommonOptions) -> Result<PaletteOutput> {
    let resolved = resolve_input(common)?;
    let material_light = scheme_to_map(build_material_scheme(
        resolved.seed,
        common.scheme.variant(),
        false,
        common.material_contrast,
    ));
    let material_dark = scheme_to_map(build_material_scheme(
        resolved.seed,
        common.scheme.variant(),
        true,
        common.material_contrast,
    ));
    let primary = material_light
        .get("primary")
        .context("generated material scheme is missing `primary`")
        .and_then(|color| parse_hex_value(color))
        .map(rgba_to_argb)?;
    let syntax_light = build_syntax(resolved.seed, &material_light, true, common.base16_contrast)?;
    let syntax_dark = build_syntax(resolved.seed, &material_dark, false, common.base16_contrast)?;
    let base16_light = build_base16(
        resolved.seed,
        primary,
        &material_light,
        &syntax_light,
        true,
        common.base16_contrast,
        common.base16_mode,
    )?;
    let base16_dark = build_base16(
        resolved.seed,
        primary,
        &material_dark,
        &syntax_dark,
        false,
        common.base16_contrast,
        common.base16_mode,
    )?;

    Ok(PaletteOutput {
        input: resolved.info,
        scheme: common.scheme.label().to_string(),
        seed: SeedInfo {
            color: resolved.seed.to_hex_with_pound(),
        },
        color: ThemeSchemes {
            light: material_light,
            dark: material_dark,
        },
        base16: Base16Schemes {
            light: base16_light,
            dark: base16_dark,
        },
        syntax: SyntaxSchemes {
            light: syntax_light,
            dark: syntax_dark,
        },
    })
}

fn load_render_targets(command: &RenderCommand) -> Result<Vec<RenderTarget>> {
    if let Some(config_path) = &command.config {
        load_render_config(config_path)
    } else {
        Ok(command.render.clone())
    }
}

fn load_render_config(config_path: &Path) -> Result<Vec<RenderTarget>> {
    let raw = fs::read_to_string(config_path)
        .with_context(|| format!("failed to read render config {}", config_path.display()))?;
    let config: RenderConfig = serde_json::from_str(&raw)
        .with_context(|| format!("failed to parse render config {}", config_path.display()))?;
    let base_dir = config_path.parent().unwrap_or_else(|| Path::new("."));

    Ok(config
        .renders
        .into_iter()
        .map(|target| RenderTarget {
            template: resolve_config_path(base_dir, target.template),
            output: resolve_config_path(base_dir, target.output),
        })
        .collect())
}

fn resolve_config_path(base_dir: &Path, path: PathBuf) -> PathBuf {
    if path.is_absolute() {
        path
    } else {
        base_dir.join(path)
    }
}

fn prepare_render_jobs(targets: Vec<RenderTarget>) -> Result<Vec<RenderJob>> {
    if targets.is_empty() {
        bail!("render requires at least one target");
    }

    let mut outputs = BTreeSet::new();
    let mut jobs = Vec::with_capacity(targets.len());

    for target in targets {
        if !outputs.insert(target.output.clone()) {
            bail!("duplicate render output `{}`", target.output.display());
        }

        let template = fs::read_to_string(&target.template)
            .with_context(|| format!("failed to read template {}", target.template.display()))?;

        jobs.push(RenderJob {
            template_path: target.template,
            output: target.output,
            template,
        });
    }

    Ok(jobs)
}

fn render_palette_text(output: &PaletteOutput) -> Result<String> {
    render_palette_text_with_swatches(output, io::stdout().is_terminal())
}

fn render_palette_text_with_swatches(output: &PaletteOutput, swatches: bool) -> Result<String> {
    let mut rendered = String::new();

    writeln!(&mut rendered, "themegen palette").unwrap();
    writeln!(
        &mut rendered,
        "input.kind                 {}",
        output.input.kind
    )
    .unwrap();
    writeln!(
        &mut rendered,
        "input.value                {}",
        output.input.value
    )
    .unwrap();
    writeln!(
        &mut rendered,
        "scheme                     {}",
        output.scheme
    )
    .unwrap();
    write_color_line(&mut rendered, "seed.color", &output.seed.color, swatches)?;
    rendered.push('\n');

    write_map_section(
        &mut rendered,
        "color",
        &output.color.light,
        &output.color.dark,
        swatches,
    )?;
    rendered.push('\n');
    write_base16_section(
        &mut rendered,
        "base16",
        &output.base16.light,
        &output.base16.dark,
        swatches,
    )?;
    rendered.push('\n');
    write_syntax_section(
        &mut rendered,
        "syntax",
        &output.syntax.light,
        &output.syntax.dark,
        swatches,
    )?;

    Ok(rendered)
}

fn write_map_section(
    rendered: &mut String,
    title: &str,
    light_palette: &std::collections::BTreeMap<String, String>,
    dark_palette: &std::collections::BTreeMap<String, String>,
    swatches: bool,
) -> Result<()> {
    write_section_header(rendered, title, swatches);

    for (name, light_color) in light_palette {
        let dark_color = dark_palette.get(name).with_context(|| {
            format!("generated {title} scheme is missing `{name}` in dark palette")
        })?;
        write_paired_color_line(rendered, name, light_color, dark_color, swatches)?;
    }

    Ok(())
}

fn write_base16_section(
    rendered: &mut String,
    title: &str,
    light_palette: &Base16Palette,
    dark_palette: &Base16Palette,
    swatches: bool,
) -> Result<()> {
    write_section_header(rendered, title, swatches);

    let light_entries = base16_entries(light_palette);
    let dark_entries = base16_entries(dark_palette);

    for ((name, light_color), (_, dark_color)) in light_entries.into_iter().zip(dark_entries) {
        write_paired_color_line(rendered, name, light_color, dark_color, swatches)?;
    }

    Ok(())
}

fn write_syntax_section(
    rendered: &mut String,
    title: &str,
    light_palette: &SyntaxPalette,
    dark_palette: &SyntaxPalette,
    swatches: bool,
) -> Result<()> {
    write_section_header(rendered, title, swatches);

    for ((name, light_color), (_, dark_color)) in syntax_entries(light_palette)
        .into_iter()
        .zip(syntax_entries(dark_palette))
    {
        write_paired_color_line(rendered, name, light_color, dark_color, swatches)?;
    }

    Ok(())
}

fn write_color_line(rendered: &mut String, name: &str, color: &str, swatches: bool) -> Result<()> {
    let color_cell = render_color_cell(color, swatches)?;

    writeln!(rendered, "{name:<NAME_COLUMN_WIDTH$} {color_cell}").unwrap();

    Ok(())
}

fn write_section_header(rendered: &mut String, title: &str, swatches: bool) {
    let title_header = format!("[{title}]");
    let light_gap = color_cell_width(swatches) + COLUMN_GAP - COLOR_COLUMN_WIDTH;

    writeln!(
        rendered,
        "{title_header:<NAME_COLUMN_WIDTH$} [light]{}[dark]",
        " ".repeat(light_gap),
    )
    .unwrap();
}

fn write_paired_color_line(
    rendered: &mut String,
    name: &str,
    light_color: &str,
    dark_color: &str,
    swatches: bool,
) -> Result<()> {
    let light_cell = render_color_cell(light_color, swatches)?;
    let dark_cell = render_color_cell(dark_color, swatches)?;

    writeln!(
        rendered,
        "{name:<NAME_COLUMN_WIDTH$} {light_cell}{}{dark_cell}",
        " ".repeat(COLUMN_GAP),
    )
    .unwrap();

    Ok(())
}

fn render_color_cell(color: &str, swatches: bool) -> Result<String> {
    if swatches {
        Ok(format!(
            "{color}{}{}",
            " ".repeat(SWATCH_GAP),
            render_swatch(color)?,
        ))
    } else {
        Ok(color.to_string())
    }
}

fn color_cell_width(swatches: bool) -> usize {
    COLOR_COLUMN_WIDTH
        + if swatches {
            SWATCH_GAP + SWATCH_WIDTH
        } else {
            0
        }
}

fn render_swatch(color: &str) -> Result<String> {
    let rgba = parse_hex_value(color)?;

    Ok(format!(
        "\x1b[48;2;{};{};{}m        \x1b[0m",
        rgba.red, rgba.green, rgba.blue
    ))
}

fn base16_entries(palette: &Base16Palette) -> [(&'static str, &str); 16] {
    [
        ("base00", palette.base00.as_str()),
        ("base01", palette.base01.as_str()),
        ("base02", palette.base02.as_str()),
        ("base03", palette.base03.as_str()),
        ("base04", palette.base04.as_str()),
        ("base05", palette.base05.as_str()),
        ("base06", palette.base06.as_str()),
        ("base07", palette.base07.as_str()),
        ("base08", palette.base08.as_str()),
        ("base09", palette.base09.as_str()),
        ("base0A", palette.base0_a.as_str()),
        ("base0B", palette.base0_b.as_str()),
        ("base0C", palette.base0_c.as_str()),
        ("base0D", palette.base0_d.as_str()),
        ("base0E", palette.base0_e.as_str()),
        ("base0F", palette.base0_f.as_str()),
    ]
}

fn syntax_entries(palette: &SyntaxPalette) -> [(&'static str, &str); 17] {
    [
        ("boolean", palette.boolean.as_str()),
        ("comment", palette.comment.as_str()),
        ("emphasis", palette.emphasis.as_str()),
        ("function", palette.function.as_str()),
        ("keyword", palette.keyword.as_str()),
        ("link", palette.link.as_str()),
        ("literal", palette.literal.as_str()),
        ("number", palette.number.as_str()),
        ("operator", palette.operator.as_str()),
        ("predictive", palette.predictive.as_str()),
        ("punctuation", palette.punctuation.as_str()),
        ("string", palette.string.as_str()),
        ("stringRegex", palette.string_regex.as_str()),
        ("stringSpecial", palette.string_special.as_str()),
        ("title", palette.title.as_str()),
        ("type", palette.type_name.as_str()),
        ("variable", palette.variable.as_str()),
    ]
}

fn resolve_input(common: &CommonOptions) -> Result<ResolvedInput> {
    match (&common.image, &common.source) {
        (Some(image), None) => {
            let image_data = image::open(image)
                .with_context(|| format!("failed to read image {}", image.display()))?;

            Ok(ResolvedInput {
                info: InputInfo {
                    kind: "image".to_string(),
                    value: image.display().to_string(),
                },
                seed: extract_source_color(&image_data)?,
            })
        }
        (None, Some(source)) => Ok(ResolvedInput {
            info: InputInfo {
                kind: "source".to_string(),
                value: source.clone(),
            },
            seed: parse_hex_value(source)
                .context("failed to parse source color")
                .map(rgba_to_argb)?,
        }),
        _ => unreachable!("clap enforces exactly one input"),
    }
}

struct ResolvedInput {
    info: InputInfo,
    seed: material_colors::color::Argb,
}

struct RenderJob {
    template_path: PathBuf,
    output: PathBuf,
    template: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::collections::BTreeMap;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn resolves_relative_render_config_paths() {
        let root = std::env::temp_dir().join(format!(
            "themegen-test-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let config_path = root.join("renders.json");

        fs::create_dir_all(&root).unwrap();
        fs::write(
            &config_path,
            r#"{
                "renders": [
                    { "template": "templates/ghostty", "output": "generated/ghostty-dark" }
                ]
            }"#,
        )
        .unwrap();

        let targets = load_render_config(&config_path).unwrap();

        assert_eq!(targets.len(), 1);
        assert_eq!(targets[0].template, root.join("templates/ghostty"));
        assert_eq!(targets[0].output, root.join("generated/ghostty-dark"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn renders_light_and_dark_palette_columns_side_by_side() {
        let output = PaletteOutput {
            input: InputInfo {
                kind: "source".to_string(),
                value: "#336699".to_string(),
            },
            scheme: "tonal-spot".to_string(),
            seed: SeedInfo {
                color: "#336699".to_string(),
            },
            color: ThemeSchemes {
                light: BTreeMap::from([
                    ("background".to_string(), "#f7f9fe".to_string()),
                    ("primary".to_string(), "#336699".to_string()),
                ]),
                dark: BTreeMap::from([
                    ("background".to_string(), "#101417".to_string()),
                    ("primary".to_string(), "#88aadd".to_string()),
                ]),
            },
            base16: Base16Schemes {
                light: Base16Palette {
                    base00: "#f7f9fe".to_string(),
                    base01: "#e8edf5".to_string(),
                    base02: "#d8deea".to_string(),
                    base03: "#a1adbf".to_string(),
                    base04: "#718099".to_string(),
                    base05: "#3a4456".to_string(),
                    base06: "#202733".to_string(),
                    base07: "#101417".to_string(),
                    base08: "#b34a4a".to_string(),
                    base09: "#c97733".to_string(),
                    base0_a: "#b68a1f".to_string(),
                    base0_b: "#4f8a3a".to_string(),
                    base0_c: "#2e8a8a".to_string(),
                    base0_d: "#336699".to_string(),
                    base0_e: "#7259b3".to_string(),
                    base0_f: "#944c7a".to_string(),
                },
                dark: Base16Palette {
                    base00: "#101417".to_string(),
                    base01: "#202733".to_string(),
                    base02: "#3a4456".to_string(),
                    base03: "#718099".to_string(),
                    base04: "#a1adbf".to_string(),
                    base05: "#d8deea".to_string(),
                    base06: "#e8edf5".to_string(),
                    base07: "#f7f9fe".to_string(),
                    base08: "#ff8f8f".to_string(),
                    base09: "#ffb366".to_string(),
                    base0_a: "#ffd166".to_string(),
                    base0_b: "#8fd47a".to_string(),
                    base0_c: "#73d9d9".to_string(),
                    base0_d: "#88aadd".to_string(),
                    base0_e: "#b9a1ff".to_string(),
                    base0_f: "#d98bc0".to_string(),
                },
            },
            syntax: SyntaxSchemes {
                light: SyntaxPalette {
                    boolean: "#8a6f16".to_string(),
                    comment: "#5d6f71".to_string(),
                    emphasis: "#8a4f8b".to_string(),
                    function: "#336699".to_string(),
                    keyword: "#8c4aa2".to_string(),
                    link: "#256c9b".to_string(),
                    literal: "#9a6c00".to_string(),
                    number: "#9a6c00".to_string(),
                    operator: "#3a4456".to_string(),
                    predictive: "#71809980".to_string(),
                    punctuation: "#718099".to_string(),
                    string: "#3f7c4c".to_string(),
                    string_regex: "#007f8d".to_string(),
                    string_special: "#00816d".to_string(),
                    title: "#9a5a2e".to_string(),
                    type_name: "#7259b3".to_string(),
                    variable: "#a15555".to_string(),
                },
                dark: SyntaxPalette {
                    boolean: "#ffd166".to_string(),
                    comment: "#86a2a5".to_string(),
                    emphasis: "#f0a7f0".to_string(),
                    function: "#88aadd".to_string(),
                    keyword: "#f0a3ff".to_string(),
                    link: "#82d3ff".to_string(),
                    literal: "#ffd166".to_string(),
                    number: "#ffd166".to_string(),
                    operator: "#d8deea".to_string(),
                    predictive: "#a1adbf80".to_string(),
                    punctuation: "#a1adbf".to_string(),
                    string: "#8fd47a".to_string(),
                    string_regex: "#73d9d9".to_string(),
                    string_special: "#77dec0".to_string(),
                    title: "#ffb366".to_string(),
                    type_name: "#b9a1ff".to_string(),
                    variable: "#ff9d9d".to_string(),
                },
            },
        };

        let rendered = render_palette_text_with_swatches(&output, false).unwrap();

        assert!(rendered.contains("[color]                    [light]  [dark]"));
        assert!(rendered.contains("background                 #f7f9fe  #101417"));
        assert!(rendered.contains("primary                    #336699  #88aadd"));
        assert!(rendered.contains("[base16]                   [light]  [dark]"));
        assert!(rendered.contains("[syntax]                   [light]  [dark]"));
        assert!(!rendered.contains("[color.light]"));
        assert!(!rendered.contains("[color.dark]"));
        assert!(!rendered.contains("[base16.light]"));
        assert!(!rendered.contains("[base16.dark]"));
        assert!(!rendered.contains("[syntax.light]"));
        assert!(!rendered.contains("[syntax.dark]"));
    }
}
