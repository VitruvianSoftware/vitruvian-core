// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import UniformTypeIdentifiers

/// How big a file is, for people.
enum FileSize {
    static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Opens a received file in the app meant for it. The engine's copy has no name or extension, so a copy under its
/// real name is made first (see OpenFileCache) and that is opened.
/// View-once media is never passed through `OpenFileCache` or opened in an external app.
enum ReceivedFile {
    @MainActor
    static func open(_ message: TimelineMessage) {
        guard !message.viewOnce, !message.mediaPath.isEmpty else { return }
        let source = URL(fileURLWithPath: message.mediaPath)
        let name = message.fileName
        let mime = message.mimeType
        Task.detached(priority: .userInitiated) {
            do {
                let copy = try OpenFileCache.shared.prepare(source: source, fileName: name, mimeType: mime)
                await MainActor.run { _ = NSWorkspace.shared.open(copy) }
            } catch {
                await MainActor.run { NSSound.beep() }
            }
        }
    }

    /// The icon of the kind of file this is, from its mime type or the extension of its name.
    static func icon(for message: TimelineMessage) -> NSImage {
        let type = UTType(mimeType: message.mimeType)
            ?? UTType(filenameExtension: (message.fileName as NSString).pathExtension)
            ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}

/// Returns true only when `path` is a local filesystem path (never a remote `http://`, `https://`, or `mxc://` URL).
func isLocalMediaStorePath(_ path: String) -> Bool {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let lower = trimmed.lowercased()
    if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mxc://") {
        return false
    }
    return trimmed.hasPrefix("/")
}

/// A file waiting in the composer: its icon, name and size, and a button that takes it out.
struct PendingAttachmentChip: View {
    let attachment: ComposerAttachment
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: attachment.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.fileName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(FileSize.text(attachment.size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 180, alignment: .leading)
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
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        .accessibilityElement(children: .contain)
    }
}

/// A file in a message: a video, a voice note (inline players are milestone 4) or any other file. It opens in the
/// default app. Without the file on disk yet, it says so.
struct FileAttachmentChip: View {
    let message: TimelineMessage

    private var url: URL? {
        isLocalMediaStorePath(message.mediaPath) ? URL(fileURLWithPath: message.mediaPath) : nil
    }

    var body: some View {
        Button {
            ReceivedFile.open(message)
        } label: {
            HStack(spacing: 10) {
                icon
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 220, alignment: .leading)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .help(url == nil ? String(localized: "Not downloaded yet") : String(localized: "Open"))
        .accessibilityLabel(name)
        .accessibilityHint(url == nil ? String(localized: "Not downloaded yet") : String(localized: "Opens the file"))
    }

    @ViewBuilder
    private var icon: some View {
        if url != nil {
            Image(nsImage: ReceivedFile.icon(for: message))
                .resizable()
        } else {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private var symbol: String {
        switch message.kind {
        case .video: "film"
        case .voiceNote: "waveform"
        default: "doc"
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
        var parts: [String] = []
        if let size = message.byteSize { parts.append(FileSize.text(size)) }
        if url == nil { parts.append(String(localized: "Not downloaded yet")) }
        return parts.joined(separator: " · ")
    }
}

/// Broken-image fallback card (`ImageError.tsx`) shown when a local media file is missing or unreadable.
public struct ImageErrorCard: View {
    public let fileName: String
    public let size: CGSize

    public init(fileName: String, size: CGSize = CGSize(width: 240, height: 150)) {
        self.fileName = fileName
        self.size = size
    }

    public var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text(String(localized: "Image unavailable"))
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
        .accessibilityLabel(String(localized: "Image unavailable: \(fileName)"))
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
                    Text(String(localized: "Not downloaded yet"))
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
        guard let width = message.width, let height = message.height, width > 0, height > 0 else {
            return CGSize(width: 240, height: 180)
        }
        let scale = min(1, Self.longestSide / CGFloat(max(width, height)))
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
