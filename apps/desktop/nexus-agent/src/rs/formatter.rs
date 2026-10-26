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

//! Native Rust port of `apps/desktop/nexus-agent/src/formatter.js`.
//! Handles message splitting for Telegram's 4096-character limit and converts
//! standard Markdown into Telegram-compatible HTML.

pub const MAX_MESSAGE_LENGTH: usize = 4096;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FormattedResponse {
    pub text: String,
    pub parse_mode: Option<String>,
}

/// Split a long message into chunks that fit Telegram's 4096-character limit.
pub fn split_message_default(text: &str) -> Vec<String> {
    split_message(text, MAX_MESSAGE_LENGTH)
}

/// Split a long message into chunks that fit `max_len`.
/// Prefers breaking at paragraph boundaries (`\n\n`), then single newlines (`\n`),
/// then spaces (` `), matching `splitMessage` in `formatter.js`.
pub fn split_message(text: &str, max_len: usize) -> Vec<String> {
    let max_len = max_len.max(1);
    if text.len() <= max_len {
        return vec![text.to_string()];
    }

    let mut chunks = Vec::new();
    let mut remaining = text;
    let min_break = (max_len as f64) * 0.3;

    while !remaining.is_empty() {
        if remaining.len() <= max_len {
            chunks.push(remaining.to_string());
            break;
        }

        let mut safe_max = max_len.min(remaining.len());
        while safe_max > 0 && !remaining.is_char_boundary(safe_max) {
            safe_max -= 1;
        }
        let mut break_at = safe_max;

        if let Some(idx) = last_index_of(remaining, "\n\n", safe_max) {
            if (idx as f64) > min_break {
                break_at = idx + 2;
            } else if let Some(nl) = last_index_of(remaining, "\n", safe_max) {
                if (nl as f64) > min_break {
                    break_at = nl + 1;
                } else if let Some(sp) = last_index_of(remaining, " ", safe_max) {
                    if (sp as f64) > min_break {
                        break_at = sp + 1;
                    }
                }
            } else if let Some(sp) = last_index_of(remaining, " ", safe_max) {
                if (sp as f64) > min_break {
                    break_at = sp + 1;
                }
            }
        } else if let Some(nl) = last_index_of(remaining, "\n", safe_max) {
            if (nl as f64) > min_break {
                break_at = nl + 1;
            } else if let Some(sp) = last_index_of(remaining, " ", safe_max) {
                if (sp as f64) > min_break {
                    break_at = sp + 1;
                }
            }
        } else if let Some(sp) = last_index_of(remaining, " ", safe_max) {
            if (sp as f64) > min_break {
                break_at = sp + 1;
            }
        }

        chunks.push(remaining[..break_at].to_string());
        remaining = &remaining[break_at..];
    }

    chunks
}

/// Equivalent to JavaScript `str.lastIndexOf(needle, max_pos)`: finds the last
/// occurrence of `needle` in `haystack` whose starting index is `<= max_pos`.
fn last_index_of(haystack: &str, needle: &str, max_pos: usize) -> Option<usize> {
    let end = (max_pos + needle.len()).min(haystack.len());
    let mut valid_end = end;
    while valid_end > 0 && !haystack.is_char_boundary(valid_end) {
        valid_end -= 1;
    }
    haystack[..valid_end].rfind(needle)
}

