// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// How big a file is, for people.
enum FileSize {
    static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Default `QLPreviewPanel`-backed controller for `QuickLookPreviewCoordinator`.
@MainActor
public final class SystemQuickLookPanelController: QuickLookPanelControlling {
    public private(set) var isVisible = false

    public init() {}

    public func presentPreview(for coordinator: AnyObject) {
        isVisible = true
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = coordinator as? any QLPreviewPanelDataSource
        panel.delegate = coordinator as? any QLPreviewPanelDelegate
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    public func closePreview() {
        isVisible = false
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else { return }
        panel.orderOut(nil)
        panel.close()
    }
}

/// Coordinates macOS Quick Look (`QLPreviewPanel`) for local, quarantined attachment copies.
@MainActor
public final class QuickLookPreviewCoordinator: NSObject, QuickLookPreviewCoordinating, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = QuickLookPreviewCoordinator()
    private var previewURL: URL?
    public let panelController: any QuickLookPanelControlling
    private var lockObserver: NSObjectProtocol?

    public var currentPreviewURL: URL? { previewURL }

    public init(panelController: (any QuickLookPanelControlling)? = nil) {
        self.panelController = panelController ?? SystemQuickLookPanelController()
        super.init()
        AppLockGate.shared.registerQuickLookCoordinator(self)
        lockObserver = NotificationCenter.default.addObserver(
            forName: SystemLifecycleModel.didLockNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closeForAppLock()
            }
        }
    }

    deinit {
        if let lockObserver {
            NotificationCenter.default.removeObserver(lockObserver)
        }
    }

    public func preview(url: URL) {
        guard AppLockGate.shared.canPerform(.other), url.isFileURL else { return }
        previewURL = url
        panelController.presentPreview(for: self)
    }

    public func closeForAppLock() {
        guard previewURL != nil || panelController.isVisible else { return }
        previewURL = nil
        panelController.closePreview()
    }

    func preview(fileAtPath path: String, suggestedName: String = "") {
        guard AppLockGate.shared.canPerform(.other), isLocalMediaStorePath(path) else { return }
        let source = URL(fileURLWithPath: path)
        Task.detached(priority: .userInitiated) {
            let resolved = (try? OpenFileCache.shared.prepare(
                source: source,
                fileName: suggestedName,
                mimeType: ""
            )) ?? source
            await MainActor.run {
                guard AppLockGate.shared.canPerform(.other) else { return }
                QuickLookPreviewCoordinator.shared.preview(url: resolved)
            }
        }
    }

    public nonisolated func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            previewURL == nil ? 0 : 1
        }
    }

    public nonisolated func previewPanel(_: QLPreviewPanel!, previewItemAt _: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            previewURL as NSURL?
        }
    }
}

/// Opens or downloads a received file from the engine's local media store.
/// The engine's copy has no name or extension, so a copy under its real name is made first (see `OpenFileCache`)
/// when opening or previewing, and `AttachmentDownloader` copies to the configured Downloads folder.
/// View-once media and remote URLs are never opened or downloaded here.
enum ReceivedFile {
    @MainActor
    static func open(_ message: TimelineMessage) {
        guard AppLockGate.shared.canPerform(.other), !message.viewOnce, isLocalMediaStorePath(message.mediaPath) else { return }
        let source = URL(fileURLWithPath: message.mediaPath)
        let name = message.fileName
        let mime = message.mimeType
        Task.detached(priority: .userInitiated) {
            do {
                let copy = try OpenFileCache.shared.prepare(source: source, fileName: name, mimeType: mime)
                await MainActor.run {
                    guard AppLockGate.shared.canPerform(.other), copy.isFileURL else { return }
                    _ = NSWorkspace.shared.open(copy)
                }
            } catch {
                await MainActor.run { NSSound.beep() }
            }
        }
    }

