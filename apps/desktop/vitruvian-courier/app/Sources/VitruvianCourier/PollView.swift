// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// A poll in its bubble (01 §5's Poll chunk): the question, what to select, each option with a radio (one answer)
/// or a tick (more), its votes and a bar, and how many voted. Clicking an option votes; clicking my one answer again
/// takes the vote back. An ended poll is shown as it stood, and takes no votes.
struct PollView: View {
    let poll: PollTally
    let onBubble: Bool
    /// The options chosen now ([] takes the vote back).
    let vote: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(poll.question)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(MessageLines.pollHint(poll))
                    .font(.caption)
                    .opacity(0.75)
            }
            ForEach(poll.options) { option in
                // An ended poll reads as it stood, not greyed; it just takes no clicks.
                Button { choose(option.id) } label: { row(option) }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!poll.ended)
            }
            Text(MessageLines.votes(poll.voters))
                .font(.caption)
                .opacity(0.75)
        }
        .frame(minWidth: 220, idealWidth: 280, maxWidth: 320, alignment: .leading)
    }

    private var many: Bool { poll.maxSelections > 1 }

    private func row(_ option: PollOption) -> some View {
        let chosen = poll.mine.contains(option.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: many ? (chosen ? "checkmark.square.fill" : "square")
                    : (chosen ? "largecircle.fill.circle" : "circle"))
                Text(option.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(verbatim: "\(option.votes)")
                    .font(.callout.monospacedDigit())
                    .opacity(0.8)
            }
            Capsule()
                .fill(onBubble ? Color.white.opacity(0.25) : Color.primary.opacity(0.1))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(onBubble ? Color.white : Color.accentColor)
                            .frame(width: geometry.size.width * MessageLines.share(of: option, in: poll))
                    }
                }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    private func choose(_ id: String) {
        var chosen = poll.mine
        if many {
            if let index = chosen.firstIndex(of: id) { chosen.remove(at: index) } else { chosen.append(id) }
        } else {
            chosen = chosen == [id] ? [] : [id]
        }
        vote(chosen)
    }
}