/// Escape characters that are special in Telegram HTML (`&`, `<`, `>`).
pub fn escape_html(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn is_table_separator_line(line: &str) -> bool {
    let trimmed = line.trim();
    if !trimmed.starts_with('|') || !trimmed.ends_with('|') || trimmed.len() < 3 {
        return false;
    }
    let inner = &trimmed[1..trimmed.len() - 1];
    !inner.is_empty()
        && inner
            .chars()
            .all(|c| c.is_whitespace() || c == '-' || c == ':' || c == '|')
        && inner.contains('-')
}

fn is_table_row_line(line: &str) -> bool {
    let trimmed = line.trim();
    trimmed.starts_with('|') && trimmed.ends_with('|') && trimmed.len() >= 2
}

/// Convert a markdown table to a fixed-width `<pre>` block for Telegram.
pub fn convert_markdown_table(table_block: &str) -> String {
    let lines: Vec<&str> = table_block.trim().split('\n').collect();
    if lines.len() < 2 {
        return escape_html(table_block);
    }

    let mut rows: Vec<Vec<String>> = Vec::new();
    for line in lines {
        if is_table_separator_line(line) {
            continue;
        }
        let parts: Vec<&str> = line.split('|').collect();
        if parts.len() <= 2 {
            continue;
        }
        // Drop leading empty part before first '|' and trailing empty part after last '|'
        let end = if parts.last().map(|s| s.trim().is_empty()).unwrap_or(false) {
            parts.len() - 1
        } else {
            parts.len()
        };
        let cells: Vec<String> = parts[1..end].iter().map(|c| c.trim().to_string()).collect();
        if !cells.is_empty() {
            rows.push(cells);
        }
    }

    if rows.is_empty() {
        return escape_html(table_block);
    }

    let col_count = rows.iter().map(|r| r.len()).max().unwrap_or(0);
    let mut col_widths = vec![0usize; col_count];
    for row in &rows {
        for (i, cell) in row.iter().enumerate() {
            col_widths[i] = col_widths[i].max(cell.chars().count());
        }
    }

    let mut rendered = Vec::new();
    for (r, cells) in rows.iter().enumerate() {
        let padded: Vec<String> = cells
            .iter()
            .enumerate()
            .map(|(i, cell)| {
                let width = col_widths.get(i).copied().unwrap_or(0);
                let char_len = cell.chars().count();
                if char_len < width {
                    format!("{}{}", cell, " ".repeat(width - char_len))
                } else {
                    cell.clone()
                }
            })
            .collect();
        rendered.push(escape_html(&padded.join(" │ ")));
        if r == 0 {
            let sep: Vec<String> = col_widths.iter().map(|&w| "─".repeat(w)).collect();
            rendered.push(sep.join("─┼─"));
        }
    }

    format!("<pre>{}</pre>", rendered.join("\n"))
}

/// Convert standard markdown (from agy) to Telegram HTML.
pub fn markdown_to_telegram_html(md: &str) -> String {
    // Step 1: Extract and protect fenced code blocks (```lang\ncode```)
    let mut code_blocks: Vec<String> = Vec::new();
    let mut processed = extract_fenced_code_blocks(md, &mut code_blocks);

    // Step 2: Extract and protect inline code (`...`)
    let mut inline_codes: Vec<String> = Vec::new();
    processed = extract_inline_codes(&processed, &mut inline_codes);

    // Step 3: Extract and convert markdown tables
    let mut tables: Vec<String> = Vec::new();
    processed = extract_markdown_tables(&processed, &mut tables);

    // Step 4: Escape HTML in remaining text
    processed = escape_html(&processed);

    // Step 5: Convert markdown syntax to HTML line by line
    let mut converted_lines: Vec<String> = Vec::new();
    for line in processed.split('\n') {
        converted_lines.push(convert_markdown_line(line));
    }
    processed = converted_lines.join("\n");

    // Merge adjacent blockquotes
    processed = processed.replace("</blockquote>\n<blockquote>", "\n");

    // Step 6: Restore protected blocks
    for (idx, block) in code_blocks.iter().enumerate() {
        let token = format!("\x00CODEBLOCK_{}\x00", idx);
        processed = processed.replace(&token, block);
    }
    for (idx, code) in inline_codes.iter().enumerate() {
        let token = format!("\x00INLINE_{}\x00", idx);
        processed = processed.replace(&token, code);
    }
    for (idx, table) in tables.iter().enumerate() {
        let token = format!("\x00TABLE_{}\x00", idx);
        processed = processed.replace(&token, table);
    }

    processed.trim().to_string()
}

fn extract_fenced_code_blocks(input: &str, code_blocks: &mut Vec<String>) -> String {
    let mut out = String::with_capacity(input.len());
    let mut rest = input;

    while let Some(start) = rest.find("```") {
        out.push_str(&rest[..start]);
        let after_ticks = &rest[start + 3..];
        let Some(nl_pos) = after_ticks.find('\n') else {
            out.push_str(&rest[start..]);
            return out;
        };
        let lang = &after_ticks[..nl_pos];
        if !lang.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
            out.push_str("```");
            rest = after_ticks;
            continue;
        }
        let body_and_more = &after_ticks[nl_pos + 1..];
        let Some(end_ticks) = body_and_more.find("```") else {
            out.push_str(&rest[start..]);
            return out;
        };
        let code = &body_and_more[..end_ticks];
        let idx = code_blocks.len();
        let lang_attr = if lang.is_empty() {
            String::new()
        } else {
            format!(" class=\"language-{}\"", escape_html(lang))
        };
        code_blocks.push(format!(
            "<pre><code{}>{}</code></pre>",
            lang_attr,
            escape_html(code.trim_end())
        ));
        out.push_str(&format!("\x00CODEBLOCK_{}\x00", idx));
        rest = &body_and_more[end_ticks + 3..];
    }
    out.push_str(rest);
    out
}

