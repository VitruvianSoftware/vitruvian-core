// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Darwin
import Foundation
import ImageIO

/// A picture made small enough to keep and draw.
public struct Thumbnail: @unchecked Sendable {
    public let image: CGImage
}

/// The kept pictures, readable from any thread without waiting for the loader: a row scrolling back into view draws
/// its picture in its first frame instead of a placeholder. It holds exactly what the loader's cache holds.
private final class ThumbnailMirror: @unchecked Sendable {
    private let lock = NSLock()
    private var pictures: [String: Thumbnail] = [:]

    func picture(at path: String) -> Thumbnail? {
        lock.lock()
        defer { lock.unlock() }
        return pictures[path]
    }

    func set(_ thumbnail: Thumbnail, at path: String) {
        lock.lock()
        defer { lock.unlock() }
        pictures[path] = thumbnail
    }

    func remove(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        pictures[path] = nil
    }
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
    private nonisolated let mirror = ThumbnailMirror()

    public init(maxPixelSize: Int = 640, maxCount: Int = 300, maxBytes: Int = 160 * 1024 * 1024) {
        self.maxPixelSize = maxPixelSize
        self.maxCount = maxCount
        self.maxBytes = maxBytes
    }

    public var cachedCount: Int { entries.count }
    public var cachedPaths: [String] { usage }

    /// The picture at `path` if it is already kept; never loads. For drawing a row's first frame.
    public nonisolated func cachedThumbnail(atPath path: String) -> Thumbnail? {
        mirror.picture(at: path)
    }

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

    /// First pictures of MP4 loops, kept apart from `entries` so a video's frame is never handed to the conversation as
    /// if it were that file's picture.
    private var loopFrames: [String: Thumbnail] = [:]

    /// A tile's picture for a GIF in the picker: `thumbnail(atPath:)` for a GIF or a picture (a GIF's first frame), and
    /// for an MP4 loop (what a GIF from a chat network often is) its first frame. Nil when the file is neither.
    public func loopThumbnail(atPath path: String) async -> Thumbnail? {
        if let picture = await thumbnail(atPath: path) { return picture }
        if let kept = loopFrames[path] { return kept }
        guard LoopFileKind.detect(atPath: path) == .mp4,
              let frame = await VideoFirstFrame.image(atPath: path, maxPixelSize: maxPixelSize) else { return nil }
        let thumbnail = Thumbnail(image: frame)
        if loopFrames.count >= 80 { loopFrames.removeAll() }
        loopFrames[path] = thumbnail
        return thumbnail
    }

    private func touch(_ path: String) {
        usage.removeAll { $0 == path }
        usage.append(path)
    }

    private func store(_ thumbnail: Thumbnail, for path: String) {
        let bytes = thumbnail.image.bytesPerRow * thumbnail.image.height
        if let old = entries[path] { totalBytes -= old.bytes }
        entries[path] = Entry(thumbnail: thumbnail, bytes: bytes)
        mirror.set(thumbnail, at: path)
        totalBytes += bytes
        touch(path)
        // The newest stays even when it alone is over the limit.
        while usage.count > 1, entries.count > maxCount || totalBytes > maxBytes {
            let oldest = usage.removeFirst()
            if let gone = entries.removeValue(forKey: oldest) { totalBytes -= gone.bytes }
            mirror.remove(oldest)
        }
    }

    // MARK: - Reading the file

    /// Resolves a local media path from a `courier://media/<sha256>`, `mxc://courier.local/<sha256>`, `file://` URL, or filesystem path.
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
        } else if raw.hasPrefix("mxc://courier.local/") {
            hashCandidate = String(raw.dropFirst("mxc://courier.local/".count))
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
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        let longest = max(width, height)
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if longest <= maxPixelSize && orientation == 1 {
            // Decoded here, off the main thread, not on first draw.
            let whole: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
            return CGImageSourceCreateImageAtIndex(source, 0, whole as CFDictionary).map(Thumbnail.init)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, longest),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(Thumbnail.init)
    }
}

