// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import UniformTypeIdentifiers

/// Presents an `NSOpenPanel` for importing a local PNG, WebP, or GIF sticker into Courier's sticker catalog.
@MainActor
enum StickerImportPicker {
    static func run(into composer: ComposerModel, shortcode: String? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .webP, .gif, .jpeg]
        panel.message = String(localized: "Choose a PNG, WebP, GIF, or JPEG image to import as a sticker")
        panel.prompt = String(localized: "Import Sticker…")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await composer.importSticker(from: url, shortcode: shortcode)
        }
    }
}

/// Sticker picker popover (`StickerPicker.tsx`): pack selector tabs (`Recent`, `Imported`, and bridge packs with
/// network badge), search bar, 4-column grid of 64×64 pt sticker cells, empty state, and `"Import Sticker…"` +
/// `"Sync Packs"` footer controls.
public struct StickerPickerPopover: View {
    @ObservedObject public var composer: ComposerModel
    public var thumbnailLoader: ThumbnailLoader?
    public var onImportSticker: (() -> Void)?

    private static let gridColumns = Array(repeating: GridItem(.fixed(64), spacing: 8), count: 4)

    public init(
        composer: ComposerModel,
        thumbnailLoader: ThumbnailLoader? = nil,
        onImportSticker: (() -> Void)? = nil
    ) {
        self.composer = composer
        self.thumbnailLoader = thumbnailLoader ?? composer.thumbnailLoader
        self.onImportSticker = onImportSticker
    }

    public static func stickerItems(in pack: StickerPackWire) -> [StickerItemWire] {
        pack.items.filter { $0.usage.isEmpty || $0.usage.contains("sticker") }
    }

    private var displayedPacks: [StickerPackWire] {
        if composer.stickerPacks.isEmpty {
            return [
                StickerPackWire(id: "recent", title: String(localized: "Recent"), source: "recent", items: []),
                StickerPackWire(id: "imported", title: String(localized: "Imported"), source: "imported", items: []),
            ]
        }
        return composer.stickerPacks
    }

    private var activePack: StickerPackWire? {
        displayedPacks.first(where: { $0.id == composer.selectedStickerPackID }) ?? displayedPacks.first
    }

    private var filteredItems: [StickerItemWire] {
        let query = composer.stickerSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return activePack.map(Self.stickerItems(in:)) ?? []
        }
        var seen = Set<String>()
        var matches: [StickerItemWire] = []
        for pack in displayedPacks {
            for item in Self.stickerItems(in: pack) {
                guard seen.insert(item.id).inserted else { continue }
                if item.name.localizedCaseInsensitiveContains(query)
                    || item.shortcode?.localizedCaseInsensitiveContains(query) == true
                    || item.emoji?.localizedCaseInsensitiveContains(query) == true {
                    matches.append(item)
                }
            }
        }
        return matches
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            packTabsBar
            searchBar
            Divider()
            stickerGridSection
            Divider()
            footerBar
        }
        .padding(12)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .task {
            if composer.stickerPacks.isEmpty {
                await composer.loadStickers(refresh: false)
            }
        }
    }

    private var packTabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(displayedPacks) { pack in
                    let isSelected = (activePack?.id ?? "recent") == pack.id
                    Button {
                        composer.selectedStickerPackID = pack.id
                    } label: {
                        HStack(spacing: 5) {
                            if let network = pack.network, !network.isEmpty {
                                NetworkBadge(
                                    network: network,
                                    name: NetworkNames.displayName(of: network) ?? network,
                                    size: 12
                                )
                            }
                            Text(localizedPackTitle(pack))
                                .font(.caption.weight(isSelected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected ? Color.accentColor.opacity(0.45) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func localizedPackTitle(_ pack: StickerPackWire) -> String {
        switch pack.id {
        case "recent":
            return String(localized: "Recent")
        case "imported":
            return String(localized: "Imported")
        default:
            return pack.title
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search stickers"), text: $composer.stickerSearchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
            if !composer.stickerSearchQuery.isEmpty {
                Button {
                    composer.stickerSearchQuery = ""
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
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var stickerGridSection: some View {
        let items = filteredItems
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text(
                    composer.stickerSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? String(localized: "No stickers yet")
                        : String(localized: "No matching stickers")
                )
                .font(.callout.weight(.semibold))
                Text(String(localized: "Import a PNG, WebP, or GIF image, or sync packs from a connected network."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
        } else {
            ScrollView {
                LazyVGrid(columns: Self.gridColumns, spacing: 8) {
                    ForEach(items) { item in
                        StickerCellView(
                            item: item,
                            thumbnailLoader: thumbnailLoader
                        ) {
                            Task {
                                await composer.sendSticker(item)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
        }
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            Button {
                if let onImportSticker {
                    onImportSticker()
                } else {
                    StickerImportPicker.run(into: composer)
                }
            } label: {
                Label(String(localized: "Import Sticker…"), systemImage: "plus.circle")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            Spacer(minLength: 0)

            Button {
                Task {
                    await composer.loadStickers(refresh: true)
                }
            } label: {
                Label(String(localized: "Sync Packs"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

private struct StickerCellView: View {
    let item: StickerItemWire
    let thumbnailLoader: ThumbnailLoader?
    let onSelect: () -> Void

    @State private var loadedImage: CGImage?
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.12 : 0.05))
                if let cgImage = loadedImage {
                    Image(decorative: cgImage, scale: 2.0, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                } else {
                    VStack(spacing: 2) {
                        if let emoji = item.emoji, !emoji.isEmpty {
                            Text(emoji)
                                .font(.system(size: 28))
                        } else {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 22))
                                .foregroundStyle(.secondary)
                        }
                        Text(item.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(item.name)
        .accessibilityLabel(item.name)
        .task(id: item.mediaURL) {
            guard loadedImage == nil,
                  let path = ThumbnailLoader.resolveMediaPath(item.mediaURL)
            else { return }
            let loader = thumbnailLoader ?? .shared
            loadedImage = await loader.thumbnail(atPath: path)?.image
        }
    }
}