fn extract_inline_codes(input: &str, inline_codes: &mut Vec<String>) -> String {
    let mut out = String::with_capacity(input.len());
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '`' {
            let mut j = i + 1;
            let mut found = None;
            while j < chars.len() && chars[j] != '\n' {
                if chars[j] == '`' {
                    found = Some(j);
                    break;
                }
                j += 1;
            }
            if let Some(close) = found {
                if close > i + 1 {
                    let code: String = chars[i + 1..close].iter().collect();
                    let idx = inline_codes.len();
                    inline_codes.push(format!("<code>{}</code>", escape_html(&code)));
                    out.push_str(&format!("\x00INLINE_{}\x00", idx));
                    i = close + 1;
                    continue;
                }
            }
        }
        out.push(chars[i]);
        i += 1;
    }
    out
}

fn extract_markdown_tables(input: &str, tables: &mut Vec<String>) -> String {
    let lines: Vec<&str> = input.split('\n').collect();
    let mut out_lines: Vec<String> = Vec::new();
    let mut i = 0;
    while i < lines.len() {
        if is_table_row_line(lines[i]) {
            let start = i;
            while i < lines.len() && is_table_row_line(lines[i]) {
                i += 1;
            }
            let block_lines = &lines[start..i];
            if block_lines.len() >= 2 && block_lines.iter().any(|l| is_table_separator_line(l)) {
                let table_block = block_lines.join("\n");
                let idx = tables.len();
                tables.push(convert_markdown_table(&table_block));
                out_lines.push(format!("\x00TABLE_{}\x00", idx));
            } else {
                for l in block_lines {
                    out_lines.push((*l).to_string());
                }
            }
        } else {
            out_lines.push(lines[i].to_string());
            i += 1;
        }
    }
    out_lines.join("\n")
}

fn convert_markdown_line(line: &str) -> String {
    // Horizontal rules: ^[-*_]{3,}$
    if line.len() >= 3 && line.chars().all(|c| c == '-' || c == '*' || c == '_') {
        return "———".to_string();
    }

    // Headers: ^#{1,6}\s+(.+)$
    let hash_count = line.chars().take_while(|&c| c == '#').count();
    if (1..=6).contains(&hash_count) {
        let after_hashes = &line[hash_count..];
        let trimmed = after_hashes.trim_start_matches(|c: char| c == ' ' || c == '\t');
        if trimmed.len() < after_hashes.len() && !trimmed.is_empty() {
            let inner = convert_inline_markdown(trimmed);
            return format!("<b>{}</b>", inner);
        }
    }

    // Blockquotes: ^&gt;\s?(.*)$
    if let Some(after_gt) = line.strip_prefix("&gt;") {
        let content = after_gt.strip_prefix(' ').unwrap_or(after_gt);
        return format!(
            "<blockquote>{}</blockquote>",
            convert_inline_markdown(content)
        );
    }

    let mut working = line.to_string();

    // Nested bullet lists: ^(\s*)[*\-]\s+
    let indent_len = working.chars().take_while(|c| c.is_whitespace()).count();
    let indent_bytes: usize = working.chars().take(indent_len).map(|c| c.len_utf8()).sum();
    let after_indent = &working[indent_bytes..];
    if after_indent.starts_with("* ")
        || after_indent.starts_with("- ")
        || after_indent.starts_with("*\t")
        || after_indent.starts_with("-\t")
    {
        let rest = after_indent[1..].trim_start();
        let depth = indent_len / 2;
        let bullets = ["•", "◦", "▪", "▸"];
        let bullet = bullets[depth.min(bullets.len() - 1)];
        working = format!("{}{} {}", "  ".repeat(depth), bullet, rest);
    } else {
        // Numbered lists: ^(\s*)\d+\.\s+
        let digits_len = after_indent
            .chars()
            .take_while(|c| c.is_ascii_digit())
            .count();
        if digits_len > 0 {
            let after_digits = &after_indent[digits_len..];
            if let Some(after_dot) = after_digits.strip_prefix('.') {
                let rest = after_dot.trim_start();
                if rest.len() < after_dot.len() {
                    let depth = indent_len / 2;
                    let num = &after_indent[..digits_len];
                    working = format!("{}{}. {}", "  ".repeat(depth), num, rest);
                }
            }
        }
    }

    convert_inline_markdown(&working)
}

