// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Full-pane drag-and-drop overlay (`FileDropOverlay.tsx`) displayed when dragging files over `ConversationView`.
public struct FileDropOverlayView: View {
    public let isShiftHeld: Bool

    public static let userVisibleStrings: [String] = [
        String(localized: "Drop files to attach to your message"),
        String(localized: "Hold ⇧ Shift to send immediately"),
        String(localized: "Release to send immediately"),
    ]

    public init(isShiftHeld: Bool = false) {
        self.isShiftHeld = isShiftHeld
    }

    public var body: some View {
        ZStack {
            Color.accentColor.opacity(isShiftHeld ? 0.16 : 0.10)
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .padding(10)

            VStack(spacing: 8) {
                Image(systemName: isShiftHeld ? "paperplane.fill" : "paperclip.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(String(localized: "Drop files to attach to your message"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Image(systemName: isShiftHeld ? "bolt.fill" : "shift")
                        .font(.caption.weight(.semibold))
                    Text(
                        isShiftHeld
                            ? String(localized: "Release to send immediately")
                            : String(localized: "Hold ⇧ Shift to send immediately")
                    )
                    .font(.callout.weight(.medium))
                }
                .foregroundStyle(isShiftHeld ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        isShiftHeld ? Color.accentColor : Color.primary.opacity(0.08)
                    )
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            )
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isShiftHeld
                ? String(localized: "Drop files to attach to your message. Release to send immediately.")
                : String(localized: "Drop files to attach to your message. Hold ⇧ Shift to send immediately.")
        )
    }
}
