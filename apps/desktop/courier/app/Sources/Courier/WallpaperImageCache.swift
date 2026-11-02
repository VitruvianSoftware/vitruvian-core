// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import ImageIO

/// The pictures chosen as chat wallpapers, read from disk once and kept at a size a window can show.
///
/// The wallpaper view used to read its file on every redraw, and a live resize redraws the chat pane every frame, so
/// dragging the window's edge read and decoded the whole photo again and again. Here each picture is read once per
/// version of the file (its size and modification date), scaled down to at most `maxPixelSize` on its longer side
/// (a 48-megapixel photo becomes a few megabytes), and shared by every view that shows it.
@MainActor
final class WallpaperImageCache {
    static let shared = WallpaperImageCache()

    /// The longest side, in pixels, a wallpaper is kept at: wider than a 5K display, so nothing looks soft.
    static let maxPixelSize = 5120

    private struct Key: Hashable {
        let path: String
        let size: Int
        let modified: Date?
    }

    private var images: [Key: CGImage] = [:]
    /// How many times a file was decoded, for the tests.
    private(set) var diskReads = 0

    /// The picture at `path`, or nil when there is no readable picture there.
    func image(atPath path: String) -> CGImage? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let key = Key(path: path,
                      size: (attributes[.size] as? NSNumber)?.intValue ?? 0,
                      modified: attributes[.modificationDate] as? Date)
        if let cached = images[key] { return cached }
        diskReads += 1
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // An older version of the same file is no longer shown anywhere.
        images = images.filter { $0.key.path != path }
        images[key] = image
        return image
    }

    func removeAll() {
        images = [:]
        diskReads = 0
    }
}
