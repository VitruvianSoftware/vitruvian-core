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
enum ReceivedFile {
    @MainActor
    static func open(_ message: TimelineMessage) {
        guard !message.mediaPath.isEmpty else { return }
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
        message.mediaPath.isEmpty ? nil : URL(fileURLWithPath: message.mediaPath)
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

/// A picture in a message, made small off the main actor. A click opens the original in the default app.
struct InlineImage: View {
    let message: TimelineMessage
    @State private var image: CGImage?
    @State private var failed = false

    /// The longest side of a picture in the timeline, in points.
    private static let longestSide: CGFloat = 320

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if failed {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                        Text(String(localized: "Image can’t be shown"))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else if message.mediaPath.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                        Text(String(localized: "Not downloaded yet"))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            ReceivedFile.open(message)
        }
        .task(id: message.mediaPath) {
            image = nil
            failed = false
            guard !message.mediaPath.isEmpty else { return }
            if let thumbnail = await ThumbnailLoader.shared.thumbnail(atPath: message.mediaPath) {
                image = thumbnail.image
            } else {
                failed = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel(message.fileName.isEmpty ? String(localized: "Image") : message.fileName)
        .accessibilityAddTraits(.isImage)
    }

    /// The picture's own proportions within the longest side, or a plain rectangle when they are not known.
    private var size: CGSize {
        guard let width = message.width, let height = message.height, width > 0, height > 0 else {
            return CGSize(width: 240, height: 180)
        }
        let scale = min(1, Self.longestSide / CGFloat(max(width, height)))
        return CGSize(width: max(60, CGFloat(width) * scale), height: max(40, CGFloat(height) * scale))
    }
}
