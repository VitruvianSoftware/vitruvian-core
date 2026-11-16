// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// A link-style button for a routine action ("Add Participants…", "See All", "Show more").
///
/// It is plain label text, never the accent colour. The accent is the person's chosen brand colour and can be red;
/// an accent-coloured link would then look like **Leave Group…** or **Delete Chat…**. Without the colour, the cue
/// that it is a link is the underline under the pointer, and, for keyboard users, the underline plus an outline
/// while it has keyboard focus. Put a symbol in the label in `.secondary`. Destructive actions stay system red with
/// their own symbols, and primary buttons keep the accent.
struct RoutineLinkButtonStyle: ButtonStyle {
    /// Whether the label is underlined: under the pointer, or while it has keyboard focus.
    static func isUnderlined(hovered: Bool, focused: Bool) -> Bool {
        hovered || focused
    }

    func makeBody(configuration: Configuration) -> some View {
        RoutineLinkLabel(configuration: configuration)
    }

    /// The styled label. A separate view because the hover state needs `@State`, which a style cannot hold, and
    /// because focus is read from the environment of the button's own view.
    struct RoutineLinkLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .underline(RoutineLinkButtonStyle.isUnderlined(hovered: isHovered, focused: isFocused))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .padding(.horizontal, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(isFocused ? 0.5 : 0), lineWidth: 1.5)
                )
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == RoutineLinkButtonStyle {
    static var routineLink: RoutineLinkButtonStyle { RoutineLinkButtonStyle() }
}
