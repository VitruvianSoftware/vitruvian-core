// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

struct EmojiItemRow: View {
    let candidate: EmojiCandidate
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let glyph = candidate.glyph {
                Text(glyph)
                    .font(.system(size: 18))
                    .frame(width: 22, height: 22)
            } else if let cgImage = ThumbnailLoader.thumbnail(forMediaURL: candidate.mediaURL, maxPixelSize: 44) {
                Image(decorative: cgImage, scale: 2.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "face.smiling")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                    .frame(width: 22, height: 22)
            }

            Text(":\(candidate.shortcode):")
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if candidate.isCustom {
                Text(String(localized: "Custom"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

struct EmojiAutocompletePicker: View {
    @ObservedObject var composer: ComposerModel
    var onAddCustomEmoji: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !composer.emojiCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(composer.emojiCandidates.enumerated()), id: \.element.id) { idx, item in
                        Button {
                            composer.pickEmoji(item)
                        } label: {
                            EmojiItemRow(candidate: item, isSelected: idx == composer.selectedEmojiIndex)
                        }
                        .buttonStyle(.plain)
                        .id(idx)
                    }
                }
            }

            if let query = composer.emojiQuery, !query.isEmpty {
                if !composer.emojiCandidates.isEmpty {
                    Divider()
                        .padding(.vertical, 2)
                }
                Button {
                    onAddCustomEmoji?(query)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text(String(format: String(localized: "Add :%@: to Custom Emoji"), query))
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    }
}
