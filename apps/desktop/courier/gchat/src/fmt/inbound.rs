// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::{googlechat, pb};

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ConvertedInboundText {
    pub body: String,
    pub formatted_body: Option<String>,
    pub mentions: Vec<String>, // Gaia IDs mentioned
    pub mention_all: bool,
}

#[derive(Debug, Clone)]
struct HtmlSpan {
    start: usize,
    end: usize,
    open_tag: String,
    close_tag: &'static str,
    hidden: bool,
    order: usize,
}

pub fn escape_html(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            c => out.push(c),
        }
    }
    out
}

fn is_safe_href(url: &str) -> bool {
    let trimmed = url.trim().to_ascii_lowercase();
    trimmed.starts_with("https://")
        || trimmed.starts_with("http://")
        || trimmed.starts_with("mailto:")
}

fn extract_formatted_text(ft: Option<&pb::JAddOnsFormattedText>) -> String {
    let Some(ft) = ft else {
        return String::new();
    };
    if let Some(orig) = ft.original_text.as_deref() {
        if !orig.is_empty() {
            return orig.to_string();
        }
    }
    let mut out = String::new();
    for el in &ft.formatted_text_elements {
        match &el.element {
            Some(pb::j_add_ons_formatted_text::formatted_text_element::Element::StyledText(st)) => {
                if let Some(t) = st.text.as_deref() {
                    out.push_str(t);
                }
            }
            Some(pb::j_add_ons_formatted_text::formatted_text_element::Element::Hyperlink(hl)) => {
                if let Some(t) = hl.text.as_deref() {
                    out.push_str(t);
                } else if let Some(l) = hl.link.as_deref() {
                    out.push_str(l);
                }
            }
            None => {}
        }
    }
    out
}

fn extract_onclick_url(on_click: Option<&pb::JAddOnsOnClick>) -> Option<String> {
    let oc = on_click?;
    match &oc.data_case {
        Some(pb::j_add_ons_on_click::DataCase::Link(url)) => {
            let trimmed = url.trim();
            if is_safe_href(trimmed) {
                Some(trimmed.to_string())
            } else {
                None
            }
        }
        Some(pb::j_add_ons_on_click::DataCase::OpenLink(open_link)) => open_link
            .url
            .as_deref()
            .or(open_link.original_link.as_deref())
            .map(str::trim)
            .filter(|u| is_safe_href(u))
            .map(ToOwned::to_owned),
        _ => None,
    }
}

fn render_button(btn: &pb::j_add_ons_widget::Button) -> Option<(String, String)> {
    match &btn.r#type {
        Some(pb::j_add_ons_widget::button::Type::TextButton(tb)) => {
            let label = extract_formatted_text(tb.text.as_ref());
            let label = if label.trim().is_empty() {
                tb.alt_text.clone().unwrap_or_else(|| "Button".to_string())
            } else {
                label
            };
            if let Some(url) = extract_onclick_url(tb.on_click.as_deref()) {
                let plain = format!("{label} ({url})");
                let html = format!(
                    "<a href=\"{}\">{}</a>",
                    escape_html(&url),
                    escape_html(&label)
                );
                Some((plain, html))
            } else {
                let plain = format!("[{label}]");
                let html = format!("[{}]", escape_html(&label));
                Some((plain, html))
            }
        }
        Some(pb::j_add_ons_widget::button::Type::ImageButton(ib)) => {
            let label = ib.name.as_deref().unwrap_or("Link");
            if let Some(url) = extract_onclick_url(ib.on_click.as_ref()) {
                let plain = format!("{label} ({url})");
                let html = format!(
                    "<a href=\"{}\">{}</a>",
                    escape_html(&url),
                    escape_html(label)
                );
                Some((plain, html))
            } else {
                None
            }
        }
        None => None,
    }
}

