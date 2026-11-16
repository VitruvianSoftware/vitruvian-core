// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// A link-style button for a routine action ("Add Participants…", "See All", "Show more").
///
/// It is plain label text, underlined under the pointer, never the accent colour. The accent is the person's chosen
/// brand colour and can be red; an accent-coloured link would then look like **Leave Group…** or **Delete Chat…**.
/// Put a symbol in the label in `.secondary`. Destructive actions stay system red with their own symbols, and
/// primary buttons keep the accent.
struct RoutineLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoutineLinkLabel(configuration: configuration)
    }

    /// The styled label. A separate view because the hover state needs `@State`, which a style cannot hold.
    struct RoutineLinkLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(.primary)
                .underline(isHovered)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == RoutineLinkButtonStyle {
    static var routineLink: RoutineLinkButtonStyle { RoutineLinkButtonStyle() }
}
