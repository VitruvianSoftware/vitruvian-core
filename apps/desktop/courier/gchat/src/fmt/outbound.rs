// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::pb;
use crate::GChatError;

pub const MAX_OUTBOUND_TEXT_CHARS: usize = 4096;

/// Holds the converted outbound plain text and its prost-encoded `googlechat::Annotation`
/// entries. Note: `pb::Annotation` is prost-generated without `serde` derives; across the C FFI
/// boundary (`ffi.rs`), each annotation is serialized as standard base64-encoded protobuf wire bytes.
#[derive(Debug, Clone, PartialEq)]
pub struct OutboundFormattedMessage {
    pub text: String,
    pub annotations: Vec<pb::Annotation>,
}

#[derive(Debug, Clone)]
enum HtmlToken {
    Text(String),
    OpenTag {
        name: String,
        attrs: Vec<(String, String)>,
        self_closing: bool,
    },
    CloseTag(String),
}

#[derive(Debug, Clone)]
enum OpenKind {
    Format {
        format_type: pb::format_metadata::FormatType,
        font_color: Option<i32>,
    },
    Pre,
    Link(String),
    UserMention {
        gaia_id: String,
        checked_at_prefix: bool,
    },
    Blockquote,
    UnorderedList,
    OrderedList {
        next_index: usize,
    },
    ListItem,
    Paragraph,
    NoOp,
}

#[derive(Debug, Clone)]
struct OpenElement {
    tag: String,
    start_utf16: i32,
    order: usize,
    kind: OpenKind,
}

