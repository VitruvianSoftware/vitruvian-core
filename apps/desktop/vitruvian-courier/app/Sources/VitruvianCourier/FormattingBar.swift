// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// The formatting bar over the composer while text is selected (01 §6, "Show formatting menu" in Settings ▸
/// Messages): Bold, Italic, Strikethrough, Code, Code Block, Quote, Bulleted List, Numbered List, Link, Spoiler. A
/// kind the chat doesn't keep is greyed, its tooltip saying so ("Spoiler (Unavailable for WhatsApp)").
struct FormattingBarView: View {
    let items: [FormattingItem]
    let choose: (TextEntity.Kind) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button { choose(item.kind) } label: {
                    Image(systemName: Self.symbol(item.kind))
                        .foregroundStyle(item.isEnabled ? Color.primary : Color.secondary.opacity(0.45))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
                .help(item.help)
                .accessibilityLabel(item.title)
                if item.kind == .strikethrough || item.kind == .pre || item.kind == .orderedList {
                    Divider().frame(height: 16)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Formatting"))
    }

    static func symbol(_ kind: TextEntity.Kind) -> String {
        switch kind {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .pre: "curlybraces.square"
        case .blockquote: "text.quote"
        case .bulletList: "list.bullet"
        case .orderedList: "list.number"
        case .link: "link"
        case .spoiler: "eye.slash"
        case .mention: "at"
        }
    }
}
