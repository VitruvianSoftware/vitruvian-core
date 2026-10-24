// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Who is typing in the open chat, above the composer (01 §4's BrandTypingIndicator): "Ana is typing…" or "3 people
/// are typing…", after three dots that pulse. Nothing at all when no one is (`ConversationModel.typingLine`, the
/// chat's row's words).
struct TypingLine: View {
    let text: String?

    var body: some View {
        if let text {
            HStack(spacing: 5) {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .accessibilityHidden(true)
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
