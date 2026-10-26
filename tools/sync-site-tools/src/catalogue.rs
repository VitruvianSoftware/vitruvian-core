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

//! catalogue.py: the catalog's part of the website, `_data/tools.yml`,
//! which the page tools/catalog.html lists, written from catalog/tools.json.

use crate::json::{self, BigInt, Value};
use crate::pyerr::PyErr;
use crate::pyfs;
use crate::pystr::PyStr;

pub const CATALOG: &str = "catalog/tools.json";
pub const PUBLIC_KEY: &str = "catalog/public-key.txt";
pub const DATA: &str = "apps/web/vitruviansoftware-dev/_data/tools.yml";

/// What a tool says it uses, in the words the app's agreement sheet uses.
pub const USES: &[(&str, &str)] = &[
    ("notify", "Show messages and play the alert sound"),
    ("open", "Open links"),
    ("clipboard.read", "Read the clipboard"),
    ("clipboard.write", "Write to the clipboard"),
    ("keystrokes", "Paste and press menu commands in other apps"),
    ("processes", "End other programs"),
    ("storage", "Save its own settings"),
];

fn round_half_even(x: f64) -> f64 {
    let floor = x.floor();
    let diff = x - floor;
    // Up past the half, and at the half when that makes the result even.
    if diff > 0.5 || (diff == 0.5 && floor % 2.0 != 0.0) {
        floor + 1.0
    } else {
        floor
    }
}

/// `size(count)`: bytes as a person reads them, 4 KB, 1.8 MB.
pub fn size(count: &Value) -> Result<String, PyErr> {
    let limit = Value::Int(BigInt::from_i64(1_048_576));
    let below = match count {
        Value::Int(_) | Value::Bool(_) | Value::Float(_) => count.py_lt(&limit)?,
        other => {
            return Err(PyErr::type_error(&format!(
                "'<' not supported between instances of '{}' and 'int'",
                other.type_name()
            )))
        }
    };
    let divide = |power: u32| -> Result<f64, PyErr> {
        match count {
            Value::Float(f) => Ok(f / (1u64 << power) as f64),
            Value::Bool(b) => Ok(*b as u8 as f64 / (1u64 << power) as f64),
            Value::Int(i) => i.div_pow2(power).ok_or_else(|| {
                PyErr::exc(
                    "OverflowError",
                    "integer division result too large for a float",
                )
            }),
            _ => unreachable!(),
        }
    };
    if below {
        let x = divide(10)?;
        if x.is_infinite() {
            return Err(PyErr::exc(
                "OverflowError",
                "cannot convert float infinity to integer",
            ));
        }
        let rounded = round_half_even(x);
        let kb = if rounded < 1.0 { 1 } else { rounded as i64 };
        return Ok(format!("{} KB", kb));
    }
    Ok(format!("{} MB", json::format_fixed1(divide(20)?)))
}

/// `scalar(value)`: a YAML scalar, which JSON's double-quoted string is.
pub fn scalar(value: &Value) -> PyStr {
    json::dumps(value, false, None)
}

fn line(parts: &[&PyStr]) -> PyStr {
    PyStr::concat(parts)
}

fn lit(text: &str) -> PyStr {
    PyStr::from(text)
}

/// `render(catalog, public_key)`.
pub fn render(catalog: &Value, public_key: &PyStr) -> Result<Vec<u8>, PyErr> {
    let mut lines: Vec<PyStr> = vec![
        lit("# Written by tools/sync-site-tools from catalog/tools.json. Do not edit:"),
        lit("#   bazel run //tools/sync-site-tools:sync"),
    ];
    lines.push(line(&[
        &lit("generated: "),
        &scalar(catalog.subscript("generated")?),
    ]));
    lines.push(line(&[
        &lit("public_key: "),
        &scalar(&Value::Str(public_key.clone())),
    ]));
    let tools = catalog.get_or("tools", Value::List(Vec::new()))?;
    lines.push(lit(if tools.truthy() {
        "tools:"
    } else {
        "tools: []"
    }));
    for tool in tools.iterate()? {
        let field = |label: &str, value: &Value| line(&[&lit(label), &scalar(value)]);
        let entry = vec![
            field("  - id: ", tool.subscript("id")?),
            field("    name: ", tool.subscript("name")?.subscript("en")?),
            field("    publisher: ", tool.subscript("publisher")?),
            field("    summary: ", tool.subscript("summary")?.subscript("en")?),
            field("    version: ", tool.subscript("version")?),
            field("    source: ", tool.subscript("source")?),
            field(
                "    download: ",
                tool.subscript("download")?.subscript("url")?,
            ),
            field(
                "    size: ",
                &json::s(&size(tool.subscript("download")?.subscript("size")?)?),
            ),
            field(
                "    sha256: ",
                tool.subscript("download")?.subscript("sha256")?,
            ),
        ];
        lines.extend(entry);
        let mut uses: Vec<&str> = Vec::new();
        for name in tool.get_or("uses", Value::List(Vec::new()))?.iterate()? {
            name.check_hashable()?;
            if let Some((_, words)) = USES.iter().find(|(key, _)| name.eq_str(key)) {
                uses.push(words);
            }
        }
        lines.push(lit(if uses.is_empty() {
            "    uses: []"
        } else {
            "    uses:"
        }));
        for words in uses {
            lines.push(line(&[&lit("      - "), &scalar(&json::s(words))]));
        }
    }
    let mut text = PyStr::join("\n", &lines);
    text.push_str("\n");
    text.encode_utf8()
}