pub fn unescape_html(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let bytes = input.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'&' {
            if let Some(rel_semi) = bytes[i + 1..].iter().position(|&b| b == b';') {
                let end = i + 1 + rel_semi;
                if end - (i + 1) <= 12 {
                    let entity = &input[i + 1..end];
                    let decoded = match entity {
                        "amp" => Some('&'),
                        "lt" => Some('<'),
                        "gt" => Some('>'),
                        "quot" => Some('"'),
                        "apos" => Some('\''),
                        "nbsp" => Some('\u{00A0}'),
                        _ if entity.starts_with("#x") || entity.starts_with("#X") => {
                            u32::from_str_radix(&entity[2..], 16)
                                .ok()
                                .and_then(char::from_u32)
                        }
                        _ if entity.starts_with('#') => {
                            entity[1..].parse::<u32>().ok().and_then(char::from_u32)
                        }
                        _ => None,
                    };
                    if let Some(ch) = decoded {
                        out.push(ch);
                        i = end + 1;
                        continue;
                    }
                }
            }
        }
        let ch = input[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

fn parse_tag_attrs(raw: &str) -> (String, Vec<(String, String)>, bool) {
    let trimmed = raw.trim();
    let (inner, self_closing) = if let Some(stripped) = trimmed.strip_suffix('/') {
        (stripped.trim_end(), true)
    } else {
        (trimmed, false)
    };

    let mut chars = inner.char_indices().peekable();
    let mut name_end = inner.len();
    for (idx, ch) in chars.by_ref() {
        if ch.is_ascii_whitespace() || ch == '/' {
            name_end = idx;
            break;
        }
    }
    let tag_name = inner[..name_end].to_ascii_lowercase();
    let mut rest = inner[name_end..].trim_start();
    let mut attrs = Vec::new();

    while !rest.is_empty() {
        let eq_or_ws = rest.find(|c: char| c == '=' || c.is_ascii_whitespace());
        match eq_or_ws {
            None => {
                attrs.push((rest.to_ascii_lowercase(), String::new()));
                break;
            }
            Some(pos) => {
                let attr_name = rest[..pos].trim().to_ascii_lowercase();
                let after_name = rest[pos..].trim_start();
                if let Some(after_eq) = after_name.strip_prefix('=') {
                    let val_start = after_eq.trim_start();
                    if let Some(quoted) = val_start.strip_prefix('"') {
                        if let Some(end_q) = quoted.find('"') {
                            attrs.push((attr_name, unescape_html(&quoted[..end_q])));
                            rest = quoted[end_q + 1..].trim_start();
                        } else {
                            attrs.push((attr_name, unescape_html(quoted)));
                            break;
                        }
                    } else if let Some(quoted) = val_start.strip_prefix('\'') {
                        if let Some(end_q) = quoted.find('\'') {
                            attrs.push((attr_name, unescape_html(&quoted[..end_q])));
                            rest = quoted[end_q + 1..].trim_start();
                        } else {
                            attrs.push((attr_name, unescape_html(quoted)));
                            break;
                        }
                    } else {
                        let end_val = val_start
                            .find(|c: char| c.is_ascii_whitespace())
                            .unwrap_or(val_start.len());
                        attrs.push((attr_name, unescape_html(&val_start[..end_val])));
                        rest = val_start[end_val..].trim_start();
                    }
                } else {
                    if !attr_name.is_empty() {
                        attrs.push((attr_name, String::new()));
                    }
                    rest = after_name;
                }
            }
        }
    }

    (tag_name, attrs, self_closing)
}

fn tokenize_html(html: &str) -> Vec<HtmlToken> {
    let mut tokens = Vec::new();
    let mut i = 0;
    let bytes = html.as_bytes();

    while i < bytes.len() {
        if bytes[i] == b'<' {
            if html[i..].starts_with("<!--") {
                if let Some(end_comment) = html[i + 4..].find("-->") {
                    i += 4 + end_comment + 3;
                } else {
                    break;
                }
                continue;
            }
            // Find matching '>' outside quotes.
            let mut j = i + 1;
            let mut in_quote: Option<u8> = None;
            while j < bytes.len() {
                let b = bytes[j];
                if let Some(q) = in_quote {
                    if b == q {
                        in_quote = None;
                    }
                } else if b == b'"' || b == b'\'' {
                    in_quote = Some(b);
                } else if b == b'>' {
                    break;
                }
                j += 1;
            }
            if j < bytes.len() && bytes[j] == b'>' {
                let tag_body = html[i + 1..j].trim();
                if let Some(close_name) = tag_body.strip_prefix('/') {
                    let clean_name = close_name
                        .split_whitespace()
                        .next()
                        .unwrap_or("")
                        .to_ascii_lowercase();
                    if !clean_name.is_empty() {
                        tokens.push(HtmlToken::CloseTag(clean_name));
                    }
                } else if !tag_body.is_empty() && !tag_body.starts_with('!') {
                    let (name, attrs, self_closing) = parse_tag_attrs(tag_body);
                    if !name.is_empty() {
                        tokens.push(HtmlToken::OpenTag {
                            name,
                            attrs,
                            self_closing,
                        });
                    }
                }
                i = j + 1;
                continue;
            }
        }

        let next_lt = html[i..]
            .find('<')
            .map(|off| i + off)
            .unwrap_or(bytes.len());
        let raw_text = &html[i..next_lt];
        if !raw_text.is_empty() {
            tokens.push(HtmlToken::Text(unescape_html(raw_text)));
        }
        i = next_lt;
    }

    tokens
}

fn parse_hex_color(raw: &str) -> Option<i32> {
    let hex = raw.trim().strip_prefix('#')?;
    match hex.len() {
        6 => {
            let rgb = u32::from_str_radix(hex, 16).ok()?;
            Some((0xFF00_0000u32 | rgb) as i32)
        }
        8 => {
            let argb = u32::from_str_radix(hex, 16).ok()?;
            Some(argb as i32)
        }
        _ => None,
    }
}

fn extract_gchat_user_id_from_matrix_to(href: &str) -> Option<String> {
    let trimmed = href.trim();
    let after_hash = trimmed.strip_prefix("https://matrix.to/#/")?;
    let mxid = after_hash.split('?').next().unwrap_or(after_hash);
    let after_prefix = mxid.strip_prefix("@gchat_")?;
    let localpart = after_prefix.split(':').next()?;
    if localpart.is_empty() {
        return None;
    }
    Some(localpart.to_string())
}

fn is_mention_boundary_char(ch: Option<char>) -> bool {
    match ch {
        None => true,
        Some(c) => !c.is_alphanumeric() && c != '_',
    }
}

struct OutboundBuilder {
    text: String,
    utf16_len: i32,
    annotations: Vec<(usize, pb::Annotation)>,
    next_order: usize,
    stack: Vec<OpenElement>,
    allow_mention_all: bool,
}

impl OutboundBuilder {
    fn new(allow_mention_all: bool) -> Self {
        Self {
            text: String::new(),
            utf16_len: 0,
            annotations: Vec::new(),
            next_order: 0,
            stack: Vec::new(),
            allow_mention_all,
        }
    }

    fn alloc_order(&mut self) -> usize {
        let ord = self.next_order;
        self.next_order += 1;
        ord
    }

    fn push_raw(&mut self, s: &str) {
        if s.is_empty() {
            return;
        }
        self.text.push_str(s);
        self.utf16_len += s.encode_utf16().count() as i32;
    }

    fn ensure_newline(&mut self) {
        if !self.text.is_empty() && !self.text.ends_with('\n') {
            self.push_raw("\n");
        }
    }

    fn in_code_or_pre(&self) -> bool {
        self.stack.iter().any(|e| {
            matches!(
                e.kind,
                OpenKind::Pre
                    | OpenKind::Format {
                        format_type: pb::format_metadata::FormatType::Monospace,
                        ..
                    }
            )
        })
    }

    fn in_user_mention(&self) -> bool {
        self.stack
            .iter()
            .any(|e| matches!(e.kind, OpenKind::UserMention { .. }))
    }

    fn blockquote_depth(&self) -> usize {
        self.stack
            .iter()
            .filter(|e| matches!(e.kind, OpenKind::Blockquote))
            .count()
    }

    fn push_segment_with_mention_all(&mut self, segment: &str) {
        if segment.is_empty() {
            return;
        }
        if !self.allow_mention_all || self.in_code_or_pre() || self.in_user_mention() {
            self.push_raw(segment);
            return;
        }

        let mut cursor = 0;
        while cursor < segment.len() {
            let Some(rel_at) = segment[cursor..].find('@') else {
                self.push_raw(&segment[cursor..]);
                break;
            };
            let at_idx = cursor + rel_at;
            let prev_char = segment[..at_idx].chars().next_back();
            let after_at = &segment[at_idx + 1..];

            let matched_kw = if after_at.starts_with("all") {
                Some("all")
            } else if after_at.starts_with("room") {
                Some("room")
            } else {
                None
            };

            if let Some(kw) = matched_kw {
                let after_kw_idx = at_idx + 1 + kw.len();
                let next_char = segment[after_kw_idx..].chars().next();
                if is_mention_boundary_char(prev_char) && is_mention_boundary_char(next_char) {
                    self.push_raw(&segment[cursor..at_idx]);
                    let start = self.utf16_len;
                    self.push_raw("@all");
                    let ord = self.alloc_order();
                    self.annotations.push((
                        ord,
                        pb::Annotation {
                            r#type: Some(pb::AnnotationType::UserMention as i32),
                            start_index: Some(start),
                            length: Some(4),
                            chip_render_type: Some(
                                pb::annotation::ChipRenderType::DoNotRender as i32,
                            ),
                            metadata: Some(pb::annotation::Metadata::UserMentionMetadata(
                                pb::UserMentionMetadata {
                                    r#type: Some(
                                        pb::user_mention_metadata::Type::MentionAll as i32,
                                    ),
                                    ..Default::default()
                                },
                            )),
                            ..Default::default()
                        },
                    ));
                    cursor = after_kw_idx;
                    continue;
                }
            }

            // Advance past '@'
            self.push_raw(&segment[cursor..=at_idx]);
            cursor = at_idx + 1;
        }
    }

    fn push_text(&mut self, text: &str) {
        if text.is_empty() {
            return;
        }

        // If inside a user mention whose '@' prefix hasn't been checked yet, ensure it starts with '@'.
        let mut need_at = false;
        for elem in self.stack.iter_mut().rev() {
            if let OpenKind::UserMention {
                checked_at_prefix, ..
            } = &mut elem.kind
            {
                if !*checked_at_prefix {
                    *checked_at_prefix = true;
                    if !text.starts_with('@') {
                        need_at = true;
                    }
                }
                break;
            }
        }
        if need_at {
            self.push_raw("@");
        }

        let bq_depth = self.blockquote_depth();
        if bq_depth > 0 && text.contains('\n') {
            let prefix = "> ".repeat(bq_depth);
            for (idx, line) in text.split('\n').enumerate() {
                if idx > 0 {
                    self.push_raw("\n");
                    self.push_raw(&prefix);
                }
                self.push_segment_with_mention_all(line);
            }
        } else {
            self.push_segment_with_mention_all(text);
        }
    }

    fn handle_open_tag(&mut self, name: String, attrs: Vec<(String, String)>, self_closing: bool) {
        match name.as_str() {
            "br" => {
                let bq_depth = self.blockquote_depth();
                self.push_raw("\n");
                if bq_depth > 0 {
                    self.push_raw(&"> ".repeat(bq_depth));
                }
                return;
            }
            "hr" => {
                self.ensure_newline();
                self.push_raw("---\n");
                return;
            }
            "img" => {
                if let Some((_, alt)) = attrs.iter().find(|(k, _)| k == "alt") {
                    self.push_text(alt);
                }
                return;
            }
            _ => {}
        }

        let kind = match name.as_str() {
            "b" | "strong" => OpenKind::Format {
                format_type: pb::format_metadata::FormatType::Bold,
                font_color: None,
            },
            "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => {
                self.ensure_newline();
                OpenKind::Format {
                    format_type: pb::format_metadata::FormatType::Bold,
                    font_color: None,
                }
            }
            "i" | "em" => OpenKind::Format {
                format_type: pb::format_metadata::FormatType::Italic,
                font_color: None,
            },
            "s" | "del" | "strike" => OpenKind::Format {
                format_type: pb::format_metadata::FormatType::Strike,
                font_color: None,
            },
            "u" | "ins" => OpenKind::Format {
                format_type: pb::format_metadata::FormatType::Underline,
                font_color: None,
            },
            "pre" => OpenKind::Pre,
            "code" => {
                if self.stack.iter().any(|e| matches!(e.kind, OpenKind::Pre)) {
                    OpenKind::NoOp
                } else {
                    OpenKind::Format {
                        format_type: pb::format_metadata::FormatType::Monospace,
                        font_color: None,
                    }
                }
            }
            "span" | "font" => {
                let color_attr = attrs
                    .iter()
                    .find(|(k, _)| k == "data-mx-color" || k == "color")
                    .and_then(|(_, v)| parse_hex_color(v));
                if let Some(c) = color_attr {
                    OpenKind::Format {
                        format_type: pb::format_metadata::FormatType::FontColor,
                        font_color: Some(c),
                    }
                } else {
                    OpenKind::NoOp
                }
            }
            "a" => {
                let href = attrs
                    .iter()
                    .find(|(k, _)| k == "href")
                    .map(|(_, v)| v.trim().to_string())
                    .unwrap_or_default();
                if let Some(gaia_id) = extract_gchat_user_id_from_matrix_to(&href) {
                    OpenKind::UserMention {
                        gaia_id,
                        checked_at_prefix: false,
                    }
                } else if !href.is_empty() {
                    OpenKind::Link(href)
                } else {
                    OpenKind::NoOp
                }
            }
            "blockquote" => {
                self.ensure_newline();
                let depth = self.blockquote_depth() + 1;
                self.push_raw(&"> ".repeat(depth));
                OpenKind::Blockquote
            }
            "ul" => OpenKind::UnorderedList,
            "ol" => {
                let start = attrs
                    .iter()
                    .find(|(k, _)| k == "start")
                    .and_then(|(_, v)| v.trim().parse::<usize>().ok())
                    .unwrap_or(1);
                OpenKind::OrderedList { next_index: start }
            }
            "li" => {
                self.ensure_newline();
                let mut prefix = "• ".to_string();
                for elem in self.stack.iter_mut().rev() {
                    match &mut elem.kind {
                        OpenKind::UnorderedList => {
                            prefix = "• ".to_string();
                            break;
                        }
                        OpenKind::OrderedList { next_index } => {
                            prefix = format!("{}. ", *next_index);
                            *next_index += 1;
                            break;
                        }
                        _ => {}
                    }
                }
                self.push_raw(&prefix);
                OpenKind::ListItem
            }
            "p" | "div" => {
                self.ensure_newline();
                OpenKind::Paragraph
            }
            _ => OpenKind::NoOp,
        };

        let start_utf16 = self.utf16_len;
        let order = self.alloc_order();
        let elem = OpenElement {
            tag: name,
            start_utf16,
            order,
            kind,
        };
        if self_closing {
            self.finish_element(elem);
        } else {
            self.stack.push(elem);
        }
    }

    fn handle_close_tag(&mut self, name: &str) {
        if let Some(pos) = self.stack.iter().rposition(|e| e.tag == name) {
            let elem = self.stack.remove(pos);
            self.finish_element(elem);
        }
    }

    fn finish_element(&mut self, elem: OpenElement) {
        match elem.kind {
            OpenKind::Format {
                format_type,
                font_color,
            } => {
                let len = self.utf16_len - elem.start_utf16;
                if len > 0 {
                    self.annotations.push((
                        elem.order,
                        pb::Annotation {
                            r#type: Some(pb::AnnotationType::FormatData as i32),
                            start_index: Some(elem.start_utf16),
                            length: Some(len),
                            chip_render_type: Some(
                                pb::annotation::ChipRenderType::DoNotRender as i32,
                            ),
                            metadata: Some(pb::annotation::Metadata::FormatMetadata(
                                pb::FormatMetadata {
                                    format_type: Some(format_type as i32),
                                    font_color,
                                    ..Default::default()
                                },
                            )),
                            ..Default::default()
                        },
                    ));
                }
            }
            OpenKind::Pre => {
                if self.text.ends_with('\n') && self.utf16_len > elem.start_utf16 {
                    self.text.pop();
                    self.utf16_len -= 1;
                }
                let len = self.utf16_len - elem.start_utf16;
                if len > 0 {
                    self.annotations.push((
                        elem.order,
                        pb::Annotation {
                            r#type: Some(pb::AnnotationType::FormatData as i32),
                            start_index: Some(elem.start_utf16),
                            length: Some(len),
                            chip_render_type: Some(
                                pb::annotation::ChipRenderType::DoNotRender as i32,
                            ),
                            metadata: Some(pb::annotation::Metadata::FormatMetadata(
                                pb::FormatMetadata {
                                    format_type: Some(
                                        pb::format_metadata::FormatType::MonospaceBlock as i32,
                                    ),
                                    ..Default::default()
                                },
                            )),
                            ..Default::default()
                        },
                    ));
                }
            }
            OpenKind::Link(url) => {
                let len = self.utf16_len - elem.start_utf16;
                if len > 0 {
                    self.annotations.push((
                        elem.order,
                        pb::Annotation {
                            r#type: Some(pb::AnnotationType::Url as i32),
                            start_index: Some(elem.start_utf16),
                            length: Some(len),
                            chip_render_type: Some(
                                pb::annotation::ChipRenderType::DoNotRender as i32,
                            ),
                            metadata: Some(pb::annotation::Metadata::UrlMetadata(
                                pb::UrlMetadata {
                                    url: Some(pb::Url { url: Some(url) }),
                                    ..Default::default()
                                },
                            )),
                            ..Default::default()
                        },
                    ));
                }
            }
            OpenKind::UserMention { gaia_id, .. } => {
                let len = self.utf16_len - elem.start_utf16;
                if len > 0 {
                    self.annotations.push((
                        elem.order,
                        pb::Annotation {
                            r#type: Some(pb::AnnotationType::UserMention as i32),
                            start_index: Some(elem.start_utf16),
                            length: Some(len),
                            chip_render_type: Some(
                                pb::annotation::ChipRenderType::DoNotRender as i32,
                            ),
                            metadata: Some(pb::annotation::Metadata::UserMentionMetadata(
                                pb::UserMentionMetadata {
                                    id: Some(pb::UserId {
                                        id: Some(gaia_id),
                                        r#type: Some(pb::UserType::Human as i32),
                                    }),
                                    r#type: Some(pb::user_mention_metadata::Type::Mention as i32),
                                    ..Default::default()
                                },
                            )),
                            ..Default::default()
                        },
                    ));
                }
            }
            OpenKind::Blockquote => {
                self.ensure_newline();
            }
            OpenKind::UnorderedList
            | OpenKind::OrderedList { .. }
            | OpenKind::ListItem
            | OpenKind::Paragraph
            | OpenKind::NoOp => {}
        }
    }

    fn finish(mut self) -> OutboundFormattedMessage {
        while let Some(elem) = self.stack.pop() {
            self.finish_element(elem);
        }
        self.annotations.sort_by_key(|(ord, _)| *ord);
        let annotations = self.annotations.into_iter().map(|(_, ann)| ann).collect();
        OutboundFormattedMessage {
            text: self.text,
            annotations,
        }
    }
}

