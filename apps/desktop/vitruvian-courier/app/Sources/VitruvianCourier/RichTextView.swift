// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import VitruvianCourierCore
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
    var now: Date = Date()
    var detectDates = true
    /// The time (and "Edited") that sits on the end of the last line, as text: the last paragraph ends with this much
    /// room, drawn clear, so the bubble can lay the real thing over it.
    var trailingMeta: String? = nil
    /// The size of message text (the body style's 13 pt, times the font size setting and the zoom level).
    @Environment(\.courierMessagePointSize) private var pointSize
    @Environment(\.themeAccentColor) private var themeAccent

    var body: some View {
        let blocks = RichTextLayout.blocks(of: rich)
        let hasSpoiler = rich.entities.contains { $0.kind == .spoiler }
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, reservesMeta: index == blocks.count - 1)
            }
            if let trailingMeta, let last = blocks.last, last.kind == .code {
                Text(verbatim: trailingMeta).font(.caption2).hidden()
            }
        }
        .italic(italic)
        // Links take the bubble's own text colour, never the system accent (which can be red).
        .tint(linkColor)
        // A click shows the spoilers; it still selects the message, as a click anywhere on it does.
        .simultaneousGesture(TapGesture().onEnded { if hasSpoiler { revealed = true } })
        .help(hasSpoiler && !revealed ? String(localized: "Click to show the spoiler") : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RichTextLayout.spoken(rich, revealed: revealed))
    }

    @ViewBuilder
    private func blockView(_ block: RichTextLayout.Block, reservesMeta: Bool = false) -> some View {
        switch block.kind {
        case .paragraph:
            chipped(lineText(block.lines) + metaGap(reservesMeta), block.lines)
                .fixedSize(horizontal: false, vertical: true)
        case .quote:
            HStack(alignment: .top, spacing: 7) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(onBubble ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
                    .frame(width: 3)
                // Quoted text and links are a touch softer; mentions inside it set their own colour and stay full strength.
                chipped(lineText(block.lines, dimmed: true) + metaGap(reservesMeta), block.lines)
                    .foregroundStyle(onBubble ? Color.white.opacity(0.85) : Color.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .bulletList, .orderedList:
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(block.lines.enumerated()), id: \.offset) { index, line in
                    let isLastLine = reservesMeta && index == block.lines.count - 1
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: block.kind == .bulletList ? "•" : "\(index + 1).")
                            .monospacedDigit()
                            .frame(minWidth: 12, alignment: .trailing)
                        chipped(lineText([line]) + metaGap(isLastLine), [line])
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 4)
        case .code:
            ScrollView(.horizontal, showsIndicators: true) {
                Text(block.lines.map { $0.map(\.text).joined() }.joined(separator: "\n"))
                    .font(.system(size: round(pointSize * 12 / 13 * 2) / 2, design: .monospaced)) // the callout style
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(tint))
        }
    }

    /// A mention's text and the tint behind it (a test measures their contrast).
    static func mentionColors(onBubble: Bool, accent: Color) -> (text: Color, tint: Color) {
        onBubble ? (Color.white, Color.black.opacity(0.22)) : (Color.primary, accent.opacity(0.18))
    }

    /// Links, and the arrow after them, are the bubble's text colour.
    private var linkColor: Color { onBubble ? Color.white : Color.primary }

    private func metaGap(_ reserve: Bool) -> Text {
        guard reserve, let trailingMeta else { return Text(verbatim: "") }
        return Text(verbatim: "\u{2003}" + trailingMeta).font(.caption2).foregroundStyle(Color.clear)
    }

    private var tint: Color { onBubble ? Color.white.opacity(0.2) : Color.primary.opacity(0.08) }

    /// The chip behind an inline code span: a shaded, rounded patch (on a coloured bubble, a lighter one).
    private var chipFill: Color { onBubble ? Color.white.opacity(0.22) : Color.secondary.opacity(0.2) }

    /// Inline code is drawn as a rounded chip where the system can (macOS 15 on); before that, as the square tint the
    /// text style gives it.
    static var drawsCodeChips: Bool {
        if #available(macOS 15.0, *) { true } else { false }
    }

    private func hasInlineCode(_ lines: [[RichTextLayout.Run]]) -> Bool {
        lines.contains { $0.contains { $0.code && !($0.spoiler && !revealed) } }
    }

    /// `lines` as one `Text`. With inline code to chip, the code spans are marked so `CodeChipRenderer` can find them.
    private func lineText(_ lines: [[RichTextLayout.Run]], dimmed: Bool = false) -> Text {
        guard Self.drawsCodeChips, hasInlineCode(lines), #available(macOS 15.0, *) else {
            return Text(joined(lines, dimmed: dimmed))
        }
        var result = Text(verbatim: "")
        for (index, line) in lines.enumerated() {
            if index > 0 { result = result + Text(verbatim: "\n") }
            for piece in pieces(line, dimmed: dimmed, chips: true) {
                result = result + (piece.chip ? Text(piece.text).customAttribute(CodeChipAttribute()) : Text(piece.text))
            }
        }
        return result
    }

    /// `text` with a chip drawn behind each of its marked code spans, when `lines` has any.
    @ViewBuilder
    private func chipped(_ text: Text, _ lines: [[RichTextLayout.Run]]) -> some View {
        if Self.drawsCodeChips, hasInlineCode(lines), #available(macOS 15.0, *) {
            text.textRenderer(CodeChipRenderer(fill: chipFill))
        } else {
            text
        }
    }

    private func joined(_ lines: [[RichTextLayout.Run]], dimmed: Bool = false) -> AttributedString {
        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            result.append(attributed(line, dimmed: dimmed))
        }
        return result
    }

    /// One line's runs as styled text. `dimmed` (inside a quote) softens links the way the rest of the quote is softened.
    private func attributed(_ runs: [RichTextLayout.Run], dimmed: Bool = false) -> AttributedString {
        var result = AttributedString()
        for piece in pieces(runs, dimmed: dimmed, chips: false) { result.append(piece.text) }
        return result
    }

    /// One line's runs, each as styled text. `chips`: inline code is left for `CodeChipRenderer` to draw a chip behind
    /// (marked `chip`), not given a square background here.
    private func pieces(_ runs: [RichTextLayout.Run], dimmed: Bool, chips: Bool) -> [(text: AttributedString, chip: Bool)] {
        let linkColor = dimmed ? self.linkColor.opacity(0.85) : self.linkColor
        var result: [(text: AttributedString, chip: Bool)] = []
        for run in runs {
            var piece: AttributedString
            if run.link == nil, run.mention == nil, !run.code {
                piece = LinkedText.attributed(run.text, now: now, detectDates: detectDates) // addresses and future dates typed as text still open
            } else {
                piece = AttributedString(run.text)
            }
            var font = Font.system(size: pointSize, design: run.code ? .monospaced : .default)
            if run.bold { font = font.bold() } else if run.mention != nil { font = font.weight(.semibold) }
            if run.italic { font = font.italic() }
            piece.font = font
            if run.strikethrough { piece.strikethroughStyle = .single }
            let isChip = chips && run.code && !(run.spoiler && !revealed)
            if run.code && !isChip { piece.backgroundColor = tint }
            if let url = run.link {
                piece.link = url
                piece.underlineStyle = .single
                piece.foregroundColor = linkColor
            }
            if !(run.spoiler && !revealed), run.link != nil || (run.mention == nil && !run.code) {
                piece = LinkedText.decorated(piece, color: linkColor, arrowSize: round(pointSize * 0.8))
            }
            if run.mention != nil {
                // Mentions are a highlight in the theme's accent, not a link; the text stays the primary colour so it
                // reads on the tint in light and dark.
                let colors = Self.mentionColors(onBubble: onBubble, accent: themeAccent)
                // Black 22% (not white) on my own bubble: a white tint under white text couldn't reach 4.5:1.
                piece.backgroundColor = colors.tint
                piece.foregroundColor = colors.text
            }
            if run.spoiler, !revealed {
                piece.foregroundColor = .clear
                piece.backgroundColor = onBubble ? Color.white.opacity(0.55) : Color.secondary.opacity(0.55)
                piece.link = nil
            }
            result.append((piece, isChip))
        }
        return result
    }
}

/// Marks a span of inline code in a message's text, for `CodeChipRenderer`.
@available(macOS 15.0, *)
struct CodeChipAttribute: TextAttribute {}

/// Draws message text as it is, with a shaded rounded chip behind each span marked `CodeChipAttribute`: 4 pt corners,
/// reaching 2 pt past the code on each side (into the space around it). The chips are drawn first, so they sit
/// behind the text of the words beside them.
@available(macOS 15.0, *)
struct CodeChipRenderer: TextRenderer {
    var fill: Color
    var cornerRadius: CGFloat = 4
    var horizontalPadding: CGFloat = 2

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line where run[CodeChipAttribute.self] != nil {
                let rect = run.typographicBounds.rect.insetBy(dx: -horizontalPadding, dy: 0)
                context.fill(Path(roundedRect: rect, cornerRadius: cornerRadius), with: .color(fill))
            }
        }
        for line in layout { context.draw(line) }
    }
}