fn convert_inline_markdown(input: &str) -> String {
    let mut s = input.to_string();
    // Bold: **text** or __text__
    s = replace_delimited(&s, "**", "<b>", "</b>");
    s = replace_delimited(&s, "__", "<b>", "</b>");
    // Italic: (?<!\w)*text*(?!\w) and (?<!\w)_text_(?!\w)
    s = replace_single_delimited(&s, '*', "<i>", "</i>");
    s = replace_single_delimited(&s, '_', "<i>", "</i>");
    // Strikethrough: ~~text~~
    s = replace_delimited(&s, "~~", "<s>", "</s>");
    // Links: [text](url)
    s = replace_markdown_links(&s);
    s
}

fn replace_delimited(input: &str, delim: &str, open_tag: &str, close_tag: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut rest = input;
    while let Some(start) = rest.find(delim) {
        out.push_str(&rest[..start]);
        let after_open = &rest[start + delim.len()..];
        if let Some(end) = after_open.find(delim) {
            if end > 0 {
                out.push_str(open_tag);
                out.push_str(&after_open[..end]);
                out.push_str(close_tag);
                rest = &after_open[end + delim.len()..];
                continue;
            }
        }
        out.push_str(delim);
        rest = after_open;
    }
    out.push_str(rest);
    out
}

fn is_word_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

fn replace_single_delimited(input: &str, delim: char, open_tag: &str, close_tag: &str) -> String {
    let chars: Vec<char> = input.chars().collect();
    let mut out = String::with_capacity(input.len());
    let mut i = 0;
    while i < chars.len() {
        let prev_is_word = i > 0 && is_word_char(chars[i - 1]);
        if chars[i] == delim && !prev_is_word {
            let mut j = i + 1;
            let mut found = None;
            while j < chars.len() && chars[j] != '\n' && chars[j] != delim {
                j += 1;
            }
            if j < chars.len() && chars[j] == delim && j > i + 1 {
                let next_is_word = j + 1 < chars.len() && is_word_char(chars[j + 1]);
                if !next_is_word {
                    found = Some(j);
                }
            }
            if let Some(close) = found {
                let inner: String = chars[i + 1..close].iter().collect();
                out.push_str(open_tag);
                out.push_str(&inner);
                out.push_str(close_tag);
                i = close + 1;
                continue;
            }
        }
        out.push(chars[i]);
        i += 1;
    }
    out
}

fn replace_markdown_links(input: &str) -> String {
    let chars: Vec<char> = input.chars().collect();
    let mut out = String::with_capacity(input.len());
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '[' {
            let mut j = i + 1;
            while j < chars.len() && chars[j] != ']' {
                j += 1;
            }
            if j > i + 1 && j + 1 < chars.len() && chars[j + 1] == '(' {
                let mut k = j + 2;
                while k < chars.len() && chars[k] != ')' {
                    k += 1;
                }
                if k > j + 2 && k < chars.len() {
                    let text: String = chars[i + 1..j].iter().collect();
                    let url: String = chars[j + 2..k].iter().collect();
                    out.push_str(&format!("<a href=\"{}\">{}</a>", url, text));
                    i = k + 1;
                    continue;
                }
            }
        }
        out.push(chars[i]);
        i += 1;
    }
    out
}

/// Format response for Telegram with HTML rendering.
/// Total function (never panics or fails on arbitrary input).
pub fn format_response(text: &str) -> FormattedResponse {
    let html = markdown_to_telegram_html(text);
    FormattedResponse {
        text: html,
        parse_mode: Some("HTML".to_string()),
    }
}
