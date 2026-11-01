// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// Video tile poster inside a consecutive media gallery (`GalleryVideoPoster.tsx`).
/// Shows the local poster/thumbnail (or decoded BlurHash), a centered play badge, and a formatted duration pill.
public struct GalleryVideoPoster: View {
    public let item: GalleryItem
    public let size: CGSize
    public var preloadedImage: NSImage?

    @State private var loadedCGImage: CGImage?
    @State private var failed = false

    public init(item: GalleryItem, size: CGSize, preloadedImage: NSImage? = nil) {
        self.item = item
        self.size = size
        self.preloadedImage = preloadedImage
    }

    private var decodedBlurHash: CGImage? {
        guard let hash = item.blurhash, !hash.isEmpty else { return nil }
        return BlurHashDecoder.decode(hash, width: 32, height: 32)
    }

    private var localPosterPath: String? {
        if let thumb = item.thumbnailPath, isLocalMediaStorePath(thumb) {
            return thumb
        }
        if isLocalMediaStorePath(item.mediaPath) {
            return item.mediaPath
        }
        return nil
    }

    public var body: some View {
        ZStack {
            if let preloadedImage {
                Image(nsImage: preloadedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
            } else if let loadedCGImage {
                Image(decorative: loadedCGImage, scale: 2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
            } else if let blurCG = decodedBlurHash {
                Image(decorative: blurCG, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
            } else if failed {
                ImageErrorCard(fileName: item.fileName, size: size)
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: size.width, height: size.height)
            }

            // Centered play badge
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.62))
                    .frame(width: 36, height: 36)
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: 1)
            }

            // Bottom-trailing duration pill
            if let durationText = Self.formatDuration(item.durationMS) {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        Text(durationText)
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.68)))
                    }
                }
                .padding(6)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: localPosterPath) {
            guard preloadedImage == nil else { return }
            loadedCGImage = nil
            failed = false
            guard let path = localPosterPath else { return }
            if let thumbnail = await ThumbnailLoader.shared.thumbnail(atPath: path) {
                loadedCGImage = thumbnail.image
            } else if item.blurhash == nil {
                failed = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            item.fileName.isEmpty
                ? String(localized: "Video")
                : String(localized: "Video: \(item.fileName)")
        )
    }

    public static func formatDuration(_ durationMS: Int?) -> String? {
        guard let durationMS, durationMS > 0 else { return nil }
        let totalSeconds = max(1, (durationMS + 500) / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Adaptive 2–3 column media gallery grid (`GalleryGrouper.tsx`) for 2–10 consecutive image/video messages
/// from the same sender within 60 seconds.
public struct GalleryGridView: View {
    public let message: TimelineMessage
    public var preloadedImages: [String: NSImage]
    public var onOpenLightbox: (String) -> Void

    public static let gridWidth: CGFloat = 324
    private static let spacing: CGFloat = 4

    public init(
        message: TimelineMessage,
        preloadedImages: [String: NSImage] = [:],
        onOpenLightbox: @escaping (String) -> Void = { _ in }
    ) {
        self.message = message
        self.preloadedImages = preloadedImages
        self.onOpenLightbox = onOpenLightbox
    }

    private var items: [GalleryItem] {
        message.galleryItems
    }

    private var columnCount: Int {
        switch items.count {
        case 0 ... 2, 4:
            return 2
        default:
            return 3
        }
    }

    private var tileSize: CGSize {
        let cols = CGFloat(max(columnCount, 1))
        let totalSpacing = Self.spacing * (cols - 1)
        let width = floor((Self.gridWidth - totalSpacing) / cols)
        let height = (columnCount == 2) ? round(width * 0.78) : width
        return CGSize(width: width, height: height)
    }

    public var body: some View {
        let cols = Array(
            repeating: GridItem(.fixed(tileSize.width), spacing: Self.spacing),
            count: columnCount
        )
        LazyVGrid(columns: cols, alignment: .leading, spacing: Self.spacing) {
            ForEach(items) { item in
                GalleryTileView(
                    item: item,
                    size: tileSize,
                    preloadedImage: preloadedImages[item.id],
                    onTap: { onOpenLightbox(item.id) }
                )
            }
        }
        .frame(width: Self.gridWidth, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Media gallery with \(items.count) items"))
    }
}

private struct GalleryTileView: View {
    let item: GalleryItem
    let size: CGSize
    let preloadedImage: NSImage?
    let onTap: () -> Void

    @State private var loadedCGImage: CGImage?
    @State private var failed = false

    private var decodedBlurHash: CGImage? {
        guard let hash = item.blurhash, !hash.isEmpty else { return nil }
        return BlurHashDecoder.decode(hash, width: 32, height: 32)
    }

    private var localImagePath: String? {
        if isLocalMediaStorePath(item.mediaPath) {
            return item.mediaPath
        }
        if let thumb = item.thumbnailPath, isLocalMediaStorePath(thumb) {
            return thumb
        }
        return nil
    }

    var body: some View {
        Group {
            if item.showsMediaRemovedPlaceholder {
                VStack(spacing: 4) {
                    Image(systemName: item.kind == .video ? "film" : "photo")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(TimelineMessage.mediaRemovedPlaceholderText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .frame(width: size.width, height: size.height)
                .background(Rectangle().fill(.quaternary.opacity(0.6)))
            } else if item.kind == .video {
                GalleryVideoPoster(item: item, size: size, preloadedImage: preloadedImage)
            } else {
                ZStack {
                    if failed {
                        ImageErrorCard(fileName: item.fileName, size: size)
                    } else if let preloadedImage {
                        Image(nsImage: preloadedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                    } else if let loadedCGImage {
                        Image(decorative: loadedCGImage, scale: 2)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                    } else if let blurCG = decodedBlurHash {
                        Image(decorative: blurCG, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .frame(width: size.width, height: size.height)
                    }
                    if item.isGIF {
                        VStack {
                            HStack {
                                Text("GIF")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.black.opacity(0.65)))
                                Spacer(minLength: 0)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(5)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .task(id: localImagePath) {
                    guard preloadedImage == nil else { return }
                    loadedCGImage = nil
                    failed = false
                    guard let path = localImagePath else {
                        if !item.mediaPath.isEmpty { failed = true }
                        return
                    }
                    if let thumbnail = await ThumbnailLoader.shared.thumbnail(atPath: path) {
                        loadedCGImage = thumbnail.image
                    } else {
                        failed = true
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
