// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import CoreGraphics
import Foundation

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
