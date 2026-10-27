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

//! catalog/tools.json against its schema and its rules, with no network.
//!
//! Run by `bazel test //catalog:catalog_test`, on every pull request. The check
//! that fetches each changed entry's download is .github/workflows/catalog-check.yaml.

use crate::json::{self, Value};
use crate::schema::Validator;
use crate::{here, py, pyre, rules};

const GOOD_JSON: &str = r#"{
    "id": "dev.vitruvian.reference",
    "name": {"en": "Reference tool"},
    "publisher": "VitruvianSoftware",
    "summary": {"en": "Says hello. The smallest tool that speaks protocol 1."},
    "version": "0.1.0",
    "protocol": "1",
    "minimumAppVersion": "3.43.0",
    "source": "https://github.com/VitruvianSoftware/vitruvian-sdk",
    "download": {
        "url": "https://github.com/VitruvianSoftware/vitruvian-sdk/releases/download/v0.9.0/reference-tool-0.1.0.zip",
        "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
        "size": 4096
    },
    "uses": ["notify"],
    "commands": [{"id": "hello", "title": {"en": "Say hello"}}]
}"#;

fn good() -> Value {
    json::loads(GOOD_JSON).unwrap()
}

fn catalog_with(tools: Vec<Value>) -> Value {
    py::obj(vec![
        ("version", Value::Int(1)),
        ("generated", py::s("2026-10-12T00:00:00Z")),
        ("tools", Value::List(tools)),
    ])
}

fn entry(changes: &[(&str, Value)]) -> Value {
    let mut tool = good();
    for (path, value) in changes {
        let keys: Vec<&str> = path.split("__").collect();
        let mut target = &mut tool;
        for key in &keys[..keys.len() - 1] {
            target = match target {
                Value::Dict(d) => d.get_mut(key).unwrap(),
                _ => panic!("expected dict at {}", key),
            };
        }
        match target {
            Value::Dict(d) => d.insert(*keys.last().unwrap(), value.clone()),
            _ => panic!("expected dict"),
        }
    }
    tool
}

fn load_schema() -> Value {
    let path = here::catalog_dir().join("catalog.schema.json");
    let text = std::fs::read_to_string(&path).unwrap();
    json::loads(&text).unwrap()
}

fn refused(schema: &Value, catalog: &Value) -> Vec<String> {
    let found: Vec<String> = Validator::new(schema)
        .iter_errors(catalog)
        .into_iter()
        .map(|e| e.message)
        .collect();
    if !found.is_empty() {
        found
    } else {
        rules::problems(catalog).unwrap()
    }
}

#[test]
fn test_the_catalog_is_well_formed() {
    let schema = load_schema();
    let (_, catalog) = rules::load(&here::catalog_dir().join("tools.json")).unwrap();
    assert_eq!(refused(&schema, &catalog), Vec::<String>::new());
}

#[test]
fn test_the_schema_is_a_schema() {
    let schema = load_schema();
    assert_eq!(
        schema.field("$schema"),
        Some(&py::s("https://json-schema.org/draft/2020-12/schema"))
    );
    assert_eq!(schema.field("type"), Some(&py::s("object")));
    assert!(schema.field("required").is_some());
    assert!(schema.field("properties").is_some());
    assert!(schema.field("$defs").is_some());
}

