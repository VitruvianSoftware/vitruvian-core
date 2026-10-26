// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! tools/sync-site-tools/catalogue.py: the catalog's part of the website,
//! `_data/tools.yml`, written from catalog/tools.json, byte for byte as the
//! Python writes it.

use crate::json::{self, Value};
use crate::py;
use crate::pyerr::Res;
use crate::pystr;
use std::path::Path;

pub const CATALOG: &str = "catalog/tools.json";
pub const PUBLIC_KEY: &str = "catalog/public-key.txt";
pub const DATA: &str = "apps/web/vitruviansoftware-dev/_data/tools.yml";

/// What a tool says it uses, in the words of the app's agreement sheet.
pub const USES: &[(&str, &str)] = &[
    ("notify", "Show messages and play the alert sound"),
    ("open", "Open links"),
    ("clipboard.read", "Read the clipboard"),
    ("clipboard.write", "Write to the clipboard"),
    ("keystrokes", "Paste and press menu commands in other apps"),
    ("processes", "End other programs"),
    ("storage", "Save its own settings"),
];

/// `size(count)`: 4 KB, 1.8 MB.
pub fn size(count: &Value) -> Res<String> {
    let n = match count {
        Value::Bool(b) => *b as i64 as f64,
        other => other.as_f64().ok_or_else(|| {
            crate::pyerr::Stop::crash(
                "TypeError",
                format!(
                    "'<' not supported between instances of '{}' and 'int'",
                    other.type_name()
                ),
            )
        })?,
    };
    if n < 1_048_576.0 {
        let kb = pystr::round_half_even(n / 1024.0).max(1.0);
        return Ok(format!("{} KB", kb as i64));
    }
    Ok(format!("{} MB", pystr::format_fixed(n / 1_048_576.0, 1)))
}

/// `scalar(value)`: a YAML scalar, which JSON's double-quoted string is.
pub fn scalar(v: &Value) -> String {
    json::dumps_unicode(v)
}

/// `render(catalog, public_key)`.
pub fn render(catalog: &Value, public_key: &str) -> Res<Vec<u8>> {
    let mut lines = vec![
        "# Written by tools/sync-site-tools from catalog/tools.json. Do not edit:".to_string(),
        "#   bazel run //tools/sync-site-tools:sync".to_string(),
        format!("generated: {}", scalar(py::index(catalog, "generated")?)),
        format!("public_key: {}", scalar(&py::s(public_key))),
    ];
    let tools = py::iterate(&py::get_or(catalog, "tools", Value::List(vec![]))?)?;
    lines.push(
        if tools.is_empty() {
            "tools: []"
        } else {
            "tools:"
        }
        .to_string(),
    );
    for tool in &tools {
        lines.push(format!("  - id: {}", scalar(py::index(tool, "id")?)));
        lines.push(format!(
            "    name: {}",
            scalar(py::path(tool, &["name", "en"])?)
        ));
        lines.push(format!(
            "    publisher: {}",
            scalar(py::index(tool, "publisher")?)
        ));
        lines.push(format!(
            "    summary: {}",
            scalar(py::path(tool, &["summary", "en"])?)
        ));
        lines.push(format!(
            "    version: {}",
            scalar(py::index(tool, "version")?)
        ));
        lines.push(format!(
            "    source: {}",
            scalar(py::index(tool, "source")?)
        ));
        lines.push(format!(
            "    download: {}",
            scalar(py::path(tool, &["download", "url"])?)
        ));
        lines.push(format!(
            "    size: {}",
            scalar(&py::s(size(py::path(tool, &["download", "size"])?)?))
        ));
        lines.push(format!(
            "    sha256: {}",
            scalar(py::path(tool, &["download", "sha256"])?)
        ));
        let mut uses = Vec::new();
        for name in py::iterate(&py::get_or(tool, "uses", Value::List(vec![]))?)? {
            py::hashable(&name)?;
            if let Value::Str(n) = &name {
                if let Some((_, words)) = USES.iter().find(|(k, _)| k == n) {
                    uses.push(*words);
                }
            }
        }
        lines.push(
            if uses.is_empty() {
                "    uses: []"
            } else {
                "    uses:"
            }
            .to_string(),
        );
        for words in uses {
            lines.push(format!("      - {}", scalar(&py::s(words))));
        }
    }
    Ok(format!("{}\n", lines.join("\n")).into_bytes())
}

/// `outputs(root)`: each file this part of the site is made of, by its path
/// from the repository's root, and what it must hold.
pub fn outputs(root: &Path) -> Res<Vec<(String, Vec<u8>)>> {
    let text = crate::pytext::read_text(&root.join(CATALOG))
        .map_err(|m| crate::pyerr::Stop::from_text(&m))?;
    let catalog = json::loads(&text)
        .map_err(|e| crate::pyerr::Stop::crash("json.decoder.JSONDecodeError", e.to_string()))?;
    let key = crate::pytext::read_text(&root.join(PUBLIC_KEY))
        .map_err(|m| crate::pyerr::Stop::from_text(&m))?;
    Ok(vec![(
        DATA.to_string(),
        render(&catalog, pystr::strip(&key))?,
    )])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes_as_a_person_reads_them() {
        let n = |x: i64| size(&py::int(x as i128)).unwrap();
        assert_eq!(n(0), "1 KB");
        assert_eq!(n(512), "1 KB"); // round(0.5) is 0, then max(1, 0)
        assert_eq!(n(1536), "2 KB");
        assert_eq!(n(2560), "2 KB"); // round(2.5) is 2
        assert_eq!(n(1_048_575), "1024 KB");
        assert_eq!(n(1_887_437), "1.8 MB");
    }

    #[test]
    fn renders_an_empty_list() {
        let c = json::loads(r#"{"generated": "2026-01-01T00:00:00Z", "tools": []}"#).unwrap();
        let out = String::from_utf8(render(&c, "KEY").unwrap()).unwrap();
        assert!(out.ends_with("public_key: \"KEY\"\ntools: []\n"));
    }
}
