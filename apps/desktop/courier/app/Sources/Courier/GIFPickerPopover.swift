// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import UniformTypeIdentifiers

/// Presents an `NSOpenPanel` restricted to GIF and MP4 files and sends or stages the chosen file on `composer`.
@MainActor
enum GIFFilePicker {
    static func run(into composer: ComposerModel) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.gif, .mpeg4Movie]
        panel.message = String(localized: "Choose a GIF or short loop to send")
        panel.prompt = String(localized: "Choose GIF")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await composer.sendGIFFile(url: url) }
    }
}

/// The GIF picker popover (`GifPicker.tsx`), showing the offline privacy notice when `gifProvider.isAvailable == false`,
/// a search filter over recent local GIFs, and a `"Choose GIF from Mac…"` button.
struct GIFPickerPopover: View {
    @ObservedObject var composer: ComposerModel

    private static let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(minimum: 120, maximum: 160), spacing: 8),
        count: 2
    )

    private var filteredRecentGIFs: [StickerItemWire] {
        let query = composer.gifSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return composer.recentGIFs }
        return composer.recentGIFs.filter { item in
            item.name.lowercased().contains(query)
                || (item.shortcode?.lowercased().contains(query) == true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            if !composer.gifProvider.isAvailable {
                offlineNoticeBanner
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            Divider()

            gifGridArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footerBar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 320, height: 320)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .task {
            if composer.stickerPacks.isEmpty && composer.recentGIFs.isEmpty {
                await composer.loadStickers(refresh: false)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search recent GIFs"), text: $composer.gifSearchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
            if !composer.gifSearchQuery.isEmpty {
                Button {
                    composer.gifSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var offlineNoticeBanner: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lock.shield")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(String(localized: "Online GIF search is disabled so nothing leaves your Mac. Choose a GIF file or pick a recent GIF below."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    @ViewBuilder
    private var gifGridArea: some View {
        let items = filteredRecentGIFs
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text(
                    composer.gifSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? String(localized: "No recent GIFs")
                        : String(localized: "No matching GIFs")
                )
                .font(.callout.weight(.medium))
                Text(String(localized: "Choose a GIF or MP4 loop from your Mac below."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(16)
        } else {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(items) { item in
                        GIFCellView(
                            item: item,
                            thumbnailLoader: composer.thumbnailLoader,
                            isEnabled: composer.canSendGIF
                        ) {
                            Task { await composer.selectGIF(item) }
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    private var footerBar: some View {
        HStack {
            Button {
                GIFFilePicker.run(into: composer)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder.badge.plus")
                        .font(.caption.weight(.semibold))
                    Text(String(localized: "Choose GIF from Mac…"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(!composer.canSendGIF)

            Spacer(minLength: 8)
        }
    }
}

private struct GIFCellView: View {
    let item: StickerItemWire
    let thumbnailLoader: ThumbnailLoader?
    let isEnabled: Bool
    let onSelect: () -> Void
    @State private var loadedThumbnail: CGImage?

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 84)

                Group {
                    if let cgImage = loadedThumbnail
                        ?? ThumbnailLoader.thumbnail(forMediaURL: item.mediaURL, maxPixelSize: 240) {
                        Image(decorative: cgImage, scale: 2.0, orientation: .up)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 84)
                            .clipped()
                    } else {
                        VStack(spacing: 4) {
                            if let emoji = item.emoji, !emoji.isEmpty {
                                Text(verbatim: emoji)
                                    .font(.system(size: 26))
                            } else {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.name)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 4) {
                    Text(verbatim: "GIF")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.68)))

                    Spacer(minLength: 0)
                }
                .padding(6)
            }
            .frame(height: 84)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.45)
        .help(item.name)
        .accessibilityLabel(item.name)
        .task(id: item.mediaURL) {
            guard loadedThumbnail == nil,
                  let loader = thumbnailLoader,
                  let path = ThumbnailLoader.resolveMediaPath(item.mediaURL)
            else { return }
            loadedThumbnail = await loader.thumbnail(atPath: path)?.image
        }
    }
}
