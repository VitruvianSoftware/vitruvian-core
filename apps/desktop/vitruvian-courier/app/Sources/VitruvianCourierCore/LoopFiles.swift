// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

/// What a GIF in the picker's strip really is, told from the first bytes of its file: Courier keeps received and sent
/// media under a hash with no extension, and a "GIF" from a chat network is often an MP4 loop.
public enum LoopFileKind: Equatable, Sendable {
    case gif
    case mp4
    case other

    public static func detect(atPath path: String) -> LoopFileKind {
        guard let handle = FileHandle(forReadingAtPath: path) else { return .other }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 12)) ?? Data()
        return detect(head)
    }

    public static func detect(_ head: Data) -> LoopFileKind {
        let bytes = [UInt8](head.prefix(12))
        if bytes.count >= 6, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38 { return .gif } // GIF8
        if bytes.count >= 8, bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 { return .mp4 } // ftyp
        return .other
    }
}

/// The first picture of an MP4 loop, for a tile that cannot play it: ImageIO (what `ThumbnailLoader` uses for pictures
/// and GIFs) cannot read a video.
public enum VideoFirstFrame {
    public static func image(atPath path: String, maxPixelSize: Int = 640) async -> CGImage? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path), options: [AVURLAssetOverrideMIMETypeKey: "video/mp4"])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        return try? await generator.image(at: .zero).image
    }
}

/// How much of a GIF the picker's strip may play. A GIF from a chat or from an online service is someone else's file, so
/// what it may cost is checked from its header (size on disk, pixels, frame count) before anything is decoded: a big
/// one shows its first frame, and a huge one a placeholder.
public enum LoopLimits {
    /// A GIF bigger than this on disk shows its first frame.
    public static let maximumAnimatedBytes = 8 * 1024 * 1024
    /// A GIF wider or taller than this (in pixels) shows its first frame.
    public static let maximumAnimatedSide = 2048
    /// A GIF with more frames than this shows its first frame.
    public static let maximumAnimatedFrames = 500
    /// Wider or taller than this, even a first frame is not decoded: a placeholder.
    public static let maximumStillSide = 4096

    public enum Display: Equatable, Sendable {
        case animate
        case stillFrame
        case placeholder
    }

    public static func display(bytes: Int, width: Int, height: Int, frames: Int) -> Display {
        if width <= 0 || height <= 0 || frames <= 0 { return .placeholder }
        if max(width, height) > maximumStillSide { return .placeholder }
        if bytes > maximumAnimatedBytes || max(width, height) > maximumAnimatedSide || frames > maximumAnimatedFrames {
            return .stillFrame
        }
        return .animate
    }

    /// What the file at `path` may do, from its header alone. A file ImageIO cannot read (an MP4 loop) is a still.
    public static func display(forFileAt path: String) -> Display {
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int) ?? 0
        guard bytes > 0 else { return .placeholder }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { return .stillFrame }
        return display(bytes: bytes, width: width, height: height, frames: CGImageSourceGetCount(source))
    }
}
