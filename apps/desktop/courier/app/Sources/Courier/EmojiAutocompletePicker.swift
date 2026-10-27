// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

public struct EmojiItemRow: View {
    public let candidate: EmojiCandidate
    public let isSelected: Bool
    public let thumbnailLoader: ThumbnailLoader?
    @State private var loadedImage: CGImage?

    public init(
        candidate: EmojiCandidate,
        isSelected: Bool,
        thumbnailLoader: ThumbnailLoader? = .shared
    ) {
        self.candidate = candidate
        self.isSelected = isSelected
        self.thumbnailLoader = thumbnailLoader
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let glyph = candidate.glyph {
                Text(glyph)
                    .font(.system(size: 18))
                    .frame(width: 20, height: 20)
            } else if let cgImage = loadedImage
                ?? ThumbnailLoader.thumbnail(forMediaURL: candidate.mediaURL, maxPixelSize: 40) {
                Image(decorative: cgImage, scale: 2.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "face.smiling")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                    .frame(width: 20, height: 20)
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
        .task(id: candidate.mediaURL) {
            guard candidate.glyph == nil,
                  let loader = thumbnailLoader,
                  let path = ThumbnailLoader.resolveMediaPath(candidate.mediaURL)
            else { return }
            loadedImage = await loader.thumbnail(atPath: path)?.image
        }
    }
}

public struct EmojiAutocompletePicker: View {
    public let query: String
    public let candidates: [EmojiCandidate]
    public let selectedIndex: Int
    public let thumbnailLoader: ThumbnailLoader?
    public let onSelect: (EmojiCandidate) -> Void
    public let onAddCustomEmoji: (String) -> Void
    private var observedComposer: ComposerModel?

    public init(
        query: String,
        candidates: [EmojiCandidate],
        selectedIndex: Int,
        thumbnailLoader: ThumbnailLoader? = .shared,
        onSelect: @escaping (EmojiCandidate) -> Void,
        onAddCustomEmoji: @escaping (String) -> Void
    ) {
        self.query = query
        self.candidates = candidates
        self.selectedIndex = selectedIndex
        self.thumbnailLoader = thumbnailLoader
        self.onSelect = onSelect
        self.onAddCustomEmoji = onAddCustomEmoji
        self.observedComposer = nil
    }

    public init(
        composer: ComposerModel,
        thumbnailLoader: ThumbnailLoader? = nil,
        onAddCustomEmoji: ((String) -> Void)? = nil
    ) {
        self.query = composer.emojiQuery ?? ""
        self.candidates = composer.emojiCandidates
        self.selectedIndex = composer.selectedEmojiIndex
        self.thumbnailLoader = thumbnailLoader ?? composer.thumbnailLoader
        self.onSelect = { composer.pickEmoji($0) }
        self.onAddCustomEmoji = onAddCustomEmoji ?? { _ in }
        self.observedComposer = composer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { idx, item in
                        Button {
                            onSelect(item)
                        } label: {
                            EmojiItemRow(
                                candidate: item,
                                isSelected: idx == selectedIndex,
                                thumbnailLoader: thumbnailLoader
                            )
                        }
                        .buttonStyle(.plain)
                        .id(idx)
                    }
                }
            }

            if !query.isEmpty {
                if !candidates.isEmpty {
                    Divider()
                        .padding(.vertical, 2)
                }
                Button {
                    onAddCustomEmoji(query)
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
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .task {
            if let composer = observedComposer, composer.stickerPacks.isEmpty && composer.customEmojis.isEmpty {
                await composer.loadStickers(refresh: false)
            }
        }
    }
}
