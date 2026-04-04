use std::collections::BTreeMap;
use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use material_colors::color::Argb;
use material_colors::hct::Hct;

use crate::cli::SchemeType;
use crate::color::{ensure_readable, mix, parse_hex_color, tone_color};
use crate::model::Base16Palette;

pub(crate) fn template_values(
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

pub(crate) fn render_template(template: &str, values: &BTreeMap<String, String>) -> Result<String> {
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
        let value = render_placeholder(key, values)
            .with_context(|| format!("failed to render template placeholder {{{{{raw_key}}}}}"))?;
        rendered.push_str(&value);
        rest = &after_start[end + 2..];
    }

    rendered.push_str(rest);

    Ok(rendered)
}

fn render_placeholder(placeholder: &str, values: &BTreeMap<String, String>) -> Result<String> {
    if !placeholder.contains('|') {
        return resolve_value(placeholder, values);
    }

    let mut steps = placeholder.split('|').map(str::trim);
    let base = steps.next().context("empty template expression")?;
    let mut color = resolve_color(base, values)?;

    for step in steps {
        color = apply_color_operation(color, step, values)?;
    }

    Ok(color.to_hex_with_pound())
}

fn resolve_value(name: &str, values: &BTreeMap<String, String>) -> Result<String> {
    values
        .get(name)
        .cloned()
        .with_context(|| format!("unknown template placeholder `{name}`"))
}

fn resolve_color(name: &str, values: &BTreeMap<String, String>) -> Result<Argb> {
    let value = values.get(name).map(String::as_str).unwrap_or(name);

    parse_hex_color(value).with_context(|| format!("`{name}` is not a color placeholder"))
}

fn apply_color_operation(
    color: Argb,
    operation: &str,
    values: &BTreeMap<String, String>,
) -> Result<Argb> {
    let (name, args) = parse_function_call(operation)?;

    match name {
        "rotate" => {
            let degrees = parse_number(single_arg(name, &args)?, "degrees")?;
            let hct = Hct::new(color);
            Ok(tone_color(
                hct.get_hue() + degrees,
                hct.get_chroma(),
                hct.get_tone(),
            ))
        }
        "chroma" => {
            let chroma = parse_number(single_arg(name, &args)?, "chroma")?.max(0.0);
            let hct = Hct::new(color);
            Ok(tone_color(hct.get_hue(), chroma, hct.get_tone()))
        }
        "chroma_add" => {
            let delta = parse_number(single_arg(name, &args)?, "delta")?;
            let hct = Hct::new(color);
            Ok(tone_color(
                hct.get_hue(),
                (hct.get_chroma() + delta).max(0.0),
                hct.get_tone(),
            ))
        }
        "tone" => {
            let tone = parse_number(single_arg(name, &args)?, "tone")?;
            let hct = Hct::new(color);
            Ok(tone_color(hct.get_hue(), hct.get_chroma(), tone))
        }
        "tone_add" => {
            let delta = parse_number(single_arg(name, &args)?, "delta")?;
            let hct = Hct::new(color);
            Ok(tone_color(
                hct.get_hue(),
                hct.get_chroma(),
                hct.get_tone() + delta,
            ))
        }
        "mix" => {
            if args.len() != 2 {
                bail!("`mix` expects 2 arguments, got {}", args.len());
            }

            let other = resolve_color(args[0], values)?;
            let amount = parse_number(args[1], "amount")?;
            Ok(mix(color, other, amount))
        }
        "readable" => {
            if args.len() != 2 {
                bail!("`readable` expects 2 arguments, got {}", args.len());
            }

            let background = resolve_color(args[0], values)?;
            let ratio = parse_number(args[1], "ratio")?;
            Ok(ensure_readable(color, background, ratio))
        }
        _ => bail!("unknown color operation `{name}`"),
    }
}

fn parse_function_call(operation: &str) -> Result<(&str, Vec<&str>)> {
    let open = operation
        .find('(')
        .with_context(|| format!("expected function call, got `{operation}`"))?;

    if !operation.ends_with(')') {
        bail!("expected closing `)` in `{operation}`");
    }

    let name = operation[..open].trim();
    if name.is_empty() {
        bail!("missing function name in `{operation}`");
    }

    let args = operation[open + 1..operation.len() - 1].trim();
    let parsed = if args.is_empty() {
        Vec::new()
    } else {
        args.split(',').map(str::trim).collect()
    };

    Ok((name, parsed))
}

fn single_arg<'a>(name: &str, args: &'a [&'a str]) -> Result<&'a str> {
    if args.len() != 1 {
        bail!("`{name}` expects 1 argument, got {}", args.len());
    }

    Ok(args[0])
}

fn parse_number(value: &str, label: &str) -> Result<f64> {
    value
        .parse::<f64>()
        .with_context(|| format!("invalid {label} `{value}`"))
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::color::contrast_ratio;

    fn test_values() -> BTreeMap<String, String> {
        BTreeMap::from([
            ("source.color".to_string(), "#336699".to_string()),
            ("source.type".to_string(), "scheme-tonal-spot".to_string()),
            (
                "color.light.surface_container_low".to_string(),
                "#f8f9ff".to_string(),
            ),
            (
                "color.dark.surface_container_low".to_string(),
                "#11131a".to_string(),
            ),
            ("color.light.primary".to_string(), "#3f6aa1".to_string()),
            ("color.dark.primary".to_string(), "#aac7ff".to_string()),
        ])
    }

    #[test]
    fn renders_plain_placeholders_unchanged() {
        let rendered = render_template(
            "{{ color.light.primary }} {{ source.type }}",
            &test_values(),
        )
        .unwrap();

        assert_eq!(rendered, "#3f6aa1 scheme-tonal-spot");
    }

    #[test]
    fn applies_pipe_color_operations() {
        let values = test_values();
        let rendered = render_template(
            "{{ source.color | rotate(145) | chroma(40) | tone(34) }}",
            &values,
        )
        .unwrap();

        let source = resolve_color("source.color", &values).unwrap();
        let hct = Hct::new(source);
        let expected = tone_color(hct.get_hue() + 145.0, 40.0, 34.0).to_hex_with_pound();

        assert_eq!(rendered, expected);
    }

    #[test]
    fn mix_and_readable_keep_contrast() {
        let values = test_values();
        let rendered = render_template(
            "{{ source.color | mix(color.light.primary, 0.35) | tone(74) | readable(color.dark.surface_container_low, 4.5) }}",
            &values,
        )
        .unwrap();

        let foreground = parse_hex_color(&rendered).unwrap();
        let background = resolve_color("color.dark.surface_container_low", &values).unwrap();

        assert!(contrast_ratio(foreground, background) >= 4.5);
    }

    #[test]
    fn reports_invalid_operations() {
        let error = format!(
            "{:#}",
            render_template("{{ source.color | spin(45) }}", &test_values()).unwrap_err()
        );

        assert!(error.contains("unknown color operation `spin`"));
    }
}