fn render_bot_cards(attachments: &[googlechat::Attachment]) -> Option<(String, String)> {
    let mut plain_cards = Vec::new();
    let mut html_cards = Vec::new();

    for att in attachments {
        let mut add_ons = Vec::new();
        if let Some(app_card) = att.app_card_data.as_ref() {
            add_ons.push(app_card);
        }
        if let Some(pb::attachment::Type::AddOnData(add_on)) = &att.r#type {
            add_ons.push(add_on);
        }

        for add_on in add_ons {
            for card in &add_on.cards {
                let mut plain_lines = Vec::new();
                let mut html_lines = Vec::new();

                if let Some(header) = &card.header {
                    let title = extract_formatted_text(header.title.as_ref());
                    let subtitle = extract_formatted_text(header.subtitle.as_ref());
                    if !title.is_empty() && !subtitle.is_empty() {
                        plain_lines.push(format!("{title} — {subtitle}"));
                        html_lines.push(format!(
                            "<strong>{}</strong><br><em>{}</em>",
                            escape_html(&title),
                            escape_html(&subtitle)
                        ));
                    } else if !title.is_empty() {
                        plain_lines.push(title.clone());
                        html_lines.push(format!("<strong>{}</strong>", escape_html(&title)));
                    } else if !subtitle.is_empty() {
                        plain_lines.push(subtitle.clone());
                        html_lines.push(format!("<em>{}</em>", escape_html(&subtitle)));
                    }
                }

                for section in &card.sections {
                    let sec_hdr = extract_formatted_text(section.header.as_ref());
                    if !sec_hdr.is_empty() {
                        plain_lines.push(sec_hdr.clone());
                        html_lines.push(format!("<strong>{}</strong>", escape_html(&sec_hdr)));
                    } else if let Some(desc) = section.description.as_deref() {
                        if !desc.trim().is_empty() {
                            plain_lines.push(desc.to_string());
                            html_lines.push(format!("<strong>{}</strong>", escape_html(desc)));
                        }
                    }

                    for widget in &section.widgets {
                        match &widget.data {
                            Some(pb::j_add_ons_widget::Data::TextParagraph(tp)) => {
                                let t = extract_formatted_text(tp.text.as_ref());
                                if !t.is_empty() {
                                    plain_lines.push(t.clone());
                                    html_lines.push(escape_html(&t));
                                }
                            }
                            Some(pb::j_add_ons_widget::Data::TextWidget(tw)) => {
                                for line in &tw.line {
                                    if !line.is_empty() {
                                        plain_lines.push(line.clone());
                                        html_lines.push(escape_html(line));
                                    }
                                }
                            }
                            Some(pb::j_add_ons_widget::Data::TextKeyValue(tkv)) => {
                                let k = extract_formatted_text(tkv.key.as_ref());
                                let v = extract_formatted_text(tkv.text.as_ref());
                                if !k.is_empty() && !v.is_empty() {
                                    plain_lines.push(format!("{k}: {v}"));
                                    html_lines.push(format!(
                                        "<strong>{}</strong>: {}",
                                        escape_html(&k),
                                        escape_html(&v)
                                    ));
                                } else if !v.is_empty() {
                                    plain_lines.push(v.clone());
                                    html_lines.push(escape_html(&v));
                                }
                            }
                            Some(pb::j_add_ons_widget::Data::KeyValue(kv)) => {
                                let top = extract_formatted_text(kv.top_label.as_ref());
                                let content = extract_formatted_text(kv.content.as_ref());
                                let bottom = extract_formatted_text(kv.bottom_label.as_ref());
                                let mut p_parts = Vec::new();
                                let mut h_parts = Vec::new();
                                if !top.is_empty() {
                                    p_parts.push(top.clone());
                                    h_parts.push(escape_html(&top));
                                }
                                if !content.is_empty() {
                                    p_parts.push(content.clone());
                                    h_parts.push(format!(
                                        "<strong>{}</strong>",
                                        escape_html(&content)
                                    ));
                                }
                                if !bottom.is_empty() {
                                    p_parts.push(bottom.clone());
                                    h_parts.push(format!("<em>{}</em>", escape_html(&bottom)));
                                }
                                if !p_parts.is_empty() {
                                    plain_lines.push(p_parts.join(": "));
                                    html_lines.push(h_parts.join(": "));
                                }
                                if let Some(pb::j_add_ons_widget::key_value::Control::Button(b)) =
                                    &kv.control
                                {
                                    if let Some((bp, bh)) = render_button(b) {
                                        plain_lines.push(bp);
                                        html_lines.push(bh);
                                    }
                                }
                            }
                            Some(pb::j_add_ons_widget::Data::LabelContentPairWidget(lcp)) => {
                                for pair in &lcp.label_content_pair {
                                    let l = pair.label.as_deref().unwrap_or("");
                                    let c = pair.content.as_deref().unwrap_or("");
                                    if !l.is_empty() || !c.is_empty() {
                                        plain_lines.push(format!("{l}: {c}"));
                                        html_lines.push(format!(
                                            "<strong>{}</strong>: {}",
                                            escape_html(l),
                                            escape_html(c)
                                        ));
                                    }
                                }
                            }
                            Some(pb::j_add_ons_widget::Data::Divider(_)) => {
                                plain_lines.push("---".to_string());
                                html_lines.push("<hr>".to_string());
                            }
                            _ => {}
                        }

                        if !widget.buttons.is_empty() {
                            let mut btn_plain = Vec::new();
                            let mut btn_html = Vec::new();
                            for b in &widget.buttons {
                                if let Some((bp, bh)) = render_button(b) {
                                    btn_plain.push(bp);
                                    btn_html.push(bh);
                                }
                            }
                            if !btn_plain.is_empty() {
                                plain_lines.push(btn_plain.join(" | "));
                                html_lines.push(btn_html.join(" | "));
                            }
                        }
                    }
                }

                if !plain_lines.is_empty() {
                    plain_cards.push(plain_lines.join("\n"));
                    html_cards.push(format!(
                        "<blockquote>{}</blockquote>",
                        html_lines.join("<br>")
                    ));
                }
            }
        }
    }

    if plain_cards.is_empty() {
        None
    } else {
        Some((plain_cards.join("\n\n"), html_cards.join("<br>")))
    }
}