/// `outputs(root)`: each file this part makes, by its path from the
/// repository's root, and what it must hold.
pub fn outputs(base: &PyStr) -> Result<Vec<(String, Vec<u8>)>, PyErr> {
    let catalog = json::loads(&pyfs::read_text(&pyfs::path_join(base, CATALOG))?)?;
    let public_key = pyfs::read_text_ascii(&pyfs::path_join(base, PUBLIC_KEY))?.strip();
    Ok(vec![(DATA.to_string(), render(&catalog, &public_key)?)])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry() -> Value {
        json::loads(&PyStr::from(
            r#"{
                "id": "dev.vitruvian.reference",
                "name": {"en": "Reference tool", "fr": "Outil de référence"},
                "publisher": "VitruvianSoftware",
                "summary": {"en": "Says “hello”."},
                "version": "0.1.0",
                "protocol": "1",
                "minimumAppVersion": "3.43.0",
                "source": "https://github.com/VitruvianSoftware/vitruvian-sdk",
                "download": {
                    "url": "https://github.com/VitruvianSoftware/x/releases/download/v1/x.zip",
                    "sha256": "abababababababababababababababababababababababababababababababab",
                    "size": 1834021
                },
                "uses": ["notify", "storage"],
                "commands": []
            }"#,
        ))
        .unwrap()
    }

    /// sync_test.test_an_entry_as_the_page_reads_it.
    #[test]
    fn an_entry_as_the_page_reads_it() {
        let catalog = json::obj(vec![
            ("generated", json::s("2026-11-02T10:00:00Z")),
            ("tools", Value::List(vec![entry()])),
        ]);
        let text = String::from_utf8(render(&catalog, &PyStr::from("KEY=")).unwrap()).unwrap();
        let lines: Vec<&str> = text.lines().skip(2).collect();
        let sha = format!("    sha256: \"{}\"", "ab".repeat(32));
        assert_eq!(
            lines,
            vec![
                "generated: \"2026-11-02T10:00:00Z\"",
                "public_key: \"KEY=\"",
                "tools:",
                "  - id: \"dev.vitruvian.reference\"",
                "    name: \"Reference tool\"",
                "    publisher: \"VitruvianSoftware\"",
                "    summary: \"Says “hello”.\"",
                "    version: \"0.1.0\"",
                "    source: \"https://github.com/VitruvianSoftware/vitruvian-sdk\"",
                "    download: \"https://github.com/VitruvianSoftware/x/releases/download/v1/x.zip\"",
                "    size: \"1.7 MB\"",
                sha.as_str(),
                "    uses:",
                "      - \"Show messages and play the alert sound\"",
                "      - \"Save its own settings\"",
            ]
        );
        let empty = json::obj(vec![
            ("generated", json::s("2026-11-02T10:00:00Z")),
            ("tools", Value::List(vec![])),
        ]);
        let text = String::from_utf8(render(&empty, &PyStr::from("K")).unwrap()).unwrap();
        assert!(text.contains("tools: []"));
    }

    #[test]
    fn sizes_as_python_rounds_them() {
        let int = |n: i64| Value::Int(BigInt::from_i64(n));
        let cases = [
            (int(4000), "4 KB"),
            (int(0), "1 KB"),
            (int(-5), "1 KB"),
            (int(1536), "2 KB"),
            (int(2560), "2 KB"),
            (int(1_048_575), "1024 KB"),
            (int(1_048_576), "1.0 MB"),
            (int(2_359_296), "2.2 MB"),
            (Value::Bool(true), "1 KB"),
            (Value::Float(f64::NAN), "nan MB"),
            (Value::Float(f64::INFINITY), "inf MB"),
        ];
        for (count, want) in cases {
            assert_eq!(size(&count).unwrap(), want, "{:?}", count);
        }
        assert_eq!(
            size(&Value::Float(f64::NEG_INFINITY))
                .unwrap_err()
                .last_line(),
            "OverflowError: cannot convert float infinity to integer"
        );
        assert_eq!(
            size(&json::s("12")).unwrap_err().last_line(),
            "TypeError: '<' not supported between instances of 'str' and 'int'"
        );
    }
}
