use std::collections::BTreeMap;

use serde::Serialize;

#[derive(Serialize)]
pub(crate) struct PaletteOutput {
    pub(crate) input: InputInfo,
    pub(crate) scheme: String,
    pub(crate) seed: SeedInfo,
    pub(crate) color: ThemeSchemes,
    pub(crate) base16: Base16Schemes,
    pub(crate) syntax: SyntaxSchemes,
}

#[derive(Clone, Serialize)]
pub(crate) struct InputInfo {
    pub(crate) kind: String,
    pub(crate) value: String,
}

#[derive(Serialize)]
pub(crate) struct SeedInfo {
    pub(crate) color: String,
}

#[derive(Serialize)]
pub(crate) struct ThemeSchemes {
    pub(crate) light: BTreeMap<String, String>,
    pub(crate) dark: BTreeMap<String, String>,
}

#[derive(Serialize)]
pub(crate) struct Base16Schemes {
    pub(crate) light: Base16Palette,
    pub(crate) dark: Base16Palette,
}

#[derive(Serialize)]
pub(crate) struct SyntaxSchemes {
    pub(crate) light: SyntaxPalette,
    pub(crate) dark: SyntaxPalette,
}

#[derive(Serialize)]
pub(crate) struct Base16Palette {
    pub(crate) base00: String,
    pub(crate) base01: String,
    pub(crate) base02: String,
    pub(crate) base03: String,
    pub(crate) base04: String,
    pub(crate) base05: String,
    pub(crate) base06: String,
    pub(crate) base07: String,
    pub(crate) base08: String,
    pub(crate) base09: String,
    #[serde(rename = "base0A")]
    pub(crate) base0_a: String,
    #[serde(rename = "base0B")]
    pub(crate) base0_b: String,
    #[serde(rename = "base0C")]
    pub(crate) base0_c: String,
    #[serde(rename = "base0D")]
    pub(crate) base0_d: String,
    #[serde(rename = "base0E")]
    pub(crate) base0_e: String,
    #[serde(rename = "base0F")]
    pub(crate) base0_f: String,
}

#[derive(Serialize)]
pub(crate) struct SyntaxPalette {
    pub(crate) boolean: String,
    pub(crate) comment: String,
    pub(crate) emphasis: String,
    pub(crate) function: String,
    pub(crate) keyword: String,
    pub(crate) link: String,
    pub(crate) literal: String,
    pub(crate) number: String,
    pub(crate) operator: String,
    pub(crate) predictive: String,
    pub(crate) punctuation: String,
    pub(crate) string: String,
    #[serde(rename = "stringRegex")]
    pub(crate) string_regex: String,
    #[serde(rename = "stringSpecial")]
    pub(crate) string_special: String,
    pub(crate) title: String,
    #[serde(rename = "type")]
    pub(crate) type_name: String,
    pub(crate) variable: String,
}
