// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import UniformTypeIdentifiers

/// Presents an `NSOpenPanel` restricted to GIF and MP4 files and sends or stages the chosen file on `composer`.
@MainActor
enum GIFFilePicker {
    static func run(into composer: ComposerModel) {
        guard let url = AppLockGate.shared.runOpenPanel(action: .send, lifecycle: composer.lifecycle, configure: { panel in
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.gif, .mpeg4Movie]
            panel.message = String(localized: "Choose a GIF or short loop to send")
            panel.prompt = String(localized: "Choose GIF")
        })?.first else { return }
        Task { await composer.sendGIFFile(url: url) }
    }
}

/// The GIF picker, a strip in the chat just above the message box (not a pop-over that spills over the inbox): a
/// search box on top, the GIFs in a row that scrolls sideways, and "Choose GIF from Mac…". With "Search GIFs online" on
/// (and a key in this build) it shows the GIFs I sent or chose before, then what is trending, and searches the GIF
/// service for what is typed. With it off, only the recent GIFs, filtered by what is typed. Choosing a GIF attaches it
/// to the draft as any GIF is; it is never sent by this alone. Escape closes the strip.
struct GIFPickerStrip: View {
    @ObservedObject var composer: ComposerModel
    @FocusState private var searchFocused: Bool

    static let height: CGFloat = 220
    private static let tileHeight: CGFloat = 138

    enum Entry: Identifiable {
        case recent(StickerItemWire)
        case online(GIFCandidate)

        var id: String {
            switch self {
            case let .recent(item): "recent:\(item.id)"
            case let .online(candidate): "online:\(candidate.id)"
            }
        }
    }

    private var query: String {
        composer.gifSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentMatches: [StickerItemWire] {
        guard !query.isEmpty else { return composer.recentGIFs }
        let needle = query.lowercased()
        return composer.recentGIFs.filter { item in
            item.name.lowercased().contains(needle) || (item.shortcode?.lowercased().contains(needle) == true)
        }
    }

    /// What the row shows: online, the recent GIFs (with no search typed) and then the service's; offline, the recent.
    private var entries: [Entry] {
        if composer.canSearchGIFsOnline {
            let recent = query.isEmpty ? composer.recentGIFs.map(Entry.recent) : []
            return recent + composer.gifResults.map(Entry.online)
        }
        return recentMatches.map(Entry.recent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)
            row
                .frame(maxWidth: .infinity)
                .frame(height: Self.tileHeight + 10)
            captionBar
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onExitCommand { composer.isGIFPickerPresented = false }
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        .task { await composer.loadStickers(refresh: false) }
        // A search waits for a pause in typing; an empty box (trending) and a setting change do not wait.
        .task(id: "\(composer.gifSearchQuery)|\(composer.canSearchGIFsOnline)") {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await composer.refreshGIFResults()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "GIF picker"))
        .accessibilityIdentifier("composer.gifPicker")
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            searchField
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
            Button {
                composer.isGIFPickerPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Close (Esc)"))
            .accessibilityLabel(String(localized: "Close GIF picker"))
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                composer.canSearchGIFsOnline ? String(localized: "Search GIFs") : String(localized: "Search recent GIFs"),
                text: $composer.gifSearchQuery
            )
            .textFieldStyle(.plain)
            .font(.callout)
            .focused($searchFocused)
            .accessibilityIdentifier("composer.gifPicker.search")
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
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }

