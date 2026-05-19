mod expression;
mod renderer;

#[cfg(test)]
mod tests;

use std::collections::BTreeMap;

#[cfg(test)]
use anyhow::Result;

use crate::model::{Base16Palette, PaletteOutput, SyntaxPalette};

pub(crate) use renderer::TemplateRenderer;

pub(crate) fn template_values(output: &PaletteOutput) -> BTreeMap<String, String> {
    let mut values = BTreeMap::new();

    values.insert("input.kind".to_string(), output.input.kind.clone());
    values.insert("input.value".to_string(), output.input.value.clone());
    values.insert("scheme".to_string(), output.scheme.clone());
    values.insert("seed.color".to_string(), output.seed.color.clone());

    extend_prefixed(&mut values, "color.light", &output.color.light);
    extend_prefixed(&mut values, "color.dark", &output.color.dark);
    extend_base16(&mut values, "base16.light", &output.base16.light);
    extend_base16(&mut values, "base16.dark", &output.base16.dark);
    extend_syntax(&mut values, "syntax.light", &output.syntax.light);
    extend_syntax(&mut values, "syntax.dark", &output.syntax.dark);

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

fn extend_syntax(values: &mut BTreeMap<String, String>, prefix: &str, palette: &SyntaxPalette) {
    values.insert(format!("{prefix}.boolean"), palette.boolean.clone());
    values.insert(format!("{prefix}.comment"), palette.comment.clone());
    values.insert(format!("{prefix}.emphasis"), palette.emphasis.clone());
    values.insert(format!("{prefix}.function"), palette.function.clone());
    values.insert(format!("{prefix}.keyword"), palette.keyword.clone());
    values.insert(format!("{prefix}.link"), palette.link.clone());
    values.insert(format!("{prefix}.literal"), palette.literal.clone());
    values.insert(format!("{prefix}.number"), palette.number.clone());
    values.insert(format!("{prefix}.operator"), palette.operator.clone());
    values.insert(format!("{prefix}.predictive"), palette.predictive.clone());
    values.insert(format!("{prefix}.punctuation"), palette.punctuation.clone());
    values.insert(format!("{prefix}.string"), palette.string.clone());
    values.insert(
        format!("{prefix}.stringRegex"),
        palette.string_regex.clone(),
    );
    values.insert(
        format!("{prefix}.stringSpecial"),
        palette.string_special.clone(),
    );
    values.insert(format!("{prefix}.title"), palette.title.clone());
    values.insert(format!("{prefix}.type"), palette.type_name.clone());
    values.insert(format!("{prefix}.variable"), palette.variable.clone());
}

#[cfg(test)]
fn render_template(template: &str, values: &BTreeMap<String, String>) -> Result<String> {
    TemplateRenderer::new(values).render(template)
}
