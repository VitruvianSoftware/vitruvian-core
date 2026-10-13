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

//! The generated types against the protocol's own files: the table of
//! messages, and every example message and manifest, read and written back.

use serde_json::{Map, Value};
use vitruvian_tool_kit::{round_trip, METHODS, PROTOCOL_VERSION};

const TABLE: &str = include_str!("../../../protocol/methods.json");
const MESSAGES: &str = include_str!("../../../protocol/examples/messages.json");
const MANIFESTS: &str = include_str!("../../../protocol/examples/manifests.json");

/// The Rust name the generator gives a definition of the schema.
fn type_name(definition: &str) -> String {
    let mut name = String::new();
    let mut word = String::new();
    let flush = |word: &mut String, name: &mut String| {
        if let Some(first) = word.chars().next() {
            name.push(first.to_ascii_uppercase());
            name.push_str(&word[1..].to_ascii_lowercase());
        }
        word.clear();
    };
    let chars: Vec<char> = definition.chars().collect();
    for (at, c) in chars.iter().enumerate() {
        let next_lower = chars.get(at + 1).is_some_and(|n| n.is_ascii_lowercase());
        let previous_lower = at > 0 && chars[at - 1].is_ascii_lowercase();
        if c.is_ascii_uppercase() && (previous_lower || (next_lower && !word.is_empty())) {
            flush(&mut word, &mut name);
        }
        word.push(*c);
    }
    flush(&mut word, &mut name);
    name
}

#[test]
fn methods_are_methods_json() {
    let table: Value = serde_json::from_str(TABLE).unwrap();
    assert_eq!(table["protocol"], PROTOCOL_VERSION);
    let rows = table["methods"].as_array().unwrap();
    assert_eq!(rows.len(), METHODS.len());
    for (row, method) in rows.iter().zip(METHODS) {
        let text = |key: &str| row[key].as_str().map(str::to_string);
        assert_eq!(text("method").as_deref(), Some(method.name));
        assert_eq!(text("sender").as_deref(), Some(method.sender));
        assert_eq!(text("kind").as_deref(), Some(method.kind));
        assert_eq!(text("uses").as_deref(), method.uses);
        assert_eq!(
            text("params").map(|d| type_name(&d)).as_deref(),
            method.params
        );
        assert_eq!(
            text("result").map(|d| type_name(&d)).as_deref(),
            method.result
        );
    }
}

/// Whether every field of `small` is in `big` with the same value: what a
/// type wrote back is what it read, less what it does not know.
fn contains(big: &Value, small: &Value) -> bool {
    match (big, small) {
        (Value::Object(big), Value::Object(small)) => small
            .iter()
            .all(|(key, value)| big.get(key).is_some_and(|inner| contains(inner, value))),
        (Value::Array(big), Value::Array(small)) => {
            big.len() == small.len() && big.iter().zip(small).all(|(b, s)| contains(b, s))
        }
        (big, small) => big == small,
    }
}

fn again(about: &str, name: &str, part: &Value, exact: bool) {
    let back = round_trip(name, part)
        .unwrap_or_else(|| panic!("{about}: no type {name}"))
        .unwrap_or_else(|error| panic!("{about}: {name} cannot read it: {error}"));
    assert!(
        contains(part, &back) && (!exact || part == &back),
        "{about}: {name} wrote back {back} for {part}"
    );
}

#[test]
fn every_message_example_reads_and_writes_back() {
    let rows: Map<String, Value> = serde_json::from_str::<Value>(TABLE).unwrap()["methods"]
        .as_array()
        .unwrap()
        .iter()
        .map(|row| (row["method"].as_str().unwrap().to_string(), row.clone()))
        .collect();
    let examples: Value = serde_json::from_str(MESSAGES).unwrap();
    let mut checked = 0;
    for example in examples["examples"].as_array().unwrap() {
        if example["valid"] != true {
            continue;
        }
        let about = example["about"].as_str().unwrap();
        let exact = example["unknownFields"] != true;
        let message = &example["message"];
        let row = |method: &Value, key: &str| {
            method
                .as_str()
                .and_then(|method| rows.get(method))
                .and_then(|row| row[key].as_str())
                .map(type_name)
        };
        if let (Some(name), Some(params)) =
            (row(&message["method"], "params"), message.get("params"))
        {
            again(about, &name, params, exact);
        } else if let Some(error) = message.get("error") {
            again(about, "Error", error, exact);
        } else if let (Some(name), Some(result)) =
            (row(&example["answers"], "result"), message.get("result"))
        {
            again(about, &name, result, exact);
        } else {
            continue;
        }
        checked += 1;
    }
    assert!(checked >= 30, "only {checked} examples were read");
}

#[test]
fn every_manifest_example_reads_and_writes_back() {
    let examples: Value = serde_json::from_str(MANIFESTS).unwrap();
    let mut checked = 0;
    for example in examples["examples"].as_array().unwrap() {
        if example["valid"] != true {
            continue;
        }
        let mut manifest = examples["base"].as_object().unwrap().clone();
        for (key, value) in example["change"].as_object().unwrap() {
            if value.is_null() {
                manifest.remove(key);
            } else {
                manifest.insert(key.clone(), value.clone());
            }
        }
        let about = example["about"].as_str().unwrap();
        again(about, "Manifest", &Value::Object(manifest), false);
        checked += 1;
    }
    assert!(checked >= 5, "only {checked} manifests were read");
}
