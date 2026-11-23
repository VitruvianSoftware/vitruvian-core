// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

/// Who is typing in the open chat, above the composer (01 §4's BrandTypingIndicator): "Ana is typing…" or "3 people
/// are typing…", after three dots that pulse. Nothing at all when no one is (`ConversationModel.typingLine`, the
/// chat's row's words). VoiceOver hears it, quietly, when someone starts typing in the window in front; not on every
/// change after that.
struct TypingLine: View {
    let text: String?
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var lastText: String?

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        let isVisible = TypingLineMotion.isVisible(text: text)
        let renderedText = text ?? lastText ?? ""
        let fadeAnimation = TypingLineMotion.fadeCurve
            .swiftUIAnimation(duration: TypingLineMotion.effectiveFadeDuration(reduceMotion: reduceMotionEnabled))

        // Always reserves its slot so showing or hiding the line never changes the height above the composer.
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .symbolEffect(
                        .variableColor.iterative,
                        options: .repeating,
                        isActive: TypingLineMotion.animatesDots(isVisible: isVisible, reduceMotion: reduceMotionEnabled)
                    )
                    .accessibilityHidden(true)
                Text(renderedText.isEmpty ? " " : renderedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: TypingLineMotion.reservedHeight, alignment: .leading)
            .opacity(TypingLineMotion.opacity(text: text))
            .animation(fadeAnimation, value: isVisible)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityHidden(!isVisible)
        }
        .onAppear {
            if let text {
                lastText = text
            }
        }
        .onChange(of: text) { old, new in
            if let new {
                lastText = new
            }
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
