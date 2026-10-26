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

//! Native Rust port of `apps/desktop/nexus-agent/src/formatter.test.js`.

use nexus_agent_src_lib::formatter::{
    format_response, markdown_to_telegram_html, split_message, split_message_default,
};

// ─── splitMessage ────────────────────────────────────────────────────────────

#[test]
fn split_message_returns_single_chunk_when_under_limit() {
    assert_eq!(
        split_message_default("hello world"),
        vec!["hello world".to_string()]
    );
}

#[test]
fn split_message_splits_long_text_into_chunks_that_each_fit_limit() {
    let text = "a".repeat(50);
    let chunks = split_message(&text, 10);
    assert!(chunks.len() > 1, "should split");
    for c in &chunks {
        assert!(c.len() <= 10, "chunk of {} exceeds 10", c.len());
    }
    assert_eq!(chunks.join(""), text, "chunks reassemble to the original");
}

#[test]
fn split_message_prefers_paragraph_double_newline_boundary() {
    let para1 = "x".repeat(60);
    let para2 = "y".repeat(60);
    let combined = format!("{}\n\n{}", para1, para2);
    let chunks = split_message(&combined, 100);
    assert_eq!(
        chunks[0],
        format!("{}\n\n", para1),
        "breaks after the double newline"
    );
}

#[test]
fn split_message_falls_back_to_space_boundary_when_no_newline_fits() {
    let input = "word ".repeat(30).trim().to_string();
    let chunks = split_message(&input, 20);
    for c in &chunks {
        assert!(c.len() <= 20);
    }
    assert!(chunks.iter().skip(1).all(|c| !c.starts_with(' ')));
}

// ─── markdownToTelegramHtml ──────────────────────────────────────────────────

#[test]
fn markdown_to_telegram_html_converts_bold_and_italic() {
    assert_eq!(markdown_to_telegram_html("**bold**"), "<b>bold</b>");
    assert_eq!(markdown_to_telegram_html("__bold__"), "<b>bold</b>");
    assert_eq!(markdown_to_telegram_html("*italic*"), "<i>italic</i>");
}

#[test]
fn markdown_to_telegram_html_escapes_html_metacharacters_in_plain_text() {
    assert_eq!(
        markdown_to_telegram_html("a < b & c > d"),
        "a &lt; b &amp; c &gt; d"
    );
}

#[test]
fn markdown_to_telegram_html_converts_links() {
    assert_eq!(
        markdown_to_telegram_html("[docs](https://example.com)"),
        "<a href=\"https://example.com\">docs</a>"
    );
}

#[test]
fn markdown_to_telegram_html_protects_inline_code_and_escapes_inside_it() {
    assert_eq!(
        markdown_to_telegram_html("`a < b`"),
        "<code>a &lt; b</code>"
    );
}

#[test]
fn markdown_to_telegram_html_renders_fenced_code_blocks_with_language_class() {
    let out = markdown_to_telegram_html("```js\nconst x = 1 < 2;\n```");
    assert!(out.starts_with("<pre><code class=\"language-js\">"));
    assert!(
        out.contains("const x = 1 &lt; 2;"),
        "code contents are html-escaped"
    );
}

#[test]
fn markdown_to_telegram_html_converts_headings_to_bold() {
    assert_eq!(markdown_to_telegram_html("## Title"), "<b>Title</b>");
}

// ─── formatResponse ──────────────────────────────────────────────────────────

#[test]
fn format_response_returns_html_parse_mode_for_convertible_markdown() {
    let r = format_response("**hi**");
    assert_eq!(r.parse_mode.as_deref(), Some("HTML"));
    assert_eq!(r.text, "<b>hi</b>");
}

#[test]
fn format_response_is_total_function_on_arbitrary_input() {
    let r = format_response("```unterminated");
    assert_eq!(r.parse_mode.as_deref(), Some("HTML"));
    assert!(r.text.contains("unterminated"));
}
