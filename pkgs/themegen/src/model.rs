use std::collections::BTreeMap;

use serde::Serialize;

#[derive(Serialize)]
pub(crate) struct Output {
    pub(crate) source: SourceInfo,
    pub(crate) material: ThemeSchemes,
    pub(crate) base16: Base16Schemes,
}

#[derive(Serialize)]
pub(crate) struct SourceInfo {
    pub(crate) image: String,
    pub(crate) r#type: String,
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
