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

//! JSON helpers and `unitMeta` decoding for `//tools/delivery/orchestrate`,
//! backed by `vitruvian_gojson`.

pub use vitruvian_gojson::{decode_string_map, go_string};
use vitruvian_gojson::{parse, Dec};

/// `json.Marshal(v)`.
pub fn marshal<T: serde::Serialize>(v: &T) -> Vec<u8> {
    vitruvian_gojson::marshal(v).expect(
        "no caller marshals a float; vitruvian_gojson rejects floats, see packages/gocompat/gojson/README.md",
    )
}

/// `json.MarshalIndent(v, "", "  ")`.
pub fn marshal_indent<T: serde::Serialize>(v: &T) -> Vec<u8> {
    vitruvian_gojson::marshal_indent(v).expect(
        "no caller marshals a float; vitruvian_gojson rejects floats, see packages/gocompat/gojson/README.md",
    )
}

/// `tools/delivery/defs.bzl`'s metadata, as `unitMeta` decodes it.
#[derive(Debug, Clone, Default)]
pub struct UnitMeta {
    pub schema: i64,
    pub name: String,
    pub kind: String,
    pub run: String,
    pub build: String,
    pub environments: Option<Vec<String>>,
    pub github_environment: String,
    pub promotion: String,
    pub companions: Option<Vec<String>>,
    pub extra_paths: Option<Vec<String>>,
    pub exclude_paths: Option<Vec<String>>,
    pub graph_targets: Option<Vec<String>>,
    pub preflight: String,
    pub package: String,
}

const FIELDS: &[&str] = &[
    "schema",
    "name",
    "kind",
    "run",
    "build",
    "environments",
    "github_environment",
    "promotion",
    "companions",
    "extra_paths",
    "exclude_paths",
    "graph_targets",
    "preflight",
    "package",
];

/// `json.Unmarshal(raw, &unitMeta{})`.
pub fn decode_unit_meta(raw: &[u8]) -> Result<UnitMeta, String> {
    let v = parse(raw)?;
    let mut meta = UnitMeta::default();
    let mut d = Dec::new();
    d.object(
        &v,
        "unitMeta",
        "main.unitMeta",
        FIELDS,
        |d, name, val| match name {
            "schema" => d.int(val, &mut meta.schema),
            "name" => d.string(val, &mut meta.name),
            "kind" => d.string(val, &mut meta.kind),
            "run" => d.string(val, &mut meta.run),
            "build" => d.string(val, &mut meta.build),
            "environments" => d.strings(val, &mut meta.environments),
            "github_environment" => d.string(val, &mut meta.github_environment),
            "promotion" => d.string(val, &mut meta.promotion),
            "companions" => d.strings(val, &mut meta.companions),
            "extra_paths" => d.strings(val, &mut meta.extra_paths),
            "exclude_paths" => d.strings(val, &mut meta.exclude_paths),
            "graph_targets" => d.strings(val, &mut meta.graph_targets),
            "preflight" => d.string(val, &mut meta.preflight),
            _ => d.string(val, &mut meta.package),
        },
    );
    d.finish()?;
    Ok(meta)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unit_meta_follows_go_rules() {
        let m = decode_unit_meta(
            br#"{"NAME":"a","name":"b","environments":["x","y"],"environments":[null]}"#,
        )
        .unwrap();
        assert_eq!(m.name, "b");
        assert_eq!(m.environments, Some(vec!["x".to_string()]));
        assert_eq!(decode_unit_meta(b"null").unwrap().name, "");
        assert_eq!(
            decode_unit_meta(br#"{"extra_paths":[]}"#)
                .unwrap()
                .extra_paths,
            Some(vec![])
        );
        assert_eq!(
            decode_unit_meta(br#"{"extra_paths":null}"#)
                .unwrap()
                .extra_paths,
            None
        );
        assert_eq!(
            decode_unit_meta(br#"{"schema":"1","name":3}"#).unwrap_err(),
            "json: cannot unmarshal string into Go struct field unitMeta.schema of type int"
        );
        assert_eq!(
            decode_unit_meta(br#"{"schema":1.5}"#).unwrap_err(),
            "json: cannot unmarshal number 1.5 into Go struct field unitMeta.schema of type int"
        );
        assert_eq!(
            decode_unit_meta(b"[]").unwrap_err(),
            "json: cannot unmarshal array into Go value of type main.unitMeta"
        );
    }

    #[test]
    fn marshal_escapes_like_go() {
        let v = vec!["<a&b>\u{2028}\n\u{1}"];
        assert_eq!(
            String::from_utf8(marshal(&v)).unwrap(),
            r#"["\u003ca\u0026b\u003e\u2028\n\u0001"]"#
        );
    }

    #[test]
    fn string_map() {
        assert_eq!(decode_string_map(b"{not json"), None);
        assert_eq!(decode_string_map(br#"{"a":1}"#), None);
        assert_eq!(
            decode_string_map(br#"{"a":"x"}"#),
            Some(vec![("a".into(), "x".into())])
        );
    }
}
