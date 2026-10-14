// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// A tool's status mark on the closed island, as the app draws it: the
/// glyph, its size, weight, colour and motion, and what VoiceOver says.
/// Plain values, so the tests check a mark without drawing it.
///
/// The look is the built-in GitHub mark's (`NotchGitHubRestingIndicator`),
/// number for number: the tool chooses the state and may choose the glyph,
/// and everything else is the app's.
package struct ToolStatusMarkContent: Equatable, Sendable {
    package enum Weight: Equatable, Sendable {
        case bold, medium
    }

    package enum Tint: Equatable, Sendable {
        case green, orange, yellow, red
    }

    /// The breathing of a `busy` mark, as the built-in amber mark breathes:
    /// between these scales and opacities, this many seconds each way.
    package static let breathingScale: ClosedRange<Double> = 0.9...1.15
    package static let breathingOpacity: ClosedRange<Double> = 0.65...1.0
    package static let breathingSeconds = 0.9

    /// An SF Symbol name: the tool's own when this Mac has it, else the
    /// state's.
    package let symbol: String
    package let pointSize: Double
    package let weight: Weight
    package let tint: Tint
    /// True for `busy` alone. With Reduce Motion on the mark is still, at
    /// the small, dim end.
    package let breathes: Bool
    /// The tool's name, a colon, and the tool's words for its status as one
    /// short line, or the app's word for the state when the tool gave none.
    /// For VoiceOver and the tooltip.
    package let label: String

    /// `status` is never `none`: a tool with no status has no mark.
    /// `toolName` is the tool's name in the person's language. `hasSymbol`
    /// says whether this Mac has a symbol of that name.
    package init(_ status: ToolStatus, toolName: String, language: AppLanguage, strings: ExternalToolStrings,
                 hasSymbol: (String) -> Bool = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }) {
        let own: String
        switch status.state {
        case .ok, .none:
            (own, pointSize, weight, tint) = ("checkmark", 8, .bold, .green)
        case .busy:
            (own, pointSize, weight, tint) = ("arrow.triangle.2.circlepath", 9, .medium, .orange)
        case .attention:
            (own, pointSize, weight, tint) = ("exclamationmark.circle.fill", 8, .bold, .yellow)
        case .failure:
            (own, pointSize, weight, tint) = ("exclamationmark.triangle.fill", 8, .bold, .red)
        }
        breathes = status.state == .busy
        let asked = status.icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        symbol = !asked.isEmpty && hasSymbol(asked) ? asked : own
        let said = status.text?.text(for: language.rawValue).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let words = said.isEmpty ? strings.mark(status.state) ?? "" : ToolOwnWords.oneLine(said)
        label = ToolOwnWords.oneLine(toolName) + Self.colon(in: language) + words
    }

    /// What stands between the tool's name and its words. The app's
    /// strings write a colon the way each language does; this is the same
    /// rule, for a label made of two of the tool's own texts.
    static func colon(in language: AppLanguage) -> String {
        switch language {
        case .fr: return "\u{00A0}: "
        case .ja, .zhHans, .zhTW, .zhHK: return "："
        default: return ": "
        }
    }
}

/// A tool's status mark, drawn in the closed island's wing with exactly
/// the modifiers the built-in GitHub mark has for the matching verdict.
package struct ToolStatusMark: View {
    package let content: ToolStatusMarkContent

    package init(content: ToolStatusMarkContent) {
        self.content = content
    }

    package var body: some View {
        Group {
            if content.breathes {
                // A view of its own, so that the breathing starts again each
                // time a busy mark takes another one's place.
                Breathing(content: content)
            } else {
                glyph(content)
            }
        }
        .accessibilityLabel(Text(verbatim: content.label))
        .help(Text(verbatim: content.label))
    }

    private struct Breathing: View {
        let content: ToolStatusMarkContent
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var breathing = false

        var body: some View {
            let scale = ToolStatusMarkContent.breathingScale
            let opacity = ToolStatusMarkContent.breathingOpacity
            glyph(content)
                .scaleEffect(breathing && !reduceMotion ? scale.upperBound : scale.lowerBound)
                .opacity(breathing && !reduceMotion ? opacity.upperBound : opacity.lowerBound)
                .onAppear {
                    withAnimation(.easeInOut(duration: ToolStatusMarkContent.breathingSeconds)
                        .repeatForever(autoreverses: true)) {
                        breathing = true
                    }
                }
        }
    }
}

@MainActor
private func glyph(_ content: ToolStatusMarkContent) -> some View {
    Image(systemName: content.symbol)
        .font(.system(size: content.pointSize, weight: content.weight == .bold ? .bold : .medium))
        .foregroundStyle(color(content.tint))
}

private func color(_ tint: ToolStatusMarkContent.Tint) -> Color {
    switch tint {
    case .green: return .green
    case .orange: return .orange
    case .yellow: return .yellow
    case .red: return .red
    }
}