    @MainActor
    static func quickLook(_ message: TimelineMessage) {
        guard AppLockGate.shared.canPerform(.other), !message.viewOnce, isLocalMediaStorePath(message.mediaPath) else { return }
        let source = URL(fileURLWithPath: message.mediaPath)
        let name = message.fileName
        let mime = message.mimeType
        Task.detached(priority: .userInitiated) {
            do {
                let copy = try OpenFileCache.shared.prepare(source: source, fileName: name, mimeType: mime)
                await MainActor.run {
                    guard AppLockGate.shared.canPerform(.other) else { return }
                    QuickLookPreviewCoordinator.shared.preview(url: copy)
                }
            } catch {
                await MainActor.run { NSSound.beep() }
            }
        }
    }

    @MainActor
    @discardableResult
    static func download(
        _ message: TimelineMessage,
        preferences: ComposerPreferences = ComposerPreferences()
    ) -> URL? {
        guard !message.viewOnce, isLocalMediaStorePath(message.mediaPath) else {
            NSSound.beep()
            return nil
        }
        let downloader = AttachmentDownloader(preferences: preferences)
        let suggested = message.fileName.isEmpty ? message.body : message.fileName
        do {
            return try downloader.download(
                sourcePath: message.mediaPath,
                suggestedName: suggested,
                mimeType: message.mimeType
            )
        } catch {
            NSSound.beep()
            return nil
        }
    }

    /// Downloads all local attachments on `message` (either its gallery items or the single attachment).
    @MainActor
    @discardableResult
    static func downloadAll(
        on message: TimelineMessage,
        preferences: ComposerPreferences = ComposerPreferences()
    ) -> [URL] {
        guard !message.viewOnce else { return [] }
        let downloader = AttachmentDownloader(preferences: preferences)
        if !message.galleryItems.isEmpty {
            var urls: [URL] = []
            for item in message.galleryItems where isLocalMediaStorePath(item.mediaPath) {
                let name = item.fileName.isEmpty ? "attachment" : item.fileName
                if let saved = try? downloader.download(
                    sourcePath: item.mediaPath,
                    suggestedName: name,
                    mimeType: item.mimeType
                ) {
                    urls.append(saved)
                }
            }
            return urls
        }
        guard isLocalMediaStorePath(message.mediaPath) else { return [] }
        let suggested = message.fileName.isEmpty ? message.body : message.fileName
        if let saved = try? downloader.download(
            sourcePath: message.mediaPath,
            suggestedName: suggested,
            mimeType: message.mimeType
        ) {
            return [saved]
        }
        return []
    }

    /// The icon of the kind of file this is, from its mime type or the extension of its name.
    static func icon(for message: TimelineMessage) -> NSImage {
        let type = UTType(mimeType: message.mimeType)
            ?? UTType(filenameExtension: (message.fileName as NSString).pathExtension)
            ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}

/// Strip of pending attachments in `ComposerView` (`PendingAttachments.tsx`), showing thumbnail previews,
/// human byte sizes, per-network `FileKindFeatures.maxSize` warnings before send, and remove (`×`) buttons.
public struct PendingAttachmentsStrip: View {
    public let attachments: [ComposerAttachment]
    public var features: ChatFeatures
    public var network: String
    public let onRemove: (UUID) -> Void

    public init(
        attachments: [ComposerAttachment],
        features: ChatFeatures = .noFeatures,
        network: String = "",
        onRemove: @escaping (UUID) -> Void
    ) {
        self.attachments = attachments
        self.features = features
        self.network = network
        self.onRemove = onRemove
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    PendingAttachmentChip(
                        attachment: attachment,
                        maxSizeBytes: Self.maxSizeBytes(for: attachment.url, in: features),
                        network: network
                    ) {
                        onRemove(attachment.id)
                    }
                }
            }
        }
    }

    /// Resolves the per-network maximum size in bytes for `url` from `features`.
    public static func maxSizeBytes(for url: URL, in features: ChatFeatures) -> Int64? {
        let ext = url.pathExtension.lowercased()
        let utType = UTType(filenameExtension: ext)
        let msgType: String
        if ext == "gif" || utType == .gif {
            msgType = "fi.mau.gif"
        } else if utType?.conforms(to: .image) == true {
            msgType = "m.image"
        } else if utType?.conforms(to: .movie) == true || utType?.conforms(to: .video) == true {
            msgType = "m.video"
        } else if utType?.conforms(to: .audio) == true {
            msgType = "m.audio"
        } else {
            msgType = "m.file"
        }
        return features.maxSizeBytes(for: msgType) ?? features.fileFeatures?.maxSize
    }
}