#[test]
fn test_a_good_entry_passes() {
    let schema = load_schema();
    assert_eq!(
        refused(&schema, &catalog_with(vec![good()])),
        Vec::<String>::new()
    );
    assert_eq!(
        refused(
            &schema,
            &catalog_with(vec![entry(&[(
                "panels",
                json::loads(r#"["island", "settings"]"#).unwrap()
            )])])
        ),
        Vec::<String>::new()
    );
}

#[test]
fn test_each_rule_refuses() {
    let schema = load_schema();
    let good_url =
        "https://github.com/VitruvianSoftware/vitruvian-sdk/releases/download/v0.9.0/reference-tool-0.1.0.zip";
    let cases: Vec<(&str, Value)> = vec![
        ("an id with no dot", entry(&[("id", py::s("reference"))])),
        (
            "a version that is not semver",
            entry(&[("version", py::s("1.0"))]),
        ),
        (
            "an app version that is not semver",
            entry(&[("minimumAppVersion", py::s("3.43"))]),
        ),
        (
            "a protocol the app has not",
            entry(&[("protocol", py::s("3"))]),
        ),
        (
            "a summary with no English",
            entry(&[("summary", json::loads(r#"{"fr": "Bonjour"}"#).unwrap())]),
        ),
        (
            "a download over http",
            entry(&[("download__url", py::s(&good_url.replace("https", "http")))]),
        ),
        (
            "a download from another owner",
            entry(&[(
                "download__url",
                py::s("https://github.com/someone/tool/releases/download/v1/tool.zip"),
            )]),
        ),
        (
            "a download that walks up",
            entry(&[(
                "download__url",
                py::s("https://github.com/VitruvianSoftware/x/releases/download/../../someone/t.zip"),
            )]),
        ),
        (
            "a download that is no zip",
            entry(&[(
                "download__url",
                py::s(&format!("{}.tar.gz", &good_url[..good_url.len() - 4])),
            )]),
        ),
        (
            "a checksum in capitals",
            entry(&[("download__sha256", py::s(&"A".repeat(64)))]),
        ),
        (
            "a checksum too short",
            entry(&[("download__sha256", py::s(&"0".repeat(63)))]),
        ),
        (
            "an empty download",
            entry(&[("download__size", Value::Int(0))]),
        ),
        (
            "a download over 256 MB",
            entry(&[("download__size", Value::Int(268_435_457))]),
        ),
        (
            "a service the protocol has not",
            entry(&[("uses", json::loads(r#"["camera"]"#).unwrap())]),
        ),
        (
            "a panel placement the protocol has not",
            entry(&[("panels", json::loads(r#"["menubar"]"#).unwrap())]),
        ),
        (
            "a panel placement listed twice",
            entry(&[("panels", json::loads(r#"["island", "island"]"#).unwrap())]),
        ),
        (
            "a field the schema does not name",
            entry(&[("homepage", py::s("https://example.com"))]),
        ),
        (
            "two commands with one id",
            entry(&[(
                "commands",
                json::loads(
                    r#"[{"id": "hello", "title": {"en": "A"}}, {"id": "hello", "title": {"en": "B"}}]"#,
                )
                .unwrap(),
            )]),
        ),
    ];
    for (reason, tool) in cases {
        assert!(
            !refused(&schema, &catalog_with(vec![tool])).is_empty(),
            "{}",
            reason
        );
    }
    let twice = catalog_with(vec![good(), good()]);
    assert!(refused(&schema, &twice).join(" ").contains("listed twice"));
    let mut undated = catalog_with(vec![good()]);
    if let Value::Dict(ref mut d) = undated {
        d.insert("generated", py::s("yesterday"));
    }
    assert!(!refused(&schema, &undated).is_empty());
}

#[test]
fn test_the_app_is_built_with_this_key() {
    let here_dir = here::catalog_dir();
    let root = here_dir.parent().unwrap();
    let swift = root.join(
        "apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/External/Catalogue/CatalogueSigning.swift",
    );
    let swift_text = std::fs::read_to_string(&swift).unwrap();
    let found = pyre::fixed(r#"package static let publicKey = "([^"]*)""#)
        .search(&swift_text)
        .expect("CatalogueSigning.swift declares publicKey");
    let expected = std::fs::read_to_string(here_dir.join("public-key.txt"))
        .unwrap()
        .trim()
        .to_string();
    assert_eq!(found.group(1).unwrap(), expected);
}

#[test]
fn test_versions_sort_as_semver() {
    let order = ["0.9.0", "1.0.0-beta", "1.0.0", "1.0.1", "1.10.0", "2.0.0"];
    let mut sorted = order;
    sorted.sort_by_key(|v| rules::semver_str(v).unwrap());
    assert_eq!(sorted, order);
    assert!(rules::semver_str("01.0.0").is_none());
}

#[test]
fn test_only_new_or_changed_entries_are_fetched() {
    let newer = entry(&[("version", py::s("0.2.0"))]);
    let other = entry(&[("id", py::s("dev.vitruvian.other"))]);
    assert_eq!(
        rules::changed(
            &catalog_with(vec![good()]),
            &catalog_with(vec![good(), other.clone()])
        )
        .unwrap(),
        vec![other]
    );
    assert_eq!(
        rules::changed(
            &catalog_with(vec![good()]),
            &catalog_with(vec![newer.clone()])
        )
        .unwrap(),
        vec![newer]
    );
    assert_eq!(
        rules::changed(&catalog_with(vec![good()]), &catalog_with(vec![good()])).unwrap(),
        Vec::<Value>::new()
    );
}
