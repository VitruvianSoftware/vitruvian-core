// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO

/// A picture made small enough to keep and draw.
public struct Thumbnail: @unchecked Sendable {
    public let image: CGImage
}

/// Makes pictures small for the conversation, off the main actor, and keeps the latest ones in memory.
///
/// A picture longer than `maxPixelSize` on its longer side is read at that size (ImageIO decodes straight to it,
/// so a 40-megapixel photo is never held whole); a smaller one is not enlarged. What is kept is bounded by a
/// count and by the memory the pixels take; the least recently used go first.
public actor ThumbnailLoader {
    public static let shared = ThumbnailLoader()

    private struct Entry {
        let thumbnail: Thumbnail
        let bytes: Int
    }

    private let maxPixelSize: Int
    private let maxCount: Int
    private let maxBytes: Int
    private var entries: [String: Entry] = [:]
    /// Least recently used first.
    private var usage: [String] = []
    private var totalBytes = 0
    private var loading: [String: Task<Thumbnail?, Never>] = [:]

    public init(maxPixelSize: Int = 640, maxCount: Int = 300, maxBytes: Int = 160 * 1024 * 1024) {
        self.maxPixelSize = maxPixelSize
        self.maxCount = maxCount
        self.maxBytes = maxBytes
    }

    public var cachedCount: Int { entries.count }
    public var cachedPaths: [String] { usage }

    /// The picture's size in pixels, from its header alone.
    public func pixelSize(atPath path: String) -> CGSize? {
        Self.pixelSize(ofFileAt: path)
    }

    /// The picture at `path`, small. Nil when there is no path, or the file is missing or is not a picture.
    public func thumbnail(atPath path: String) async -> Thumbnail? {
        guard !path.isEmpty else { return nil }
        if let entry = entries[path] {
            touch(path)
            return entry.thumbnail
        }
        if let running = loading[path] { return await running.value }
        let limit = maxPixelSize
        let task = Task.detached(priority: .utility) { Self.decode(path, maxPixelSize: limit) }
        loading[path] = task
        let result = await task.value
        loading[path] = nil
        if let result { store(result, for: path) }
        return result
    }

    private func touch(_ path: String) {
        usage.removeAll { $0 == path }
        usage.append(path)
    }

    private func store(_ thumbnail: Thumbnail, for path: String) {
        let bytes = thumbnail.image.bytesPerRow * thumbnail.image.height
        if let old = entries[path] { totalBytes -= old.bytes }
        entries[path] = Entry(thumbnail: thumbnail, bytes: bytes)
        totalBytes += bytes
        touch(path)
        // The newest stays even when it alone is over the limit.
        while usage.count > 1, entries.count > maxCount || totalBytes > maxBytes {
            let oldest = usage.removeFirst()
            if let gone = entries.removeValue(forKey: oldest) { totalBytes -= gone.bytes }
        }
    }

    // MARK: - Reading the file

    /// Resolves a local media path from a `courier://media/<sha256>`, `mxc://local.courier/<sha256>`, `file://` URL, or filesystem path.
    public nonisolated static func resolveMediaPath(
        _ mediaURL: String?,
        dataDirectory: URL = EngineLocation.dataDirectory()
    ) -> String? {
        guard let raw = mediaURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let hashCandidate: String?
        if raw.hasPrefix("courier://media/") {
            hashCandidate = String(raw.dropFirst("courier://media/".count))
        } else if raw.hasPrefix("mxc://local.courier/") {
            hashCandidate = String(raw.dropFirst("mxc://local.courier/".count))
        } else {
            hashCandidate = nil
        }
        if let hash = hashCandidate,
           hash.count == 64,
           hash.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) {
            let prefix = String(hash.prefix(2))
            return dataDirectory
                .appendingPathComponent("media", isDirectory: true)
                .appendingPathComponent(prefix, isDirectory: true)
                .appendingPathComponent(hash, isDirectory: false)
                .path
        }
        if raw.hasPrefix("file://"), let url = URL(string: raw), url.isFileURL {
            return url.path
        }
        if raw.hasPrefix("/") {
            return raw
        }
        return nil
    }

    /// Synchronously decodes a bounded thumbnail for small local icons (such as custom emoji or sticker cells).
    public nonisolated static func thumbnail(atPath path: String, maxPixelSize: Int = 640) -> CGImage? {
        guard !path.isEmpty else { return nil }
        return decode(path, maxPixelSize: maxPixelSize)?.image
    }

    /// Synchronously decodes a bounded thumbnail from a `mediaURL` (`courier://media/<sha256>`, `file://`, or path).
    public nonisolated static func thumbnail(
        forMediaURL mediaURL: String?,
        maxPixelSize: Int = 640,
        dataDirectory: URL = EngineLocation.dataDirectory()
    ) -> CGImage? {
        guard let path = resolveMediaPath(mediaURL, dataDirectory: dataDirectory) else { return nil }
        return thumbnail(atPath: path, maxPixelSize: maxPixelSize)
    }

    private nonisolated static func pixelSize(ofFileAt path: String) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }

    private nonisolated static func decode(_ path: String, maxPixelSize: Int) -> Thumbnail? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil), CGImageSourceGetCount(source) > 0,
              let size = pixelSize(ofFileAt: path) else { return nil }
        if Int(max(size.width, size.height)) <= maxPixelSize {
            return CGImageSourceCreateImageAtIndex(source, 0, nil).map(Thumbnail.init)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(Thumbnail.init)
    }
}
