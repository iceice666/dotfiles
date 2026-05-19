use std::collections::BTreeMap;

use crate::color::{contrast_ratio, parse_hex_value, rgba_to_argb};

use super::render_template;

fn test_values() -> BTreeMap<String, String> {
    BTreeMap::from([
        ("input.kind".to_string(), "image".to_string()),
        ("input.value".to_string(), "/tmp/wallpaper.png".to_string()),
        ("scheme".to_string(), "tonal-spot".to_string()),
        (
            "color.light.surface_container_low".to_string(),
            "#f8f9ff".to_string(),
        ),
        (
            "color.dark.surface_container_low".to_string(),
            "#11131a".to_string(),
        ),
        (
            "color.light.secondary_container".to_string(),
            "#d6e3ff".to_string(),
        ),
        (
            "color.dark.secondary_container".to_string(),
            "#334865".to_string(),
        ),
        ("color.light.primary".to_string(), "#3f6aa1".to_string()),
        ("color.dark.primary".to_string(), "#aac7ff".to_string()),
        (
            "color.dark.outline_variant".to_string(),
            "#444746".to_string(),
        ),
        ("seed.color".to_string(), "#336699".to_string()),
        ("syntax.dark.keyword".to_string(), "#f0a3ff".to_string()),
    ])
}

#[test]
fn renders_plain_placeholders_unchanged() {
    let rendered = render_template("{{ color.light.primary }} {{ scheme }}", &test_values()).unwrap();

    assert_eq!(rendered, "#3f6aa1 tonal-spot");
}

#[test]
fn renders_header_aliases_and_strips_header() {
    let rendered = render_template(
        "{{#themegen\nlet local.primary_40 = alpha(color.dark.primary, 0x40, hex)\n}}\nvalue {{local.primary_40}}",
        &test_values(),
    )
    .unwrap();

    assert_eq!(rendered, "value #aac7ff40");
}

#[test]
fn supports_header_comments_and_alias_copies() {
    let rendered = render_template(
        "{{#themegen\n# comment\nlet local.primary = color.light.primary\n}}\n{{local.primary}}",
        &test_values(),
    )
    .unwrap();

    assert_eq!(rendered, "#3f6aa1");
}

#[test]
fn alpha_accepts_percentages() {
    let rendered = render_template(
        "{{#themegen\nlet local.outline = alpha(color.dark.outline_variant, 25%, hex)\n}}\n{{local.outline}}",
        &test_values(),
    )
    .unwrap();

    assert_eq!(rendered, "#44474640");
}

#[test]
fn alpha_can_render_raw_hex_and_rgba() {
    let rendered = render_template(
        "{{#themegen\nlet local.raw = alpha(color.dark.outline_variant, 25%, raw)\nlet local.rgba = alpha(color.dark.outline_variant, 25%, rgba)\n}}\n{{local.raw}} {{local.rgba}}",
        &test_values(),
    )
    .unwrap();

    assert_eq!(rendered, "44474640 rgba(68, 71, 70, 0.251)");
}

#[test]
fn hct_mix_matches_expected_output_shape() {
    let rendered = render_template(
        "{{#themegen\nlet local.mixed = mix(color.light.surface_container_low, seed.color, 0.08, hct, hex)\n}}\n{{local.mixed}}",
        &test_values(),
    )
    .unwrap();

    assert!(rendered.starts_with('#'));
}

#[test]
fn oklch_lightness_add_renders_hex() {
    let rendered = render_template(
        "{{#themegen\nlet local.light = lightness_add(color.dark.primary, 0.09, oklch, hex)\n}}\n{{local.light}}",
        &test_values(),
    )
    .unwrap();

    assert!(rendered.starts_with('#'));
}

#[test]
fn tone_and_readable_keep_contrast() {
    let values = test_values();
    let rendered = render_template(
        "{{#themegen\nlet local.readable = tone_readable(color.dark.primary, 74, color.dark.surface_container_low, 4.5, hct, hex)\n}}\n{{local.readable}}",
        &values,
    )
    .unwrap();

    let foreground = rgba_to_argb(parse_hex_value(&rendered).unwrap());
    let background = rgba_to_argb(
        parse_hex_value(values.get("color.dark.surface_container_low").unwrap()).unwrap(),
    );

    assert!(contrast_ratio(foreground, background) >= 4.5);
}

#[test]
fn readable_alpha_renders_raw_hex() {
    let rendered = render_template(
        "{{#themegen\nlet local.match = readable_alpha(color.light.primary, color.light.secondary_container, 4.5, 100%, hct, raw)\n}}\n{{local.match}}",
        &test_values(),
    )
    .unwrap();

    assert_eq!(rendered.len(), 8);
}

#[test]
fn rejects_empty_placeholders() {
    let error = format!("{:#}", render_template("a{{ }}b", &test_values()).unwrap_err());

    assert!(error.contains("empty template placeholder"));
}

#[test]
fn rejects_old_pipe_syntax_in_body() {
    let error = format!(
        "{:#}",
        render_template(
            "{{ color.dark.primary | with_alpha(0x40, hex) }}",
            &test_values()
        )
        .unwrap_err()
    );

    assert!(error.contains("direct lookups"));
}

#[test]
fn rejects_unknown_placeholders() {
    let error = format!(
        "{:#}",
        render_template("{{ color.dark.missing }}", &test_values()).unwrap_err()
    );

    assert!(error.contains("unknown template placeholder `color.dark.missing`"));
}

#[test]
fn rejects_alias_shadowing() {
    let error = format!(
        "{:#}",
        render_template(
            "{{#themegen\nlet color.dark.primary = alpha(color.dark.primary, 0x40, hex)\n}}\n",
            &test_values()
        )
        .unwrap_err()
    );

    assert!(error.contains("must start with `local.`"));
}

#[test]
fn rejects_bare_alpha_values() {
    let error = format!(
        "{:#}",
        render_template(
            "{{#themegen\nlet local.bad = alpha(color.dark.primary, 80, hex)\n}}\n{{local.bad}}",
            &test_values()
        )
        .unwrap_err()
    );

    assert!(error.contains("expected 0xNN or N%"));
}