    @ViewBuilder
    private var row: some View {
        let shown = entries
        if shown.isEmpty {
            emptyState
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 8) {
                    ForEach(shown) { entry in
                        GIFTile(entry: entry, composer: composer, height: Self.tileHeight) {
                            switch entry {
                            case let .recent(item): Task { await composer.selectGIF(item) }
                            case let .online(candidate): Task { await composer.selectGIFCandidate(candidate) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 5) {
            if composer.canSearchGIFsOnline, composer.gifResultsState == .loading {
                ProgressView().controlSize(.small)
                Text(String(localized: "Finding GIFs…"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if case let .failed(reason) = composer.gifResultsState, composer.canSearchGIFsOnline {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text(query.isEmpty ? String(localized: "No recent GIFs") : String(localized: "No matching GIFs"))
                    .font(.callout.weight(.medium))
                Text(String(localized: "Choose a GIF or MP4 loop from your Mac."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var captionBar: some View {
        HStack(spacing: 6) {
            Text(captionText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if composer.canSearchGIFsOnline {
                Text(String(localized: "Powered by KLIPY"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var captionText: String {
        if !composer.canSearchGIFsOnline {
            if composer.gifProvider.isAvailable {
                return String(localized: "Online GIF search is off, so nothing leaves your Mac.")
            }
            return String(localized: "Online GIF search is disabled so nothing leaves your Mac.")
        }
        if query.isEmpty { return String(localized: "Your recent GIFs, then trending") }
        return String(format: String(localized: "Results for “%@”"), query)
    }
}

/// One GIF in the strip: a small preview that plays (a GIF, or an online GIF's preview) or at least shows its first
/// frame (an MP4 loop), never a play icon with a file name.
private struct GIFTile: View {
    let entry: GIFPickerStrip.Entry
    @ObservedObject var composer: ComposerModel
    let height: CGFloat
    let onSelect: () -> Void

    /// A GIF bigger than this shows its first frame, so a strip of big files stays light.
    private static let animationLimit = 8 * 1024 * 1024

    @State private var animatedPath: String?
    @State private var still: CGImage?
    @State private var didFinishLoading = false
    /// Width over height, read from the file once it is known; until then the provider's size, or a square.
    @State private var measuredAspect: CGFloat?

    private var title: String {
        switch entry {
        case let .recent(item): item.name
        case let .online(candidate): candidate.title
        }
    }

    private var width: CGFloat {
        if let measuredAspect { return min(max(height * measuredAspect, 70), 260) }
        let size: (Int?, Int?)
        switch entry {
        case let .recent(item): size = (item.width, item.height)
        case let .online(candidate): size = (candidate.width, candidate.height)
        }
        guard let w = size.0, let h = size.1, w > 0, h > 0 else { return height }
        return min(max(height * CGFloat(w) / CGFloat(h), 70), 260)
    }

    private var isDownloading: Bool {
        if case let .online(candidate) = entry { return composer.downloadingGIFID == candidate.id }
        return false
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                if let animatedPath {
                    AnimatedGIFImage(path: animatedPath)
                        .allowsHitTesting(false)
                } else if let still {
                    Image(decorative: still, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFill()
                } else if !didFinishLoading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if isDownloading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.35))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!composer.canSendGIF || composer.downloadingGIFID != nil)
        .opacity(composer.canSendGIF ? 1.0 : 0.45)
        .help(title)
        .accessibilityLabel(title)
        .task(id: entry.id) { await load() }
    }

    private func load() async {
        defer { didFinishLoading = true }
        switch entry {
        case let .recent(item):
            guard let path = ThumbnailLoader.resolveMediaPath(item.mediaURL) else { return }
            let kind = await Task.detached { LoopFileKind.detect(atPath: path) }.value
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            let loader = composer.thumbnailLoader ?? .shared
            if kind == .gif, size > 0, size <= Self.animationLimit {
                animatedPath = path
                measuredAspect = await aspect(ofFileAt: path, loader: loader)
            } else if let picture = await loader.loopThumbnail(atPath: path)?.image {
                still = picture
                measuredAspect = CGFloat(picture.width) / CGFloat(max(picture.height, 1))
            }
        case let .online(candidate):
            if let file = await composer.gifPreviewFile(for: candidate) {
                animatedPath = file.path
                measuredAspect = await aspect(ofFileAt: file.path, loader: composer.thumbnailLoader ?? .shared)
            }
        }
    }
}

private func aspect(ofFileAt path: String, loader: ThumbnailLoader) async -> CGFloat? {
    guard let size = await loader.pixelSize(atPath: path), size.width > 0, size.height > 0 else { return nil }
    return size.width / size.height
}

/// An animated GIF from a file, filling its frame. It does not take clicks: the tile's button does.
private struct AnimatedGIFImage: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        view.isEditable = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = NSImage(contentsOfFile: path)
        context.coordinator.path = path
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard context.coordinator.path != path else { return }
        context.coordinator.path = path
        view.image = NSImage(contentsOfFile: path)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var path = ""
    }
}
