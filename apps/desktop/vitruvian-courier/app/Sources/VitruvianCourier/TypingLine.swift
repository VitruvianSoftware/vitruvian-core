// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

/// Who is typing in the open chat: "Ana is typing…" or "3 people are typing…", after three dots that pulse. It is a
/// small floating pill that `ConversationView` lays over the timeline just above the composer, so it takes no room
/// when no one is typing and never changes the composer's layout. Nothing at all when no one is
/// (`ConversationModel.typingLine`, the chat's row's words). VoiceOver hears it, quietly, when someone starts typing
/// in the window in front; not on every change after that.
struct TypingLine: View {
    let text: String?
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.courierReduceMotionOverride) private var reduceMotionOverride
    /// The last words shown, kept so the pill fades out with them instead of going blank first.
    @State private var lastText: String?

    private var reduceMotionEnabled: Bool {
        courierReduceMotion(override: reduceMotionOverride, accessibility: accessibilityReduceMotion)
    }

    var body: some View {
        let isVisible = TypingLineMotion.isVisible(text: text)
        let renderedText = text ?? lastText ?? ""
        let fade = TypingLineMotion.fadeCurve
            .swiftUIAnimation(duration: TypingLineMotion.effectiveFadeDuration(reduceMotion: reduceMotionEnabled))

        HStack(spacing: 5) {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.bold))
                .symbolEffect(
                    .variableColor.iterative,
                    options: .repeating,
                    isActive: TypingLineMotion.animatesDots(isVisible: isVisible, reduceMotion: reduceMotionEnabled)
                )
                .accessibilityHidden(true)
            Text(renderedText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: TypingLineMotion.pillHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
        .frame(maxWidth: 320)
        .opacity(TypingLineMotion.opacity(text: text))
        .animation(fade, value: isVisible)
        // It floats over the timeline: it must never take a click or a scroll from what is under it.
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!isVisible)
        .onAppear {
            if let text { lastText = text }
        }
        .onChange(of: text) { old, new in
            if let new { lastText = new }
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
