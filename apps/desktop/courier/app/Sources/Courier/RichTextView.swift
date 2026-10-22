// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// A message's text as its formatting says (01 §5's MessageText, Code, Spoiler, MessageMention): paragraphs, a quote
/// with a bar, lists indented with their bullets or numbers, a code block in a monospaced box that scrolls sideways;
/// and in a line bold, italic, struck-through, code on a tint, links that open in the browser, mentions as chips and
/// spoilers hidden under a tint until clicked. `RichTextLayout` cuts the text up; this only draws it.
struct RichTextView: View {
    let rich: RichText
    /// Drawn on my own (accent) bubble: tints are white, not the accent.
    let onBubble: Bool
    /// The spoilers show.
    @Binding var revealed: Bool
    var italic = false

    var body: some View {
        let blocks = RichTextLayout.blocks(of: rich)
        let hasSpoiler = rich.entities.contains { $0.kind == .spoiler }
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .italic(italic)
        // Links on my own bubble are white, as its text is.
        .tint(onBubble ? Color.white : Color.accentColor)
        // A click shows the spoilers; it still selects the message, as a click anywhere on it does.
        .simultaneousGesture(TapGesture().onEnded { if hasSpoiler { revealed = true } })
        .help(hasSpoiler && !revealed ? String(localized: "Click to show the spoiler") : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RichTextLayout.spoken(rich, revealed: revealed))
    }

    @ViewBuilder
    private func blockView(_ block: RichTextLayout.Block) -> some View {
        switch block.kind {
        case .paragraph:
            Text(joined(block.lines))
                .fixedSize(horizontal: false, vertical: true)
        case .quote:
            HStack(alignment: .top, spacing: 7) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(onBubble ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
                    .frame(width: 3)
                Text(joined(block.lines))
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .bulletList, .orderedList:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(block.lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: block.kind == .bulletList ? "•" : "\(index + 1).")
                            .monospacedDigit()
                            .frame(minWidth: 12, alignment: .trailing)
                        Text(attributed(line))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 4)
        case .code:
            ScrollView(.horizontal, showsIndicators: true) {
                Text(block.lines.map { $0.map(\.text).joined() }.joined(separator: "\n"))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(tint))
        }
    }

    private var tint: Color { onBubble ? Color.white.opacity(0.2) : Color.primary.opacity(0.08) }

    private func joined(_ lines: [[RichTextLayout.Run]]) -> AttributedString {
        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            result.append(attributed(line))
        }
        return result
    }

    /// One line's runs as styled text.
    private func attributed(_ runs: [RichTextLayout.Run]) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece: AttributedString
            if run.link == nil, run.mention == nil, !run.code {
                piece = LinkedText.attributed(run.text) // addresses typed as text still open
            } else {
                piece = AttributedString(run.text)
            }
            var font = run.code ? Font.system(.body, design: .monospaced) : Font.body
            if run.bold || run.mention != nil { font = font.bold() }
            if run.italic { font = font.italic() }
            piece.font = font
            if run.strikethrough { piece.strikethroughStyle = .single }
            if run.code { piece.backgroundColor = tint }
            if let url = run.link {
                piece.link = url
                piece.underlineStyle = .single
                if onBubble { piece.foregroundColor = .white }
            }
            if run.mention != nil {
                piece.backgroundColor = onBubble ? Color.white.opacity(0.25) : Color.accentColor.opacity(0.16)
                if !onBubble { piece.foregroundColor = Color.accentColor }
            }
            if run.spoiler, !revealed {
                piece.foregroundColor = .clear
                piece.backgroundColor = onBubble ? Color.white.opacity(0.55) : Color.secondary.opacity(0.55)
                piece.link = nil
            }
            result.append(piece)
        }
        return result
    }
}