/// A file waiting in the composer: its thumbnail or icon, name, byte size, optional per-network size warning, and remove (`×`) button.
struct PendingAttachmentChip: View {
    let attachment: ComposerAttachment
    var maxSizeBytes: Int64? = nil
    var network: String = ""
    let remove: () -> Void

    private var exceedsNetworkLimit: Bool {
        guard let maxSizeBytes, maxSizeBytes > 0 else { return false }
        return attachment.size > maxSizeBytes
    }

    private var warningText: String? {
        guard let maxSizeBytes, maxSizeBytes > 0, attachment.size > maxSizeBytes else { return nil }
        let limitText = FileSize.text(maxSizeBytes)
        if let networkName = NetworkNames.displayName(of: network) {
            return String(localized: "Exceeds \(networkName) \(limitText) limit")
        }
        return String(localized: "Exceeds \(limitText) limit")
    }

    private var imagePreview: NSImage? {
        guard attachment.url.isFileURL else { return nil }
        let ext = attachment.url.pathExtension.lowercased()
        guard let utType = UTType(filenameExtension: ext), utType.conforms(to: .image) else {
            return nil
        }
        return NSImage(contentsOf: attachment.url)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let preview = imagePreview {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: attachment.url.path))
                    .resizable()
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.fileName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(FileSize.text(attachment.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let warningText {
                        Label(warningText, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: 220, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Remove attachment"))
            .accessibilityLabel(String(localized: "Remove \(attachment.fileName)"))
        }
        .padding(.vertical, 5)
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(exceedsNetworkLimit ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(exceedsNetworkLimit ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

/// Rich file card (`FileAttachment.tsx`, `FilePlaceholder.tsx`) with category icon (`Audio`, `PDF`, `Text`,
/// `Archive`, `Document`), filename, human byte size, **Quick Look** (`Space`), **Open**, and **Download** (`⌘D`).
public struct FileAttachmentChip: View {
    public enum Category: String, CaseIterable, Equatable, Sendable {
        case audio
        case pdf
        case text
        case archive
        case document

        public var label: String {
            switch self {
            case .audio: String(localized: "Audio")
            case .pdf: String(localized: "PDF")
            case .text: String(localized: "Text")
            case .archive: String(localized: "Archive")
            case .document: String(localized: "Document")
            }
        }

        public var symbol: String {
            switch self {
            case .audio: "waveform"
            case .pdf: "doc.richtext.fill"
            case .text: "doc.text.fill"
            case .archive: "doc.zipper"
            case .document: "doc.fill"
            }
        }

        public var tint: Color {
            switch self {
            case .audio: .purple
            case .pdf: .red
            case .text: .blue
            case .archive: .orange
            case .document: .teal
            }
        }

        public static func classify(fileName: String, mimeType: String) -> Category {
            let mime = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let ext = (fileName as NSString).pathExtension.lowercased()

            if mime == "application/pdf" || ext == "pdf" {
                return .pdf
            }
            if mime.hasPrefix("audio/") || ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aac", "aiff"].contains(ext) {
                return .audio
            }
            if [
                "application/zip",
                "application/x-tar",
                "application/gzip",
                "application/x-gzip",
                "application/x-7z-compressed",
                "application/x-rar-compressed",
                "application/x-bzip2",
                "application/vnd.rar",
            ].contains(mime) || ["zip", "tar", "gz", "tgz", "7z", "rar", "bz2", "xz", "dmg"].contains(ext) {
                return .archive
            }
            if mime.hasPrefix("text/")
                || ["application/json", "application/xml", "application/yaml"].contains(mime)
                || ["txt", "md", "csv", "json", "xml", "yaml", "yml", "log", "rtf"].contains(ext) {
                return .text
            }
            return .document
        }
    }

    public let message: TimelineMessage
    public var isDownloading: Bool
    public var preferences: ComposerPreferences
    public var onDownload: ((TimelineMessage) -> Void)?

    public static let userVisibleStrings: [String] = [
        String(localized: "Audio"),
        String(localized: "PDF"),
        String(localized: "Text"),
        String(localized: "Archive"),
        String(localized: "Document"),
        String(localized: "Quick Look (Space)"),
        String(localized: "Open"),
        String(localized: "Download (⌘D)"),
        String(localized: "Downloading…"),
        String(localized: "Not downloaded yet"),
    ]

    public init(
        message: TimelineMessage,
        isDownloading: Bool = false,
        preferences: ComposerPreferences = ComposerPreferences(),
        onDownload: ((TimelineMessage) -> Void)? = nil
    ) {
        self.message = message
        self.isDownloading = isDownloading
        self.preferences = preferences
        self.onDownload = onDownload
    }

    private var url: URL? {
        guard isLocalMediaStorePath(message.mediaPath) else { return nil }
        let candidate = URL(fileURLWithPath: message.mediaPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            return nil
        }
        return candidate
    }

    private var category: Category {
        Category.classify(fileName: message.fileName, mimeType: message.mimeType)
    }

    public var body: some View {
        HStack(spacing: 10) {
            categoryBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 210, alignment: .leading)
            Spacer(minLength: 4)
            actionButtons
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            guard url != nil, !isDownloading else { return }
            ReceivedFile.open(message)
        }
        .help(url == nil ? String(localized: "Not downloaded yet") : String(localized: "Open"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
        .accessibilityHint(url == nil ? String(localized: "Not downloaded yet") : String(localized: "Opens the file"))
    }

    @ViewBuilder
    private var categoryBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(category.tint.opacity(0.15))
                .frame(width: 36, height: 36)
            Image(systemName: category.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(category.tint)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isDownloading {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "Downloading…"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(.quaternary.opacity(0.6)))
        } else {
            HStack(spacing: 4) {
                Button {
                    ReceivedFile.quickLook(message)
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(url == nil)
                .help(String(localized: "Quick Look (Space)"))
                .accessibilityLabel(String(localized: "Quick Look \(name)"))

                Button {
                    ReceivedFile.open(message)
                } label: {
                    Text(String(localized: "Open"))
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(url == nil)
                .help(String(localized: "Open"))
                .accessibilityLabel(String(localized: "Open \(name)"))

                Button {
                    if let onDownload {
                        onDownload(message)
                    } else {
                        ReceivedFile.download(message, preferences: preferences)
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(url == nil)
                .help(String(localized: "Download (⌘D)"))
                .accessibilityLabel(String(localized: "Download \(name)"))
            }
        }
    }

    private var name: String {
        if !message.fileName.isEmpty { return message.fileName }
        switch message.kind {
        case .video: return String(localized: "Video")
        case .voiceNote: return String(localized: "Voice note")
        default: return String(localized: "File")
        }
    }

    private var detail: String {
        var parts: [String] = [category.label]
        if let size = message.byteSize {
            parts.append(FileSize.text(size))
        }
        if isDownloading {
            parts.append(String(localized: "Downloading…"))
        } else if message.showsMediaRemovedPlaceholder {
            parts.append(TimelineMessage.mediaRemovedPlaceholderText)
        } else if url == nil {
            parts.append(String(localized: "Not downloaded yet"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Calm placeholder shown when an image, video, file, sticker, or voice note had its local media file deleted on this Mac (`com.courier.media_removed == true`).
public struct RemovedMediaPlaceholderView: View {
    public let message: TimelineMessage

    public init(message: TimelineMessage) {
        self.message = message
    }

    private var symbol: String {
        switch message.kind {
        case .image: "photo"
        case .video: "film"
        case .voiceNote: "waveform"
        case .sticker: "face.smiling"
        default: "doc"
        }
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(TimelineMessage.mediaRemovedPlaceholderText)
                    .font(.callout.italic().weight(.medium))
                    .foregroundStyle(.secondary)
                if !message.fileName.isEmpty {
                    Text(message.fileName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(TimelineMessage.mediaRemovedPlaceholderText)
    }
}

/// Broken-media fallback card (`ImageError.tsx`) shown when a local media file is missing or unreadable.
public struct ImageErrorCard: View {
    public let fileName: String
    public let size: CGSize
    public let title: String
    public let symbol: String

    public init(
        fileName: String,
        size: CGSize = CGSize(width: 240, height: 150),
        title: String = String(localized: "Image unavailable"),
        symbol: String = "photo.badge.exclamationmark"
    ) {
        self.fileName = fileName
        self.size = size
        self.title = title
        self.symbol = symbol
    }

    public var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            Text(fileName.isEmpty ? String(localized: "Missing or corrupted local media") : fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 12)
        }
        .frame(width: size.width, height: size.height)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.6)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(title): \(fileName)"))
    }
}

/// AppKit animated `NSImageView` wrapper for looping muted GIF playback (`isGIF == true`).
private struct AnimatedGIFImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context _: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.canDrawSubviewsIntoLayer = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    func updateNSView(_ nsView: NSImageView, context _: Context) {
        nsView.image = image
        nsView.animates = true
    }
}

/// Inline image bubble (`EnhancedImg.tsx`): sizes from stored `width`/`height` so the timeline never jumps,
/// shows a decoded BlurHash placeholder while loading from the local media store, falls back to `ImageErrorCard`
/// if missing/broken, loops animated GIFs, shows a subtle `Transcoded` badge when applicable, and opens the
/// in-app lightbox on click.
public struct EnhancedImageView: View {
    public let message: TimelineMessage
    public var preloadedImage: NSImage?
    public var forceBlurHashPlaceholder: Bool
    public var forceErrorState: Bool
    public var onOpenLightbox: (String) -> Void

    @State private var loadedCGImage: CGImage?
    @State private var loadedAnimatedImage: NSImage?
    @State private var failed = false

    /// The longest side of a picture in the timeline, in points.
    public static let longestSide: CGFloat = 320

    public init(
        message: TimelineMessage,
        preloadedImage: NSImage? = nil,
        forceBlurHashPlaceholder: Bool = false,
        forceErrorState: Bool = false,
        onOpenLightbox: @escaping (String) -> Void = { _ in }
    ) {
        self.message = message
        self.preloadedImage = preloadedImage
        self.forceBlurHashPlaceholder = forceBlurHashPlaceholder
        self.forceErrorState = forceErrorState
        self.onOpenLightbox = onOpenLightbox
    }

    private var decodedBlurHash: CGImage? {
        guard let hash = message.blurhash, !hash.isEmpty else { return nil }
        return BlurHashDecoder.decode(hash, width: 32, height: 32)
    }

    private var localPath: String? {
        if isLocalMediaStorePath(message.mediaPath) {
            return message.mediaPath
        }
        if let thumb = message.thumbnailPath, isLocalMediaStorePath(thumb) {
            return thumb
        }
        return nil
    }

    public var body: some View {
        ZStack {
            if forceErrorState || failed {
                ImageErrorCard(fileName: message.fileName, size: size)
            } else if !forceBlurHashPlaceholder, let preloadedImage {
                if message.isGIF {
                    AnimatedGIFImageView(image: preloadedImage)
                        .frame(width: size.width, height: size.height)
                } else {
                    Image(nsImage: preloadedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                }
                badgesOverlay
            } else if !forceBlurHashPlaceholder, let loadedAnimatedImage, message.isGIF {
                AnimatedGIFImageView(image: loadedAnimatedImage)
                    .frame(width: size.width, height: size.height)
                badgesOverlay
            } else if !forceBlurHashPlaceholder, let loadedCGImage {
                Image(decorative: loadedCGImage, scale: 2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                badgesOverlay
            } else {
                placeholderView
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !forceErrorState, !failed else { return }
            onOpenLightbox(message.id)
        }
        .task(id: message.mediaPath) {
            guard !forceBlurHashPlaceholder, preloadedImage == nil else { return }
            if forceErrorState {
                failed = true
                return
            }
            loadedCGImage = nil
            loadedAnimatedImage = nil
            failed = false
            guard let path = localPath else {
                if !message.mediaPath.isEmpty {
                    // Reject non-local paths immediately as an error.
                    failed = true
                }
                return
            }
            if message.isGIF, let nsImage = NSImage(contentsOfFile: path) {
                loadedAnimatedImage = nsImage
                return
            }
            if let thumbnail = await ThumbnailLoader.shared.thumbnail(atPath: path) {
                loadedCGImage = thumbnail.image
            } else {
                failed = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel(message.fileName.isEmpty ? String(localized: "Image") : message.fileName)
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var placeholderView: some View {
        ZStack {
            if let blurCG = decodedBlurHash {
                Image(decorative: blurCG, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            if message.mediaPath.isEmpty && !forceBlurHashPlaceholder {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                    Text(message.showsMediaRemovedPlaceholder
                        ? TimelineMessage.mediaRemovedPlaceholderText
                        : String(localized: "Not downloaded yet"))
                        .font(.caption)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial))
                .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(Circle().fill(.ultraThinMaterial))
            }
        }
    }

    @ViewBuilder
    private var badgesOverlay: some View {
        VStack {
            HStack {
                if message.isGIF {
                    Text("GIF")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                if message.isTranscoded {
                    Text(String(localized: "Transcoded"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                }
            }
        }
        .padding(6)
    }

    /// The picture's own proportions within the longest side, or a plain rectangle when they are not known.
    public var size: CGSize {
        Self.proportionalSize(width: message.width, height: message.height)
    }

    /// Computes a proportional inline media frame within `longestSide`, falling back to `fallback` when dimensions are absent.
    public static func proportionalSize(
        width: Int?,
        height: Int?,
        longestSide: CGFloat = longestSide,
        fallback: CGSize = CGSize(width: 240, height: 180)
    ) -> CGSize {
        guard let width, let height, width > 0, height > 0 else {
            return fallback
        }
        let scale = min(1, longestSide / CGFloat(max(width, height)))
        return CGSize(width: max(80, CGFloat(width) * scale), height: max(60, CGFloat(height) * scale))
    }
}

/// View-once media pill shown in the timeline instead of an inline thumbnail.
/// Never renders the underlying image inline; shows "View-once Photo/Video/Voice Note" when unopened,
/// or "Opened" in muted text once played on this Mac.
public struct ViewOnceChip: View {
    public let message: TimelineMessage
    public let onOpen: () -> Void

    public init(message: TimelineMessage, onOpen: @escaping () -> Void) {
        self.message = message
        self.onOpen = onOpen
    }

    private var unopenedTitle: String {
        switch message.kind {
        case .video:
            return String(localized: "View-once Video")
        case .voiceNote:
            return String(localized: "View-once Voice Note")
        default:
            return String(localized: "View-once Photo")
        }
    }

    public var body: some View {
        if message.played {
            HStack(spacing: 8) {
                Image(systemName: "1.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Opened"))
                        .font(.callout.italic().weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "View-once media expired on this Mac"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Opened view-once media"))
        } else {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.16))
                            .frame(width: 30, height: 30)
                        Image(systemName: "1.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(unopenedTitle)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(String(localized: "Tap to view once on this Mac"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 250, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.75)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(unopenedTitle)
            .accessibilityHint(String(localized: "Opens the view-once viewer"))
        }
    }
}

/// Legacy wrapper preserved for compatibility; delegates to `EnhancedImageView`.
struct InlineImage: View {
    let message: TimelineMessage
    var onOpenLightbox: (String) -> Void = { _ in }

    var body: some View {
        EnhancedImageView(message: message, onOpenLightbox: onOpenLightbox)
    }
}
