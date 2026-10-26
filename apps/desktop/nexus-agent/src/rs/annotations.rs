// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Native Rust port of `apps/desktop/nexus-agent/src/annotations.js`.
//! Reads Antigravity conversation annotations (`annotations/<id>.pbtxt`) to
//! determine which conversations the user marked as archived.

use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

fn is_word_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// Whether an annotation (`archived:true` or `archived: true`) marks its
/// conversation archived. Quoted strings (`"..."` or `'...'`) are skipped so a
/// conversation title containing `archived:true` cannot pass for the field.
/// When multiple `archived` fields appear, the last one wins.
pub fn annotation_is_archived(text: &str) -> bool {
    let chars: Vec<char> = text.chars().collect();
    let len = chars.len();
    let mut i = 0;
    let mut archived = false;
    let keyword: [char; 8] = ['a', 'r', 'c', 'h', 'i', 'v', 'e', 'd'];

    while i < len {
        let c = chars[i];
        // Match double-quoted or single-quoted string: /"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/
        if c == '"' || c == '\'' {
            let quote = c;
            let mut j = i + 1;
            let mut closed = false;
            while j < len {
                if chars[j] == '\\' {
                    if j + 1 < len && chars[j + 1] != '\n' && chars[j + 1] != '\r' {
                        j += 2;
                        continue;
                    } else {
                        break;
                    }
                }
                if chars[j] == '\n' || chars[j] == '\r' {
                    break;
                }
                if chars[j] == quote {
                    i = j + 1;
                    closed = true;
                    break;
                }
                j += 1;
            }
            if closed {
                continue;
            }
            i += 1;
            continue;
        }

        // Check `\barchived\s*:\s*(true|false)\b`
        let word_boundary_before = i == 0 || !is_word_char(chars[i - 1]);
        if word_boundary_before && chars[i..].starts_with(&keyword) {
            let mut j = i + keyword.len();
            while j < len && chars[j].is_whitespace() {
                j += 1;
            }
            if j < len && chars[j] == ':' {
                j += 1;
                while j < len && chars[j].is_whitespace() {
                    j += 1;
                }
                if chars[j..].starts_with(&['t', 'r', 'u', 'e']) {
                    let end = j + 4;
                    if end == len || !is_word_char(chars[end]) {
                        archived = true;
                        i = end;
                        continue;
                    }
                } else if chars[j..].starts_with(&['f', 'a', 'l', 's', 'e']) {
                    let end = j + 5;
                    if end == len || !is_word_char(chars[end]) {
                        archived = false;
                        i = end;
                        continue;
                    }
                }
            }
        }

        i += 1;
    }

    archived
}

/// The conversations marked archived in the `annotations` folder of each of
/// agy's data directories.
pub fn archived_conversation_ids<P: AsRef<Path>>(data_dirs: &[P]) -> BTreeSet<String> {
    let mut archived = BTreeSet::new();
    for dir in data_dirs {
        let annotations_dir = dir.as_ref().join("annotations");
        let Ok(entries) = fs::read_dir(&annotations_dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let file_name = entry.file_name();
            let Some(name) = file_name.to_str() else {
                continue;
            };
            let Some(stem) = name.strip_suffix(".pbtxt") else {
                continue;
            };
            if let Ok(text) = fs::read_to_string(entry.path()) {
                if annotation_is_archived(&text) {
                    archived.insert(stem.to_string());
                }
            }
        }
    }
    archived
}
