// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore

/// What the message area shows while a chat's first page is still on its way. The chat's header and composer have
/// switched already. For the first `TimelineLoadMotion.placeholderDelay` the pane is plain; then message-shaped
/// bars fade in (they just appear under Reduce Motion), bottom-aligned where the real messages will land. It is
/// replaced by the timeline, which starts at the same bottom edge, so nothing jumps when the page arrives.
struct TimelinePlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isShown = false

    private var reduceMotion: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                ForEach(Array(TimelineLoadMotion.placeholderRows().enumerated()), id: \.offset) { _, row in
                    HStack {
                        if row.fromMe { Spacer(minLength: 0) }
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.primary.opacity(row.fromMe ? 0.07 : 0.05))
                            .frame(width: max(60, proxy.size.width * row.widthFraction), height: 12 + CGFloat(row.lines) * 16)
                        if !row.fromMe { Spacer(minLength: 0) }
                    }
                }
            }
            .padding(.horizontal, TimelineTableMetrics.horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: TimelineLoadMotion.placeholderDelay)
            guard !Task.isCancelled else { return }
            if reduceMotion {
                isShown = true
            } else {
                withAnimation(.easeOut(duration: TimelineLoadMotion.placeholderFadeDuration)) { isShown = true }
            }
        }
    }
}
