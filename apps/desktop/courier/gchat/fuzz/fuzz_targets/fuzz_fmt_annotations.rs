// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use gchat_ffi::fuzz_tests::{fuzz_fmt_annotations_once, Xorshift64};

#[test]
fn fuzz_fmt_annotations_never_splits_surrogate_pairs_or_panics() {
    let seeds: &[&str] = &[
        "",
        "Hello 👋🏼🇵🇱👨‍👩‍👧‍👦 *bold* _italic_ ~strike~ `code`",
        "<b>bold <i>italic <s>strike</s></i></b> <a href=\"https://matrix.to/#/@gchat_112233445566778899001:courier.local\">Alice</a>",
        "<b>unclosed <i>tags <a href=\"javascript:alert(1)\">click</a> <font color=\"#123456\">c</font>",
        "<pre><code>fn main() {}</code></pre><blockquote>quoted\nline 2</blockquote>",
        "<ul><li>item 1</li><li>item 2</li></ul><ol><li>one</li></ol>",
    ];
    for seed in seeds {
        assert!(
            fuzz_fmt_annotations_once(seed.as_bytes()),
            "fuzz_fmt_annotations_once failed on seed {:?}",
            seed
        );
    }

    let mut rng = Xorshift64::new(0xFACE_CAFE_1122_3344);
    for _ in 0..500 {
        let buf = rng.next_bytes(256);
        assert!(fuzz_fmt_annotations_once(&buf));
    }
}
