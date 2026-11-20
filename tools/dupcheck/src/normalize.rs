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

//! Source file eligibility, meaningful-line normalization, and 12-line block hashing.

pub const BLOCK_SIZE: usize = 12;

const EXTENSIONS: &[&str] = &[
    ".rs", ".swift", ".kt", ".go", ".ts", ".tsx", ".js", ".mjs", ".py", ".sh",
];

const SKIP_SUBSTRINGS: &[&str] = &[
    "third_party/",
    "node_modules/",
    "/testdata/",
    "/generated/",
    "/vendor/",
    "Localizations/",
];

const SKIP_SUFFIXES: &[&str] = &["_pb.go", ".pb.go", ".d.ts"];

const DROP_PREFIXES: &[&str] = &[
    "//", "#", "*", "/*", "import ", "use ", "package ", "}", "{", ")", "@",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MeaningfulLine {
    pub line_no: usize,
    pub text: String,
}

pub fn is_eligible_source(path: &str) -> bool {
    if !EXTENSIONS.iter().any(|ext| path.ends_with(ext)) {
        return false;
    }
    if SKIP_SUBSTRINGS.iter().any(|part| path.contains(part)) {
        return false;
    }
    if SKIP_SUFFIXES.iter().any(|sfx| path.ends_with(sfx)) {
        return false;
    }
    true
}

pub fn normalize_lines(content: &str) -> Vec<MeaningfulLine> {
    let mut out = Vec::new();
    for (idx, raw) in content.lines().enumerate() {
        let trimmed = raw.trim();
        if trimmed.chars().count() < 4 {
            continue;
        }
        if DROP_PREFIXES.iter().any(|pre| trimmed.starts_with(pre)) {
            continue;
        }
        out.push(MeaningfulLine {
            line_no: idx + 1,
            text: trimmed.to_string(),
        });
    }
    out
}

pub fn hash_block(lines: &[MeaningfulLine]) -> u128 {
    const FNV_OFFSET: u128 = 0x6c62_272e_07bb_0142_62b8_2175_6295_c58d;
    const FNV_PRIME: u128 = 0x0000_0000_0100_0000_0000_0000_0000_013b;

    let mut hash = FNV_OFFSET;
    for (i, line) in lines.iter().enumerate() {
        if i > 0 {
            hash ^= b'\n' as u128;
            hash = hash.wrapping_mul(FNV_PRIME);
        }
        for &b in line.text.as_bytes() {
            hash ^= b as u128;
            hash = hash.wrapping_mul(FNV_PRIME);
        }
    }
    hash
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eligibility_filters_extensions_and_excluded_paths() {
        for p in [
            "a.rs",
            "a/b.swift",
            "a/b.kt",
            "a/b.go",
            "a/b.ts",
            "a/b.tsx",
            "a/b.js",
            "a/b.mjs",
            "a/b.py",
            "a/b.sh",
        ] {
            assert!(is_eligible_source(p), "expected eligible: {p}");
        }
        for p in [
            "README.md",
            "BUILD",
            "third_party/foo/a.rs",
            "apps/web/node_modules/x/a.ts",
            "tools/x/testdata/a.rs",
            "apps/x/generated/a.swift",
            "apps/x/vendor/a.go",
            "apps/mac/Localizations/a.swift",
            "proto/foo_pb.go",
            "proto/foo.pb.go",
            "types/index.d.ts",
        ] {
            assert!(!is_eligible_source(p), "expected ineligible: {p}");
        }
    }

    #[test]
    fn normalize_drops_noise_and_keeps_original_line_numbers() {
        let src = "\
// Copyright 2026
# python comment
/* block start
 * block middle
import foo from 'bar';
use std::collections::HashMap;
package main
@Decorator
{
}
)
x=1

    let alpha = 100;
    let beta = 200;
";
        let norm = normalize_lines(src);
        assert_eq!(
            norm,
            vec![
                MeaningfulLine {
                    line_no: 14,
                    text: "let alpha = 100;".to_string(),
                },
                MeaningfulLine {
                    line_no: 15,
                    text: "let beta = 200;".to_string(),
                },
            ]
        );
    }

    #[test]
    fn block_hash_matches_identical_content_and_distinguishes_line_breaks() {
        let mk = |items: &[&str]| -> Vec<MeaningfulLine> {
            items
                .iter()
                .enumerate()
                .map(|(i, s)| MeaningfulLine {
                    line_no: i + 10,
                    text: (*s).to_string(),
                })
                .collect()
        };
        let a = mk(&[
            "let v1 = 1;",
            "let v2 = 2;",
            "let v3 = 3;",
            "let v4 = 4;",
            "let v5 = 5;",
            "let v6 = 6;",
            "let v7 = 7;",
            "let v8 = 8;",
            "let v9 = 9;",
            "let v10 = 10;",
            "let v11 = 11;",
            "let v12 = 12;",
        ]);
        let mut a_shifted_lines = a.clone();
        for item in &mut a_shifted_lines {
            item.line_no += 100;
        }
        assert_eq!(hash_block(&a), hash_block(&a_shifted_lines));

        let b = mk(&[
            "let v1 = 1;",
            "let v2 = 2;",
            "let v3 = 3;",
            "let v4 = 4;",
            "let v5 = 5;",
            "let v6 = 6;",
            "let v7 = 7;",
            "let v8 = 8;",
            "let v9 = 9;",
            "let v10 = 10;",
            "let v11 = 11;",
            "let v12 = 99;",
        ]);
        assert_ne!(hash_block(&a), hash_block(&b));
    }
}
