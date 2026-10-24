// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// Who is typing in the open chat, above the composer (01 §4's BrandTypingIndicator): "Ana is typing…" or "3 people
/// are typing…", after three dots that pulse. Nothing at all when no one is (`ConversationModel.typingLine`, the
/// chat's row's words). VoiceOver hears it, quietly, when someone starts typing in the window in front; not on every
/// change after that.
struct TypingLine: View {
    let text: String?
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        // A container that is always there, so the change is seen even while the line is not.
        VStack(spacing: 0) {
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
            }
        }
        .onChange(of: text) { old, new in
            guard let words = Self.announcement(from: old, to: new, isKey: controlActiveState == .key) else { return }
            var spoken = AttributedString(words)
            spoken.accessibilitySpeechAnnouncementPriority = .low
            AccessibilityNotification.Announcement(spoken).post()
        }
    }

    /// What to announce for a change of the line: the new line, only when it appears (no one was typing) in the
    /// window in front; nil otherwise, so a growing list or a window behind says nothing.
    static func announcement(from old: String?, to new: String?, isKey: Bool) -> String? {
        guard old == nil, isKey else { return nil }
        return new
    }
}