/// Reads a picture's real pixel size from its file header (no decoding), cached, for bridged images that arrive
/// without width/height.
public actor ImagePixelSizeReader {
    public static let shared = ImagePixelSizeReader()
    public nonisolated static let didLearnSizeNotification = Notification.Name("VitruvianCourier.ImagePixelSizeReader.didLearnSize")
    public nonisolated static let pathUserInfoKey = "path"

    private struct FileStamp: Equatable, Sendable {
        let dev: dev_t
        let ino: ino_t
        let size: off_t
        let mtimeSec: Int
        let mtimeNsec: Int
    }

    /// Sizes already read, for any thread: a row that scrolls back into view knows its picture's size from
    /// memory without touching disk. Failed non-empty files are keyed by file stamp so a later file at the
    /// same path is re-read, while missing or empty files are not cached at all.
    private nonisolated static let known = KnownSizes()

    private final class KnownSizes: @unchecked Sendable {
        private let lock = NSLock()
        private var sizes: [String: CGSize] = [:]
        private var failedStamps: [String: FileStamp] = [:]

        func size(at path: String) -> CGSize? {
            lock.lock()
            defer { lock.unlock() }
            return sizes[path]
        }

        @discardableResult
        func set(_ size: CGSize, at path: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            failedStamps.removeValue(forKey: path)
            let changed = sizes[path] != size
            sizes[path] = size
            return changed
        }

        func hasFailed(_ stamp: FileStamp, at path: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return failedStamps[path] == stamp
        }

        func recordFailure(_ stamp: FileStamp, at path: String) {
            lock.lock()
            defer { lock.unlock() }
            sizes.removeValue(forKey: path)
            failedStamps[path] = stamp
        }
    }

    private nonisolated static func fileStamp(at path: String) -> FileStamp? {
        var st = stat()
        guard stat(path, &st) == 0, st.st_size > 0 else { return nil }
        return FileStamp(
            dev: st.st_dev,
            ino: st.st_ino,
            size: st.st_size,
            mtimeSec: st.st_mtimespec.tv_sec,
            mtimeNsec: st.st_mtimespec.tv_nsec
        )
    }

    /// The size of the first local picture among `paths` that is already cached in memory; never reads disk.
    public nonisolated static func cachedSize(ofFirstReadable paths: [String?]) -> CGSize? {
        for path in paths.compactMap({ $0 }) where isLocalMediaStorePath(path) {
            if let remembered = known.size(at: path) {
                return remembered
            }
        }
        return nil
    }

    /// The size of the first readable local picture among `paths`, reading a header on this thread if need be.
    public nonisolated static func sizeNow(ofFirstReadable paths: [String?]) -> CGSize? {
        for path in paths.compactMap({ $0 }) where isLocalMediaStorePath(path) {
            if let remembered = known.size(at: path) {
                return remembered
            }
            guard let stamp = fileStamp(at: path) else { continue }
            if known.hasFailed(stamp, at: path) { continue }
            if let read = Self.read(path) {
                if known.set(read, at: path) {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: didLearnSizeNotification,
                            object: nil,
                            userInfo: [pathUserInfoKey: path]
                        )
                    }
                }
                return read
            }
            known.recordFailure(stamp, at: path)
        }
        return nil
    }

    public func size(ofFirstReadable paths: [String?]) -> CGSize? {
        Self.sizeNow(ofFirstReadable: paths)
    }

    /// Pre-warms cached pixel sizes off the main thread for local media events missing stored dimensions.
    public func warm(events: [Event]) async {
        let uncached = Self.uncachedPaths(in: events)
        let files = LocalFileFacts.paths(in: events)
        guard !uncached.isEmpty || !files.isEmpty else { return }
        await Task.detached(priority: .userInitiated) {
            // Whether each local file is there (and a PDF's pages), so rows size without touching the disk.
            LocalFileFacts.warm(paths: files)
            for path in uncached {
                _ = Self.sizeNow(ofFirstReadable: [path])
            }
            // A link card's picture sizes the card (120–148 pt): known before the card is shown.
            for event in events {
                for preview in event.linkPreviews ?? [] {
                    if let path = preview.imagePath, isLocalMediaStorePath(path) {
                        _ = Self.sizeNow(ofFirstReadable: [path])
                    }
                }
            }
        }.value
    }

    private nonisolated static func uncachedPaths(in events: [Event]) -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        for event in events {
            let info = event.content["info"]
            let width = info?["w"]?.integerValue ?? 0
            let height = info?["h"]?.integerValue ?? 0
            let needsHeader = width <= 0 || height <= 0 || Timeline.isEdit(event)
            guard needsHeader else { continue }
            for candidate in [event.mediaPath, event.thumbnailPath] {
                guard let path = candidate, isLocalMediaStorePath(path), seen.insert(path).inserted else { continue }
                guard known.size(at: path) == nil else { continue }
                guard let stamp = fileStamp(at: path), !known.hasFailed(stamp, at: path) else { continue }
                paths.append(path)
            }
        }
        return paths
    }

    public nonisolated static func read(_ path: String) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              var h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w > 0, h > 0 else { return nil }
        // EXIF orientations 5-8 are rotated a quarter turn.
        if let o = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue, (5 ... 8).contains(o) { swap(&w, &h) }
        return CGSize(width: w, height: h)
    }
}