pub fn annotations_to_matrix_html(
    text: &str,
    annotations: &[googlechat::Annotation],
    attachments: &[googlechat::Attachment],
) -> ConvertedInboundText {
    let utf16: Vec<u16> = text.encode_utf16().collect();
    let utf16_len = utf16.len();

    let mut mentions = Vec::new();
    let mut mention_all = false;
    let mut spans = Vec::new();

    for (order, ann) in annotations.iter().enumerate() {
        // Record mention metadata even before checking span bounds if MENTION_ALL.
        if let Some(pb::annotation::Metadata::UserMentionMetadata(um)) = &ann.metadata {
            if um.r#type == Some(pb::user_mention_metadata::Type::MentionAll as i32)
                || um.r#type == Some(2)
            {
                mention_all = true;
            }
            if let Some(gaia_id) = um
                .id
                .as_ref()
                .and_then(|u| u.id.as_deref())
                .filter(|s| !s.trim().is_empty())
            {
                if !mentions.iter().any(|m| m == gaia_id) {
                    mentions.push(gaia_id.to_string());
                }
            }
        }

        let Some(start_u32) = ann.start_index.and_then(|v| u32::try_from(v).ok()) else {
            continue;
        };
        let Some(len_u32) = ann.length.and_then(|v| u32::try_from(v).ok()) else {
            continue;
        };
        if len_u32 == 0 {
            continue;
        }
        let start = start_u32 as usize;
        if start >= utf16_len {
            continue;
        }
        let Some(raw_end) = start.checked_add(len_u32 as usize) else {
            continue;
        };
        let mut end = raw_end.min(utf16_len);
        if end <= start {
            continue;
        }

        // Prevent splitting surrogate pairs (0xD800..=0xDBFF followed by 0xDC00..=0xDFFF).
        if (0xDC00..=0xDFFF).contains(&utf16[start]) {
            continue;
        }
        if end < utf16_len && (0xDC00..=0xDFFF).contains(&utf16[end]) {
            end += 1;
        }

        match &ann.metadata {
            Some(pb::annotation::Metadata::FormatMetadata(fm)) => {
                let ft = fm.format_type.unwrap_or(0);
                if let Some(color) = fm.font_color {
                    let rgb = u32::from_ne_bytes(color.to_ne_bytes()) & 0x00FF_FFFF;
                    spans.push(HtmlSpan {
                        start,
                        end,
                        open_tag: format!("<font color=\"#{rgb:06x}\">"),
                        close_tag: "</font>",
                        hidden: false,
                        order,
                    });
                } else {
                    match ft {
                        x if x == pb::format_metadata::FormatType::Bold as i32 => {
                            spans.push(HtmlSpan {
                                start,
                                end,
                                open_tag: "<strong>".to_string(),
                                close_tag: "</strong>",
                                hidden: false,
                                order,
                            });
                        }
                        x if x == pb::format_metadata::FormatType::Italic as i32 => {
                            spans.push(HtmlSpan {
                                start,
                                end,
                                open_tag: "<em>".to_string(),
                                close_tag: "</em>",
                                hidden: false,
                                order,
                            });
                        }
                        x if x == pb::format_metadata::FormatType::Strike as i32 => {
                            spans.push(HtmlSpan {
                                start,
                                end,
                                open_tag: "<del>".to_string(),
                                close_tag: "</del>",
                                hidden: false,
                                order,
                            });
                        }
                        x if x == pb::format_metadata::FormatType::SourceCode as i32
                            || x == pb::format_metadata::FormatType::Monospace as i32 =>
                        {
                            spans.push(HtmlSpan {
                                start,
                                end,
                                open_tag: "<code>".to_string(),
                                close_tag: "</code>",
                                hidden: false,
                                order,
                            });
                        }
                        x if x == pb::format_metadata::FormatType::Hidden as i32
                            || x == pb::format_metadata::FormatType::ClientHidden as i32 =>
                        {
                            spans.push(HtmlSpan {
                                start,
                                end,
                                open_tag: String::new(),
                                close_tag: "",
                                hidden: true,
                                order,
                            });
                        }
                        x if x == pb::format_metadata::FormatType::MonospaceBlock as i32 => {
                            spans.push(HtmlSpan {
                                start,
                                end,
                                open_tag: "<pre><code>".to_string(),
                                close_tag: "</code></pre>",
                                hidden: false,
                                order,
                            });
                        }
                        x if x == pb::format_metadata::FormatType::Underline as i32 => {
                            spans.push(HtmlSpan {
                                start,
                                end,
                                open_tag: "<u>".to_string(),
                                close_tag: "</u>",
                                hidden: false,
                                order,
                            });
                        }
                        x if x == pb::format_metadata::FormatType::BulletedList as i32 => {
                            spans.push(HtmlSpan {
                                start,
                                end,
                                open_tag: "<ul>".to_string(),
                                close_tag: "</ul>",
                                hidden: false,
                                order,
                            });
                        }
                        x if x == pb::format_metadata::FormatType::BulletedListItem as i32 => {
                            spans.push(HtmlSpan {
                                start,
                                end,
                                open_tag: "<li>".to_string(),
                                close_tag: "</li>",
                                hidden: false,
                                order,
                            });
                        }
                        _ => {}
                    }
                }
            }
            Some(pb::annotation::Metadata::UrlMetadata(um)) => {
                if let Some(href) = um
                    .url
                    .as_ref()
                    .and_then(|u| u.url.as_deref())
                    .filter(|u| is_safe_href(u))
                {
                    spans.push(HtmlSpan {
                        start,
                        end,
                        open_tag: format!("<a href=\"{}\">", escape_html(href)),
                        close_tag: "</a>",
                        hidden: false,
                        order,
                    });
                }
            }
            Some(pb::annotation::Metadata::UserMentionMetadata(um)) => {
                if let Some(gaia_id) = um
                    .id
                    .as_ref()
                    .and_then(|u| u.id.as_deref())
                    .filter(|s| !s.trim().is_empty())
                {
                    spans.push(HtmlSpan {
                        start,
                        end,
                        open_tag: format!(
                            "<a href=\"https://matrix.to/#/@gchat_{}:courier.local\">",
                            escape_html(gaia_id)
                        ),
                        close_tag: "</a>",
                        hidden: false,
                        order,
                    });
                }
            }
            _ => {}
        }
    }

    let sort_spans = |list: &mut Vec<HtmlSpan>| {
        list.sort_by(|a, b| {
            a.start
                .cmp(&b.start)
                .then_with(|| b.end.cmp(&a.end))
                .then_with(|| a.order.cmp(&b.order))
        });
    };
    sort_spans(&mut spans);

    // Split any partially overlapping span that starts inside an earlier span and extends past its end,
    // matching `normalizeAnnotations` in `ref/pkg/msgconv/gchatfmt/convert.go:141-198`.
    loop {
        let mut split_pair: Option<(usize, usize)> = None;
        'outer: for i in 0..spans.len() {
            for j in (i + 1)..spans.len() {
                if spans[j].start >= spans[i].end {
                    break;
                }
                if spans[j].end > spans[i].end {
                    split_pair = Some((j, spans[i].end));
                    break 'outer;
                }
            }
        }
        let Some((idx, split_at)) = split_pair else {
            break;
        };
        let orig = spans[idx].clone();
        spans[idx].end = split_at;
        spans.push(HtmlSpan {
            start: split_at,
            end: orig.end,
            open_tag: orig.open_tag,
            close_tag: orig.close_tag,
            hidden: orig.hidden,
            order: orig.order,
        });
        sort_spans(&mut spans);
    }

    let mut body = text.to_string();
    let mut formatted_body = if spans.is_empty() {
        None
    } else {
        let mut html = String::with_capacity(text.len() + spans.len() * 16);
        let mut active: Vec<&HtmlSpan> = Vec::new();
        let mut span_idx = 0usize;
        let mut pos = 0usize;

        while pos <= utf16_len {
            // Close spans ending at `pos` in reverse (LIFO) order.
            while let Some(last) = active.last() {
                if last.end <= pos {
                    let popped = active.pop().unwrap();
                    html.push_str(popped.close_tag);
                } else {
                    break;
                }
            }

            // Open spans starting at `pos`.
            while span_idx < spans.len() && spans[span_idx].start == pos {
                let s = &spans[span_idx];
                html.push_str(&s.open_tag);
                active.push(s);
                span_idx += 1;
            }

            if pos == utf16_len {
                break;
            }

            // Advance to next boundary across all active spans and the next unopened span.
            let mut next_pos = utf16_len;
            for a in &active {
                next_pos = next_pos.min(a.end);
            }
            if span_idx < spans.len() {
                next_pos = next_pos.min(spans[span_idx].start);
            }
            if next_pos <= pos {
                next_pos = pos + 1;
            }

            let is_hidden = active.iter().any(|s| s.hidden);
            if !is_hidden {
                let seg = String::from_utf16_lossy(&utf16[pos..next_pos]);
                html.push_str(&escape_html(&seg));
            }
            pos = next_pos;
        }

        while let Some(popped) = active.pop() {
            html.push_str(popped.close_tag);
        }

        Some(html)
    };

    if let Some((card_plain, card_html)) = render_bot_cards(attachments) {
        if body.trim().is_empty() {
            body = card_plain;
        } else {
            body = format!("{body}\n\n{card_plain}");
        }
        formatted_body = Some(match formatted_body {
            Some(existing) if !existing.trim().is_empty() => format!("{existing}<br>{card_html}"),
            _ if !text.trim().is_empty() => format!("{}<br>{card_html}", escape_html(text)),
            _ => card_html,
        });
    }

    ConvertedInboundText {
        body,
        formatted_body,
        mentions,
        mention_all,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pb;

    #[test]
    fn test_inbound_annotations_convert_utf16_spans_with_emojis_and_nested_styles() {
        // UTF-16 layout of:
        // "Hi 👋 bold italic strike code block under color link @Alice Example"
        // "Hi " = 3 units (0..3)
        // "👋" = 2 units (3..5)
        // " " = 1 unit (5..6)
        // "bold" = 4 units (6..10)
        // " " = 1 unit (10..11)
        // "italic" = 6 units (11..17)
        // " " = 1 unit (17..18)
        // "strike" = 6 units (18..24)
        // " " = 1 unit (24..25)
        // "code" = 4 units (25..29)
        // " " = 1 unit (29..30)
        // "block" = 5 units (30..35)
        // " " = 1 unit (35..36)
        // "under" = 5 units (36..41)
        // " " = 1 unit (41..42)
        // "color" = 5 units (42..47)
        // " " = 1 unit (47..48)
        // "link" = 4 units (48..52)
        // " " = 1 unit (52..53)
        // "@Alice Example" = 14 units (53..67)
        let text = "Hi 👋 bold italic strike code block under color link @Alice Example";
        let signed_color = ((0xFF3366i64 | 0x7F00_0000i64) - (1i64 << 31)) as i32;

        let annotations = vec![
            // BOLD (1) on "bold" (6..10)
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(6),
                length: Some(4),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::Bold as i32),
                        font_color: None,
                    },
                )),
                ..Default::default()
            },
            // ITALIC (2) on "italic" (11..17)
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(11),
                length: Some(6),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::Italic as i32),
                        font_color: None,
                    },
                )),
                ..Default::default()
            },
            // STRIKE (3) on "strike" (18..24)
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(18),
                length: Some(6),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::Strike as i32),
                        font_color: None,
                    },
                )),
                ..Default::default()
            },
            // MONOSPACE (5; also test SOURCE_CODE = 4) on "code" (25..29)
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(25),
                length: Some(4),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::Monospace as i32),
                        font_color: None,
                    },
                )),
                ..Default::default()
            },
            // MONOSPACE_BLOCK (7) on "block" (30..35)
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(30),
                length: Some(5),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::MonospaceBlock as i32),
                        font_color: None,
                    },
                )),
                ..Default::default()
            },
            // UNDERLINE (8) on "under" (36..41)
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(36),
                length: Some(5),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::Underline as i32),
                        font_color: None,
                    },
                )),
                ..Default::default()
            },
            // FONT_COLOR (9) on "color" (42..47)
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(42),
                length: Some(5),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::FontColor as i32),
                        font_color: Some(signed_color),
                    },
                )),
                ..Default::default()
            },
            // URL (1) on "link" (48..52)
            pb::Annotation {
                r#type: Some(pb::AnnotationType::Url as i32),
                start_index: Some(48),
                length: Some(4),
                metadata: Some(pb::annotation::Metadata::UrlMetadata(pb::UrlMetadata {
                    url: Some(pb::Url {
                        url: Some("https://example.com/docs".to_string()),
                    }),
                    ..Default::default()
                })),
                ..Default::default()
            },
            // USER_MENTION (6) on "@Alice Example" (53..67)
            pb::Annotation {
                r#type: Some(pb::AnnotationType::UserMention as i32),
                start_index: Some(53),
                length: Some(14),
                metadata: Some(pb::annotation::Metadata::UserMentionMetadata(
                    pb::UserMentionMetadata {
                        id: Some(pb::UserId {
                            id: Some("112233445566778899001".to_string()),
                            r#type: Some(pb::UserType::Human as i32),
                        }),
                        r#type: Some(pb::user_mention_metadata::Type::Mention as i32),
                        display_name: Some("Alice Example".to_string()),
                        ..Default::default()
                    },
                )),
                ..Default::default()
            },
        ];

        let res = annotations_to_matrix_html(text, &annotations, &[]);
        let html = res.formatted_body.expect("formatted_body must be present");
        assert!(html.contains("<strong>bold</strong>"), "html: {html}");
        assert!(html.contains("<em>italic</em>"), "html: {html}");
        assert!(html.contains("<del>strike</del>"), "html: {html}");
        assert!(html.contains("<code>code</code>"), "html: {html}");
        assert!(
            html.contains("<pre><code>block</code></pre>"),
            "html: {html}"
        );
        assert!(html.contains("<u>under</u>"), "html: {html}");
        assert!(
            html.contains("<font color=\"#ff3366\">color</font>"),
            "html: {html}"
        );
        assert!(
            html.contains("<a href=\"https://example.com/docs\">link</a>"),
            "html: {html}"
        );
        assert!(
            html.contains(
                "<a href=\"https://matrix.to/#/@gchat_112233445566778899001:courier.local\">"
            ),
            "html: {html}"
        );
        assert_eq!(res.mentions, vec!["112233445566778899001".to_string()]);
    }

    #[test]
    fn test_inbound_annotations_clamp_or_skip_out_of_bounds_and_negative_offsets() {
        let text = "Hello 👋 world";
        let annotations = vec![
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(-5),
                length: Some(4),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::Bold as i32),
                        font_color: None,
                    },
                )),
                ..Default::default()
            },
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(0),
                length: Some(-1),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::Italic as i32),
                        font_color: None,
                    },
                )),
                ..Default::default()
            },
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(6),
                length: Some(9999),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::Bold as i32),
                        font_color: None,
                    },
                )),
                ..Default::default()
            },
        ];

        let res = annotations_to_matrix_html(text, &annotations, &[]);
        assert_eq!(res.body, "Hello 👋 world");
        assert_eq!(
            res.formatted_body.as_deref(),
            Some("Hello <strong>👋 world</strong>")
        );
    }

    #[test]
    fn test_inbound_bot_card_attachment_field_15_renders_structured_fallback() {
        let card_att = pb::Attachment {
            app_card_data: Some(pb::JAddOnsContextualAddOn {
                cards: vec![pb::j_add_ons_contextual_add_on::Card {
                    header: Some(pb::j_add_ons_contextual_add_on::card::CardHeader {
                        title: Some(pb::JAddOnsFormattedText {
                            original_text: Some("PagerDuty Alert".to_string()),
                            ..Default::default()
                        }),
                        subtitle: Some(pb::JAddOnsFormattedText {
                            original_text: Some("Sev-2".to_string()),
                            ..Default::default()
                        }),
                        ..Default::default()
                    }),
                    sections: vec![pb::j_add_ons_contextual_add_on::card::Section {
                        widgets: vec![
                            pb::JAddOnsWidget {
                                data: Some(pb::j_add_ons_widget::Data::TextParagraph(
                                    pb::j_add_ons_widget::TextParagraph {
                                        text: Some(pb::JAddOnsFormattedText {
                                            original_text: Some(
                                                "Database replica lag exceeded threshold"
                                                    .to_string(),
                                            ),
                                            ..Default::default()
                                        }),
                                    },
                                )),
                                ..Default::default()
                            },
                            pb::JAddOnsWidget {
                                data: Some(pb::j_add_ons_widget::Data::KeyValue(
                                    pb::j_add_ons_widget::KeyValue {
                                        top_label: Some(pb::JAddOnsFormattedText {
                                            original_text: Some("Service".to_string()),
                                            ..Default::default()
                                        }),
                                        content: Some(pb::JAddOnsFormattedText {
                                            original_text: Some("payments-db".to_string()),
                                            ..Default::default()
                                        }),
                                        ..Default::default()
                                    },
                                )),
                                ..Default::default()
                            },
                            pb::JAddOnsWidget {
                                buttons: vec![pb::j_add_ons_widget::Button {
                                    r#type: Some(pb::j_add_ons_widget::button::Type::TextButton(
                                        pb::j_add_ons_widget::TextButton {
                                            text: Some(pb::JAddOnsFormattedText {
                                                original_text: Some(
                                                    "Acknowledge Incident".to_string(),
                                                ),
                                                ..Default::default()
                                            }),
                                            on_click: Some(Box::new(pb::JAddOnsOnClick {
                                                data_case: Some(
                                                    pb::j_add_ons_on_click::DataCase::OpenLink(
                                                        pb::JAddOnsOpenLink {
                                                            url: Some(
                                                                "https://example.com/inc/42"
                                                                    .to_string(),
                                                            ),
                                                            ..Default::default()
                                                        },
                                                    ),
                                                ),
                                            })),
                                            ..Default::default()
                                        },
                                    )),
                                }],
                                ..Default::default()
                            },
                        ],
                        ..Default::default()
                    }],
                    ..Default::default()
                }],
                ..Default::default()
            }),
            ..Default::default()
        };

        let res = annotations_to_matrix_html("", &[], &[card_att]);
        assert!(
            res.body.contains("PagerDuty Alert")
                && res.body.contains("Sev-2")
                && res.body.contains("https://example.com/inc/42"),
            "plain body missing card summary: {}",
            res.body
        );
        let html = res
            .formatted_body
            .expect("bot card must produce formatted_body");
        assert!(html.contains("<blockquote>"), "html: {html}");
        assert!(html.contains("PagerDuty Alert"), "html: {html}");
        assert!(html.contains("Sev-2"), "html: {html}");
        assert!(
            html.contains("<a href=\"https://example.com/inc/42\">"),
            "html: {html}"
        );
    }

    #[test]
    fn test_inbound_annotations_split_partially_overlapping_spans_with_emojis() {
        // Text: "Hi 👋🔥 world"
        // "Hi " = 0..3 (3 UTF-16 units)
        // "👋" = 3..5 (2 UTF-16 units)
        // "🔥" = 5..7 (2 UTF-16 units)
        // " world" = 7..13 (6 UTF-16 units)
        // Span A (BOLD): start=3, length=4 -> covers "👋🔥" (3..7)
        // Span B (ITALIC): start=5, length=8 -> covers "🔥 world" (5..13)
        // Because Span B starts inside Span A (5 < 7) and extends past Span A (13 > 7),
        // Span B must be split at 7 so BOLD closes at 7 and ITALIC wraps both "🔥" and " world".
        let text = "Hi 👋🔥 world";
        let annotations = vec![
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(3),
                length: Some(4),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::Bold as i32),
                        font_color: None,
                    },
                )),
                ..Default::default()
            },
            pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(5),
                length: Some(8),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::Italic as i32),
                        font_color: None,
                    },
                )),
                ..Default::default()
            },
        ];

        let res = annotations_to_matrix_html(text, &annotations, &[]);
        assert_eq!(
            res.formatted_body.as_deref(),
            Some("Hi <strong>👋<em>🔥</em></strong><em> world</em>")
        );
    }
}
