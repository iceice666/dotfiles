use std::collections::{BTreeMap, HashMap};

use anyhow::{bail, Context, Result};

use super::expression::{evaluate_header_expression, lookup};

pub(crate) struct TemplateRenderer {
    values: HashMap<String, String>,
}

impl TemplateRenderer {
    pub(crate) fn new(values: &BTreeMap<String, String>) -> Self {
        Self {
            values: values
                .iter()
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect(),
        }
    }

    pub(crate) fn render(&self, template: &str) -> Result<String> {
        let mut values = self.values.clone();
        let body = parse_header(template, &mut values)?;
        render_body(body, &values)
    }
}

fn parse_header<'a>(template: &'a str, values: &mut HashMap<String, String>) -> Result<&'a str> {
    let leading = template.len() - template.trim_start().len();
    let after_leading = &template[leading..];
    let Some(after_open) = after_leading.strip_prefix("{{#themegen") else {
        return Ok(template);
    };

    let end = after_open
        .find("}}")
        .context("unclosed themegen header block")?;
    let header = &after_open[..end];

    for (line_index, line) in header.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        parse_header_line(line, values)
            .with_context(|| format!("failed to parse themegen header line {}", line_index + 1))?;
    }

    let body = &after_open[end + 2..];
    Ok(body
        .strip_prefix("\r\n")
        .or_else(|| body.strip_prefix('\n'))
        .unwrap_or(body))
}

fn parse_header_line(line: &str, values: &mut HashMap<String, String>) -> Result<()> {
    let assignment = line
        .strip_prefix("let ")
        .with_context(|| format!("expected `let local.name = expression`, got `{line}`"))?;
    let (name, expression) = assignment
        .split_once('=')
        .with_context(|| format!("expected `=` in `{line}`"))?;
    let name = name.trim();

    validate_local_name(name)?;
    if values.contains_key(name) {
        bail!("duplicate template local `{name}`");
    }

    let value = evaluate_header_expression(expression.trim(), values)
        .with_context(|| format!("failed to evaluate `{name}`"))?;
    values.insert(name.to_string(), value);

    Ok(())
}

fn validate_local_name(name: &str) -> Result<()> {
    let local = name
        .strip_prefix("local.")
        .with_context(|| format!("template local `{name}` must start with `local.`"))?;
    if local.is_empty() {
        bail!("template local `{name}` must include a name after `local.`");
    }
    if !local
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
    {
        bail!("template local `{name}` may only use ASCII letters, digits, and `_`");
    }

    Ok(())
}

fn render_body(template: &str, values: &HashMap<String, String>) -> Result<String> {
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
        let value = render_lookup(key, values)
            .with_context(|| format!("failed to render template placeholder {{{{{raw_key}}}}}"))?;
        rendered.push_str(&value);
        rest = &after_start[end + 2..];
    }

    rendered.push_str(rest);

    Ok(rendered)
}

fn render_lookup(key: &str, values: &HashMap<String, String>) -> Result<String> {
    if key.is_empty() {
        bail!("empty template placeholder");
    }
    if key.contains('|') || key.contains('(') || key.contains(')') {
        bail!("template body placeholders only support direct lookups");
    }

    lookup(key, values)
}