/// Converts Matrix HTML (or plain text when `formatted_body` is `None`/empty) into Google Chat
/// plain text and UTF-16 `Annotation` spans. User mentions are extracted directly from Matrix
/// `https://matrix.to/#/@gchat_<gaia_id>:...` anchor `href` attributes rather than a separate
/// `mention_map` parameter, and returns `Result<OutboundFormattedMessage, GChatError>`.
pub fn matrix_html_to_annotations(
    plain_body: &str,
    formatted_body: Option<&str>,
    allow_mention_all: bool,
) -> Result<OutboundFormattedMessage, GChatError> {
    let mut builder = OutboundBuilder::new(allow_mention_all);
    match formatted_body.filter(|s| !s.is_empty()) {
        Some(html) => {
            for token in tokenize_html(html) {
                match token {
                    HtmlToken::Text(t) => builder.push_text(&t),
                    HtmlToken::OpenTag {
                        name,
                        attrs,
                        self_closing,
                    } => builder.handle_open_tag(name, attrs, self_closing),
                    HtmlToken::CloseTag(name) => builder.handle_close_tag(&name),
                }
            }
        }
        None => {
            builder.push_segment_with_mention_all(plain_body);
        }
    }

    let out = builder.finish();
    if out.text.chars().count() > MAX_OUTBOUND_TEXT_CHARS {
        return Err(GChatError::Protocol(
            "Messages in Google Chat can be at most 4,096 characters long.".to_string(),
        ));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fmt::inbound::annotations_to_matrix_html;

    #[test]
    fn test_outbound_html_generates_utf16_annotations_for_all_supported_tags() {
        let html = concat!(
            "🚀 👩‍💻 日本語 ",
            "<b>bold <i>both</i></b> ",
            "<em>italic</em> ",
            "<s>strike</s> ",
            "<u>under</u> ",
            "<code>inline()</code> ",
            "<pre><code>block_line_1\nblock_line_2\n</code></pre>",
            "<span data-mx-color=\"#ff00aa\">colored</span> ",
            "<a href=\"https://example.com/docs\">docs</a>",
            "<ul><li>first bullet</li><li>second bullet</li></ul>",
            "<ol><li>step one</li><li>step two</li></ol>"
        );
        let res = matrix_html_to_annotations("fallback", Some(html), true)
            .expect("convert supported HTML tags");

        // Verify HTML tags are stripped and list prefixes are emitted.
        assert!(
            !res.text.contains('<') && !res.text.contains('>'),
            "HTML tags must be stripped from output text: {:?}",
            res.text
        );
        assert!(
            res.text.contains("• first bullet\n• second bullet"),
            "unordered list items must be prefixed with bullet: {:?}",
            res.text
        );
        assert!(
            res.text.contains("1. step one\n2. step two"),
            "ordered list items must be numbered: {:?}",
            res.text
        );

        // Prefix "🚀 👩‍💻 日本語 " UTF-16 length:
        // "🚀" (2) + " " (1) + "👩‍💻" (5) + " " (1) + "日本語" (3) + " " (1) = 13 UTF-16 units.
        let prefix_utf16: i32 = "🚀 👩‍💻 日本語 ".encode_utf16().count() as i32;
        assert_eq!(prefix_utf16, 13);

        let has_format =
            |fmt_type: pb::format_metadata::FormatType, start: i32, len: i32| -> bool {
                res.annotations.iter().any(|ann| {
                    ann.r#type == Some(pb::AnnotationType::FormatData as i32)
                        && ann.start_index == Some(start)
                        && ann.length == Some(len)
                        && ann.chip_render_type
                            == Some(pb::annotation::ChipRenderType::DoNotRender as i32)
                        && matches!(
                            &ann.metadata,
                            Some(pb::annotation::Metadata::FormatMetadata(fm))
                                if fm.format_type == Some(fmt_type as i32)
                        )
                })
            };

        // "bold both" starts at 13, length 9; nested "both" starts at 18, length 4.
        assert!(
            has_format(pb::format_metadata::FormatType::Bold, 13, 9),
            "expected BOLD annotation at (13, 9), got: {:?}",
            res.annotations
        );
        assert!(
            has_format(pb::format_metadata::FormatType::Italic, 18, 4),
            "expected nested ITALIC annotation at (18, 4), got: {:?}",
            res.annotations
        );
        // "italic" starts at 23, length 6.
        assert!(
            has_format(pb::format_metadata::FormatType::Italic, 23, 6),
            "expected ITALIC annotation at (23, 6)"
        );
        // "strike" starts at 30, length 6.
        assert!(
            has_format(pb::format_metadata::FormatType::Strike, 30, 6),
            "expected STRIKE annotation at (30, 6)"
        );
        // "under" starts at 37, length 5.
        assert!(
            has_format(pb::format_metadata::FormatType::Underline, 37, 5),
            "expected UNDERLINE annotation at (37, 5)"
        );
        // "inline()" starts at 43, length 8.
        assert!(
            has_format(pb::format_metadata::FormatType::Monospace, 43, 8),
            "expected MONOSPACE annotation at (43, 8)"
        );
        // "block_line_1\nblock_line_2" has length 25.
        let block_start = res.text[..res.text.find("block_line_1").unwrap()]
            .encode_utf16()
            .count() as i32;
        assert!(
            has_format(
                pb::format_metadata::FormatType::MonospaceBlock,
                block_start,
                25
            ),
            "expected MONOSPACE_BLOCK annotation at ({block_start}, 25)"
        );

        // Font color "#ff00aa" -> 0xFFFF00AA as i32.
        let color_start = res.text[..res.text.find("colored").unwrap()]
            .encode_utf16()
            .count() as i32;
        let expected_color = 0xFFFF00AAu32 as i32;
        assert!(
            res.annotations.iter().any(|ann| {
                ann.r#type == Some(pb::AnnotationType::FormatData as i32)
                    && ann.start_index == Some(color_start)
                    && ann.length == Some(7)
                    && matches!(
                        &ann.metadata,
                        Some(pb::annotation::Metadata::FormatMetadata(fm))
                            if fm.format_type == Some(pb::format_metadata::FormatType::FontColor as i32)
                                && fm.font_color == Some(expected_color)
                    )
            }),
            "expected FONT_COLOR annotation for #ff00aa"
        );

        // Link "docs" -> https://example.com/docs
        let link_start = res.text[..res.text.find("docs").unwrap()]
            .encode_utf16()
            .count() as i32;
        assert!(
            res.annotations.iter().any(|ann| {
                ann.r#type == Some(pb::AnnotationType::Url as i32)
                    && ann.start_index == Some(link_start)
                    && ann.length == Some(4)
                    && matches!(
                        &ann.metadata,
                        Some(pb::annotation::Metadata::UrlMetadata(um))
                            if um.url.as_ref().and_then(|u| u.url.as_deref())
                                == Some("https://example.com/docs")
                    )
            }),
            "expected URL annotation for https://example.com/docs"
        );

        // Round-trip check with annotations_to_matrix_html.
        let round_trip = annotations_to_matrix_html(&res.text, &res.annotations, &[]);
        let rt_html = round_trip.formatted_body.as_deref().unwrap_or("");
        assert!(
            rt_html.contains("<strong>bold <em>both</em></strong>"),
            "got: {rt_html}"
        );
        assert!(rt_html.contains("<del>strike</del>"), "got: {rt_html}");
        assert!(rt_html.contains("<u>under</u>"), "got: {rt_html}");
        assert!(rt_html.contains("<code>inline()</code>"), "got: {rt_html}");
        assert!(
            rt_html.contains("<pre><code>block_line_1\nblock_line_2</code></pre>"),
            "got: {rt_html}"
        );
        assert!(rt_html.contains("color=\"#ff00aa\""), "got: {rt_html}");
        assert!(
            rt_html.contains("href=\"https://example.com/docs\""),
            "got: {rt_html}"
        );

        // Also verify partially overlapping bold/italic/links with emoji and CJK.
        let overlap_html =
            "🚀<b>漢字 <i>overlap <a href=\"https://example.com/o\">link</b> tail</a></i>";
        let overlap_res = matrix_html_to_annotations("fallback", Some(overlap_html), false)
            .expect("overlapping tags");
        assert_eq!(overlap_res.text, "🚀漢字 overlap link tail");
        // "🚀" is 2 UTF-16 units; "漢字 overlap link" is 15 UTF-16 units (start=2, len=15).
        assert!(overlap_res.annotations.iter().any(|a| {
            a.start_index == Some(2)
                && a.length == Some(15)
                && matches!(
                    &a.metadata,
                    Some(pb::annotation::Metadata::FormatMetadata(fm))
                        if fm.format_type == Some(pb::format_metadata::FormatType::Bold as i32)
                )
        }));
        // "overlap link tail" starts at 2 + 3 ("漢字 ") = 5, length 17.
        assert!(overlap_res.annotations.iter().any(|a| {
            a.start_index == Some(5)
                && a.length == Some(17)
                && matches!(
                    &a.metadata,
                    Some(pb::annotation::Metadata::FormatMetadata(fm))
                        if fm.format_type == Some(pb::format_metadata::FormatType::Italic as i32)
                )
        }));
        // "link tail" starts at 5 + 8 ("overlap ") = 13, length 9.
        assert!(overlap_res.annotations.iter().any(|a| {
            a.start_index == Some(13)
                && a.length == Some(9)
                && matches!(
                    &a.metadata,
                    Some(pb::annotation::Metadata::UrlMetadata(um))
                        if um.url.as_ref().and_then(|u| u.url.as_deref())
                            == Some("https://example.com/o")
                )
        }));
    }

    #[test]
    fn test_outbound_mentions_emit_user_mention_and_mention_all_annotations() {
        let html = "Hi <a href=\"https://matrix.to/#/@gchat_112233445566778899002:courier.local\">@Grace Hopper</a> and @all!";
        let allowed = matrix_html_to_annotations("Hi @Grace Hopper and @all!", Some(html), true)
            .expect("mentions with allow_mention_all=true");
        assert_eq!(allowed.text, "Hi @Grace Hopper and @all!");

        // @Grace Hopper starts at UTF-16 index 3, length 13.
        assert!(
            allowed.annotations.iter().any(|ann| {
                ann.r#type == Some(pb::AnnotationType::UserMention as i32)
                    && ann.start_index == Some(3)
                    && ann.length == Some(13)
                    && matches!(
                        &ann.metadata,
                        Some(pb::annotation::Metadata::UserMentionMetadata(um))
                            if um.r#type == Some(pb::user_mention_metadata::Type::Mention as i32)
                                && um.id.as_ref().and_then(|u| u.id.as_deref())
                                    == Some("112233445566778899002")
                    )
            }),
            "expected USER_MENTION (MENTION) for Grace Hopper, got: {:?}",
            allowed.annotations
        );

        // @all starts at UTF-16 index 21, length 4.
        assert!(
            allowed.annotations.iter().any(|ann| {
                ann.r#type == Some(pb::AnnotationType::UserMention as i32)
                    && ann.start_index == Some(21)
                    && ann.length == Some(4)
                    && matches!(
                        &ann.metadata,
                        Some(pb::annotation::Metadata::UserMentionMetadata(um))
                            if um.r#type == Some(pb::user_mention_metadata::Type::MentionAll as i32)
                    )
            }),
            "expected USER_MENTION (MENTION_ALL) for @all when allow_mention_all=true, got: {:?}",
            allowed.annotations
        );

        // When allow_mention_all == false, @all is left as plain text without a MENTION_ALL annotation.
        let disallowed =
            matrix_html_to_annotations("Hi @Grace Hopper and @all!", Some(html), false)
                .expect("mentions with allow_mention_all=false");
        assert_eq!(disallowed.text, "Hi @Grace Hopper and @all!");
        assert_eq!(
            disallowed.annotations.len(),
            1,
            "only the explicit user mention should be emitted when allow_mention_all=false: {:?}",
            disallowed.annotations
        );

        // Also verify @room converts to @all with MENTION_ALL when allow_mention_all == true,
        // and stays plain text when allow_mention_all == false.
        let room_allowed = matrix_html_to_annotations("Ping @room now", None, true)
            .expect("@room with allow_mention_all=true");
        assert_eq!(room_allowed.text, "Ping @all now");
        assert_eq!(room_allowed.annotations.len(), 1);
        assert_eq!(room_allowed.annotations[0].start_index, Some(5));
        assert_eq!(room_allowed.annotations[0].length, Some(4));

        // Also verify exceeds 4,096 chars is refused with a plain English message.
        let too_long = "a".repeat(MAX_OUTBOUND_TEXT_CHARS + 1);
        let err = matrix_html_to_annotations(&too_long, None, false)
            .expect_err("messages over 4,096 characters must be refused");
        assert!(
            err.to_string().contains("4,096"),
            "expected plain English 4,096-character limit error, got: {err}"
        );
    }

    #[test]
    fn test_outbound_unsupported_blockquote_and_headings_degrade_to_plain_text() {
        let bq = matrix_html_to_annotations("quote", Some("<blockquote>quote</blockquote>"), false)
            .expect("blockquote degrades to plain text");
        assert_eq!(bq.text, "> quote\n");
        assert!(bq.annotations.is_empty());

        let h1 = matrix_html_to_annotations("Title", Some("<h1>Title</h1>"), false)
            .expect("h1 degrades to BOLD annotation");
        assert_eq!(h1.text, "Title");
        assert_eq!(h1.annotations.len(), 1);
        assert_eq!(
            h1.annotations[0].r#type,
            Some(pb::AnnotationType::FormatData as i32)
        );
        assert_eq!(h1.annotations[0].start_index, Some(0));
        assert_eq!(h1.annotations[0].length, Some(5));
        assert!(matches!(
            &h1.annotations[0].metadata,
            Some(pb::annotation::Metadata::FormatMetadata(fm))
                if fm.format_type == Some(pb::format_metadata::FormatType::Bold as i32)
        ));
    }
}
