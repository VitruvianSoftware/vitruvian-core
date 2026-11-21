// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo made ready to leave this Mac: shrunk, turned upright, and with every bit of metadata (where it was taken,
/// the camera, the date) left behind.
public struct PreparedPhoto: Equatable, Sendable {
    public let data: Data
    public let mimeType: String
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(data: Data, mimeType: String, pixelWidth: Int, pixelHeight: Int) {
        self.data = data
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Makes a photo ready for an AI service: the long edge at most 2048 pixels, upright, and re-drawn from its pixels
/// alone so no EXIF, GPS, XMP or IPTC survives. A photo with see-through parts stays a PNG; any other becomes a JPEG.
public enum PhotoEditPreparer {
    public enum Failure: Error, Equatable, Sendable {
        /// The bytes are not a picture ImageIO can read.
        case unreadable
        /// Too big to read at all, or still over `maxBytes` once shrunk.
        case tooLarge
    }

    public static let maxLongEdge = 2048
    /// What may be sent: Google takes 20 MB of request in all, and base64 adds a third.
    public static let maxUploadBytes = 14 * 1024 * 1024
    /// The biggest original it will even try to decode.
    public static let maxInputBytes = 120 * 1024 * 1024
    public static let jpegQuality = 0.9

    public static func prepare(
        _ data: Data,
        maxLongEdge: Int = PhotoEditPreparer.maxLongEdge,
        maxBytes: Int = PhotoEditPreparer.maxUploadBytes
    ) throws -> PreparedPhoto {
        guard data.count <= maxInputBytes else { throw Failure.tooLarge }
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0
        else { throw Failure.unreadable }

        let longest = max(width, height)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Turns the picture upright by its orientation tag, so dropping the tag with the rest of the metadata is safe.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(maxLongEdge, 1), longest),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else { throw Failure.unreadable }

        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let type = hasAlpha ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        else { throw Failure.unreadable }
        // The image goes in with no properties dictionary: nothing but its pixels is written.
        var options: [CFString: Any] = [:]
        if !hasAlpha { options[kCGImageDestinationLossyCompressionQuality] = jpegQuality }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }

        let encoded = output as Data
        guard encoded.count <= maxBytes else { throw Failure.tooLarge }
        return PreparedPhoto(
            data: encoded,
            mimeType: hasAlpha ? "image/png" : "image/jpeg",
            pixelWidth: image.width,
            pixelHeight: image.height
        )
    }
}
