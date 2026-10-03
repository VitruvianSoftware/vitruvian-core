// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

package enum MediaTool: String, CaseIterable, Identifiable {
    case videoCompressor, gifMaker, imageCompressor, textExtractor

    package var id: String { rawValue }
}

/// A cancelled duration lookup remains resumable, while a successful lookup
/// stays attached to its input and tool instead of resetting a user's trim.
package struct MediaDurationLoading {
    package struct Request: Equatable {
        package let id = UUID()
        package let url: URL
        package let tool: MediaTool

        // Spelled out because a memberwise initializer never leaves its module.
        package init(url: URL, tool: MediaTool) {
            self.url = url
            self.tool = tool
        }
    }
    private var loaded: Request?
    package private(set) var pending: Request?

    package mutating func reset() { self = Self() }
    package mutating func cancel() { pending = nil }

    package mutating func start(url: URL?, tool: MediaTool) -> Request? {
        guard let url, tool == .videoCompressor || tool == .gifMaker else { reset(); return nil }
        guard loaded?.url != url || loaded?.tool != tool else { return nil }
        let request = Request(url: url, tool: tool)
        pending = request
        return request
    }

    package mutating func finish(_ request: Request, duration: Double?) -> Double? {
        guard pending == request else { return nil }
        pending = nil
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        let rounded = (duration * 10).rounded() / 10
        guard rounded.isFinite, rounded > 0 else { return nil }
        loaded = request
        return rounded
    }

    // Spelled out because a default initializer never leaves its module.
    package init() {}
}

package enum MediaImageFormat: String, CaseIterable, Codable, Identifiable {
    case jpeg, heic, png, pdf

    package var id: String { rawValue }

    package var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .png: return "png"
        case .pdf: return "pdf"
        }
    }

    package static func sanitized(_ value: String) -> MediaImageFormat {
        MediaImageFormat(rawValue: value) ?? .jpeg
    }
}

package enum MediaImageResizeKind: String, CaseIterable, Codable, Identifiable {
    case none, maxDimension, width, height, exact

    package var id: String { rawValue }

    package static func sanitized(_ value: String) -> MediaImageResizeKind {
        MediaImageResizeKind(rawValue: value) ?? .maxDimension
    }
}

package enum MediaImageExactResizeMode: String, CaseIterable, Codable, Identifiable {
    case stretch, fit, fill

    package var id: String { rawValue }

    package static func sanitized(_ value: String) -> MediaImageExactResizeMode {
        MediaImageExactResizeMode(rawValue: value) ?? .stretch
    }
}

package struct MediaImageResizeMode: Codable, Equatable {
    package var kind: MediaImageResizeKind
    package var maxDimension: Int
    package var width: Int
    package var height: Int
    package var exactMode: MediaImageExactResizeMode

    package init(kind: MediaImageResizeKind = .maxDimension,
         maxDimension: Int = 1600,
         width: Int = 1600,
         height: Int = 1200,
         exactMode: MediaImageExactResizeMode = .stretch) {
        self.kind = kind
        self.maxDimension = MediaSupport.sanitizedImageDimension(maxDimension, fallback: 1600)
        self.width = MediaSupport.sanitizedImageDimension(width, fallback: 1600)
        self.height = MediaSupport.sanitizedImageDimension(height, fallback: 1200)
        self.exactMode = exactMode
    }

    private enum CodingKeys: String, CodingKey {
        case kind, maxDimension, width, height, exactMode
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kindRaw = try container.decodeIfPresent(String.self, forKey: .kind) ?? MediaImageResizeKind.maxDimension.rawValue
        let exactModeRaw = try container.decodeIfPresent(String.self, forKey: .exactMode) ?? MediaImageExactResizeMode.stretch.rawValue
        self.init(kind: MediaImageResizeKind.sanitized(kindRaw),
                  maxDimension: try container.decodeIfPresent(Int.self, forKey: .maxDimension) ?? 1600,
                  width: try container.decodeIfPresent(Int.self, forKey: .width) ?? 1600,
                  height: try container.decodeIfPresent(Int.self, forKey: .height) ?? 1200,
                  exactMode: MediaImageExactResizeMode.sanitized(exactModeRaw))
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(maxDimension, forKey: .maxDimension)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(exactMode, forKey: .exactMode)
    }

    package static let none = MediaImageResizeMode(kind: .none)

    package static func maxDimension(_ value: Int) -> MediaImageResizeMode {
        MediaImageResizeMode(kind: .maxDimension, maxDimension: value)
    }

    package static func width(_ value: Int) -> MediaImageResizeMode {
        MediaImageResizeMode(kind: .width, width: value)
    }

    package static func height(_ value: Int) -> MediaImageResizeMode {
        MediaImageResizeMode(kind: .height, height: value)
    }

    package static func exact(width: Int, height: Int,
                      mode: MediaImageExactResizeMode = .stretch) -> MediaImageResizeMode {
        MediaImageResizeMode(kind: .exact, width: width, height: height, exactMode: mode)
    }

    package func targetSize(for source: CGSize) -> CGSize {
        let sourceWidth = max(1, abs(source.width))
        let sourceHeight = max(1, abs(source.height))
        switch kind {
        case .none:
            return CGSize(width: Int(sourceWidth.rounded()), height: Int(sourceHeight.rounded()))
        case .maxDimension:
            let maxSide = CGFloat(max(1, maxDimension))
            let scale = min(1, maxSide / max(sourceWidth, sourceHeight))
            return MediaSupport.integralImageSize(width: sourceWidth * scale, height: sourceHeight * scale)
        case .width:
            let outWidth = CGFloat(max(1, width))
            let outHeight = outWidth * sourceHeight / sourceWidth
            return MediaSupport.integralImageSize(width: outWidth, height: outHeight)
        case .height:
            let outHeight = CGFloat(max(1, height))
            let outWidth = outHeight * sourceWidth / sourceHeight
            return MediaSupport.integralImageSize(width: outWidth, height: outHeight)
        case .exact:
            return CGSize(width: max(1, width), height: max(1, height))
        }
    }
}

package enum MediaImageWatermarkKind: String, CaseIterable, Codable, Identifiable {
    case off, text, logo, textAndLogo

    package var id: String { rawValue }

    package static func sanitized(_ value: String) -> MediaImageWatermarkKind {
        MediaImageWatermarkKind(rawValue: value) ?? .off
    }
}

package enum MediaImageWatermarkPosition: String, CaseIterable, Codable, Identifiable {
    case topLeft, topRight, center, bottomLeft, bottomRight

    package var id: String { rawValue }

    package static func sanitized(_ value: String) -> MediaImageWatermarkPosition {
        MediaImageWatermarkPosition(rawValue: value) ?? .bottomRight
    }
}

package enum MediaImageBackground: String, CaseIterable, Codable, Identifiable {
    case transparent, white, black

    package var id: String { rawValue }

    package static func sanitized(_ value: String) -> MediaImageBackground {
        MediaImageBackground(rawValue: value) ?? .transparent
    }
}

package struct MediaImageWatermark: Codable, Equatable {
    package var kind: MediaImageWatermarkKind
    package var text: String
    package var logoPath: String
    package var position: MediaImageWatermarkPosition
    package var opacity: Double
    package var margin: Int
    package var scale: Double

    package init(kind: MediaImageWatermarkKind = .off,
         text: String = "",
         logoPath: String = "",
         position: MediaImageWatermarkPosition = .bottomRight,
         opacity: Double = 0.45,
         margin: Int = 32,
         scale: Double = 0.18) {
        self.kind = kind
        self.text = text
        self.logoPath = logoPath
        self.position = position
        self.opacity = MediaSupport.sanitizedOpacity(opacity)
        self.margin = MediaSupport.sanitizedImageDimension(margin, fallback: 32, min: 0, max: 2000)
        self.scale = MediaSupport.sanitizedWatermarkScale(scale)
    }

    package static let off = MediaImageWatermark()

    package var usesText: Bool {
        (kind == .text || kind == .textAndLogo) && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package var usesLogo: Bool {
        (kind == .logo || kind == .textAndLogo) && !logoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package var isEnabled: Bool { usesText || usesLogo }
}

package struct MediaImageRenamePattern: Codable, Equatable {
    package var rawValue: String

    package init(_ rawValue: String = "") {
        self.rawValue = rawValue
    }

    package static let automatic = MediaImageRenamePattern()

    package func outputBaseName(for inputURL: URL,
                        index: Int,
                        date: Date = Date(),
                        size: CGSize,
                        format: MediaImageFormat) -> String {
        let pattern = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{name}" : rawValue
        let baseName = MediaSupport.visibleOutputBaseName(for: inputURL)
        var output = pattern
            .replacingOccurrences(of: "{name}", with: baseName)
            .replacingOccurrences(of: "{date}", with: Self.dateFormatter.string(from: date))
            .replacingOccurrences(of: "{time}", with: Self.timeFormatter.string(from: date))
            .replacingOccurrences(of: "{datetime}", with: Self.dateTimeFormatter.string(from: date))
            .replacingOccurrences(of: "{width}", with: "\(max(1, Int(size.width.rounded())))")
            .replacingOccurrences(of: "{height}", with: "\(max(1, Int(size.height.rounded())))")
            .replacingOccurrences(of: "{format}", with: format.fileExtension)
            .replacingOccurrences(of: "{ext}", with: format.fileExtension)
            .replacingOccurrences(of: "{index}", with: "\(max(1, index))")
            .replacingOccurrences(of: "{counter}", with: "\(max(1, index))")
        for digits in 2...6 {
            output = output.replacingOccurrences(of: "{index:0\(digits)}",
                                                 with: String(format: "%0\(digits)d", max(1, index)))
            output = output.replacingOccurrences(of: "{counter:0\(digits)}",
                                                 with: String(format: "%0\(digits)d", max(1, index)))
        }
        let clean = MediaSupport.sanitizedFileBaseName(output)
        return clean.isEmpty ? baseName : clean
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HHmmss"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

package struct MediaImageOptions: Codable, Equatable {
    package var quality: Double
    package var maxDimension: Int
    package var format: MediaImageFormat
    package var stripMetadata: Bool
    package var resizeMode: MediaImageResizeMode
    package var watermark: MediaImageWatermark
    package var renamePattern: MediaImageRenamePattern
    package var background: MediaImageBackground
    package var preserveModificationDate: Bool

    package init(quality: Double,
         maxDimension: Int,
         format: MediaImageFormat,
         stripMetadata: Bool,
         resizeMode: MediaImageResizeMode? = nil,
         watermark: MediaImageWatermark = .off,
         renamePattern: MediaImageRenamePattern = .automatic,
         background: MediaImageBackground = .transparent,
         preserveModificationDate: Bool = false) {
        self.quality = MediaSupport.sanitizedQuality(quality)
        // Image profiles and their resize mode share one range. Keeping this
        // legacy field on the video-oriented even/7680 sanitizer let the two
        // persisted values silently disagree for large image exports.
        self.maxDimension = MediaSupport.sanitizedImageDimension(maxDimension, fallback: 1600)
        self.format = format
        self.stripMetadata = stripMetadata
        self.resizeMode = resizeMode ?? .maxDimension(self.maxDimension)
        self.watermark = watermark
        self.renamePattern = renamePattern
        self.background = background
        self.preserveModificationDate = preserveModificationDate
    }
}

package struct MediaImageProfile: Codable, Identifiable, Equatable {
    package var id: String
    package var name: String
    package var options: MediaImageOptions

    package init(id: String = UUID().uuidString, name: String, options: MediaImageOptions) {
        self.id = id
        self.name = name
        self.options = options
    }
}

package enum MediaVideoCodec: String, CaseIterable, Identifiable {
    case h264, hevc

    package var id: String { rawValue }

    package static func sanitized(_ value: String) -> MediaVideoCodec {
        MediaVideoCodec(rawValue: value) ?? .h264
    }
}

package struct MediaTrimRange: Equatable {
    package let start: Double
    package let end: Double

    package var duration: Double { max(0, end - start) }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// How the video and GIF tools decide what to shrink.
///
/// `resolution` is the historical behavior: the output dimension is chosen and
/// the file weighs whatever it weighs. `targetSize` inverts it, the weight is
/// chosen and everything else is derived from it.
package enum MediaSizingMode: String, CaseIterable, Identifiable {
    case resolution, targetSize

    package var id: String { rawValue }

    package static func sanitized(_ value: String) -> MediaSizingMode {
        MediaSizingMode(rawValue: value) ?? .resolution
    }
}

package struct MediaVideoSizePlan: Equatable {
    package let size: CGSize
    package let videoBitRate: Int
    package let audioBitRate: Int

    // Spelled out because a memberwise initializer never leaves its module.
    package init(size: CGSize, videoBitRate: Int, audioBitRate: Int) {
        self.size = size
        self.videoBitRate = videoBitRate
        self.audioBitRate = audioBitRate
    }
}

package struct MediaGIFSizePlan: Equatable {
    package let width: Int
    package let fps: Double

    // Spelled out because a memberwise initializer never leaves its module.
    package init(width: Int, fps: Double) {
        self.width = width
        self.fps = fps
    }
}

package enum MediaSupport {
    package static let maxImageRenderDimension = 20_000
    package static let maxImageRenderPixels = 8_192 * 8_192
    package static let maximumGIFFrames = 300
    package static let minimumTargetMegabytes = 1
    package static let maximumTargetMegabytes = 512
    package static let minimumTargetVideoBitRate = 240_000
    package static let minimumTargetGIFWidth = 160
    package static let maximumTargetGIFWidth = 1600
    package static let minimumTargetGIFFPS: Double = 6
    package static let maximumTargetGIFPasses = 4
    /// Muxer overhead plus what rate control overshoots by. Asking the encoder
    /// for slightly less than the ceiling is what makes the first pass land
    /// under it instead of just above.
    package static let targetSizeHeadroom = 0.94
    /// Bits a pixel needs before H.264 starts smearing detail. A budget that
    /// cannot pay this for every source pixel buys fewer pixels rather than
    /// starving the ones it keeps.
    private static let targetBitsPerPixel = 0.07
    private static let maxFilenameBytes = 255

    package static func sanitizedTool(_ value: String) -> MediaTool {
        MediaTool(rawValue: value) ?? .videoCompressor
    }

    package static func sanitizedQuality(_ value: Double) -> Double {
        guard value.isFinite else { return 0.7 }
        return min(1, max(0.1, value))
    }

    package static func sanitizedFPS(_ value: Double, fallback: Double = 12, maxFPS: Double = 60) -> Double {
        guard value.isFinite, value > 0 else { return fallback }
        return min(maxFPS, max(1, value.rounded()))
    }

    package static func sanitizedPixelDimension(_ value: Double, fallback: Int, min: Int = 64, max: Int = 7680) -> Int {
        guard value.isFinite, value > 0 else { return even(fallback) }
        return even(Swift.min(max, Swift.max(min, Int(value.rounded()))))
    }

    package static func sanitizedImageDimension(_ value: Int, fallback: Int, min: Int = 1, max: Int = 20_000) -> Int {
        let clean = value > 0 ? value : fallback
        return Swift.min(max, Swift.max(min, clean))
    }

    package static func sanitizedOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return 0.45 }
        return min(1, max(0.1, value))
    }

    package static func sanitizedWatermarkScale(_ value: Double) -> Double {
        guard value.isFinite else { return 0.18 }
        return min(0.8, max(0.05, value))
    }

    package static func sanitizedTrim(start: Double, end: Double, assetDuration: Double) -> MediaTrimRange {
        guard assetDuration.isFinite, assetDuration > 0 else {
            return MediaTrimRange(start: 0, end: 0)
        }
        let cleanStart = start.isFinite ? max(0, min(start, assetDuration)) : 0
        let proposedEnd = end.isFinite && end > 0 ? end : assetDuration
        let cleanEnd = max(cleanStart, min(proposedEnd, assetDuration))
        return MediaTrimRange(start: cleanStart, end: cleanEnd)
    }

    package static func safeGIFFrameCount(duration: Double, fps: Double) -> Int? {
        guard duration.isFinite, duration > 0, fps.isFinite, fps > 0 else { return nil }
        let count = (duration * fps).rounded(.up)
        guard count.isFinite, count >= 1, count <= Double(maximumGIFFrames) else { return nil }
        return Int(count)
    }

    package static func maximumGIFDuration(fps: Double) -> Int {
        guard fps.isFinite, fps > 0 else { return 1 }
        return max(1, Int(floor(Double(maximumGIFFrames) / fps)))
    }

    package static func gifLoopCount(loops: Bool) -> Int? {
        loops ? 0 : nil
    }

    package static func sanitizedTargetMegabytes(_ value: Int) -> Int {
        Swift.min(maximumTargetMegabytes, Swift.max(minimumTargetMegabytes, value))
    }

    /// Megabytes here are 1000 based, the way a sharing limit is written and
    /// the way Finder reports a file, so a file that fits a "20 MB" ceiling
    /// also fits a 20 MiB one and never the other way around.
    package static func targetBytes(megabytes: Int) -> Int64 {
        Int64(sanitizedTargetMegabytes(megabytes)) * 1_000_000
    }

    /// A file size is a bitrate multiplied by a duration, so a target size is
    /// a bitrate budget. The budget then decides how many pixels are worth
    /// keeping, which is why this returns a size the caller did not pick.
    package static func videoSizePlan(targetBytes: Int64,
                              duration: Double,
                              sourceSize: CGSize,
                              frameRate: Double,
                              hasAudio: Bool,
                              scale: Double = 1) -> MediaVideoSizePlan? {
        guard targetBytes > 0,
              duration.isFinite, duration > 0,
              sourceSize.width.isFinite, sourceSize.height.isFinite,
              sourceSize.width > 0, sourceSize.height > 0,
              scale.isFinite, scale > 0
        else { return nil }

        let fps = sanitizedFPS(frameRate, fallback: 30, maxFPS: 60)
        let audio = hasAudio ? targetAudioBitRate(targetBytes: targetBytes, duration: duration) : 0
        let budget = Int((Double(targetBytes) * 8 * targetSizeHeadroom / duration).rounded(.down)) - audio
        let video = Int(Double(budget) * Swift.min(1, scale))
        guard video >= minimumTargetVideoBitRate else { return nil }

        let affordablePixels = Double(video) / (fps * targetBitsPerPixel)
        let sourcePixels = Double(sourceSize.width) * Double(sourceSize.height)
        let longestEdge = Double(Swift.max(sourceSize.width, sourceSize.height))
        let ratio = Swift.min(1, (affordablePixels / sourcePixels).squareRoot())
        // A tiny frame is worse than a soft one, so scaling stops at 480 on the
        // long edge even when the budget would buy less.
        let floorRatio = Swift.min(1, 480 / longestEdge)
        let maxDimension = Int((longestEdge * Swift.max(ratio, floorRatio)).rounded())
        return MediaVideoSizePlan(size: scaledEvenSize(source: sourceSize, maxDimension: maxDimension),
                                  videoBitRate: video,
                                  audioBitRate: audio)
    }

    package static func targetAudioBitRate(targetBytes: Int64, duration: Double) -> Int {
        guard duration.isFinite, duration > 0, targetBytes > 0 else { return 128_000 }
        return Double(targetBytes) * 8 / duration < 1_200_000 ? 64_000 : 128_000
    }

    /// One pass of rate control lands near the budget, not on it. A pass that
    /// overshoots derives the next scale from what it actually produced, and
    /// gives up at least a tenth so the sequence always converges.
    package static func targetRetryScale(current: Double, actualBytes: Int64, targetBytes: Int64) -> Double? {
        guard current.isFinite, current > 0,
              actualBytes > 0, targetBytes > 0, actualBytes > targetBytes
        else { return nil }
        let next = current * Double(targetBytes) / Double(actualBytes) * targetSizeHeadroom
        guard next.isFinite, next > 0 else { return nil }
        return Swift.min(current * 0.9, next)
    }

    /// Aiming at a size means no frame rate was picked, so the first pass takes
    /// the highest one the frame ceiling allows and the measured passes take it
    /// down from there.
    package static func targetGIFStartFPS(duration: Double, preferred: Double = 15) -> Double {
        guard duration.isFinite, duration > 0 else { return preferred }
        let fitting = (Double(maximumGIFFrames) / duration).rounded(.down)
        return Swift.max(minimumTargetGIFFPS, Swift.min(preferred, fitting))
    }

    package static func targetGIFStartWidth(sourceWidth: CGFloat) -> Int {
        guard sourceWidth.isFinite, sourceWidth > 0 else { return maximumTargetGIFWidth }
        return Swift.max(minimumTargetGIFWidth,
                         Swift.min(maximumTargetGIFWidth, Int(sourceWidth.rounded())))
    }

    /// A GIF has no bitrate to aim at: its weight is frames times pixels, so
    /// overshooting is corrected by dropping frames first, since motion
    /// survives a lower rate better than detail survives a smaller frame.
    package static func gifSizePlan(width: Int, fps: Double,
                            actualBytes: Int64, targetBytes: Int64) -> MediaGIFSizePlan? {
        guard actualBytes > 0, targetBytes > 0, actualBytes > targetBytes else { return nil }
        let currentWidth = Swift.max(1, width)
        let currentFPS = sanitizedFPS(fps, fallback: 12, maxFPS: 30)
        let ratio = Swift.min(0.9, Double(targetBytes) * targetSizeHeadroom / Double(actualBytes))
        let nextFPS = Swift.max(minimumTargetGIFFPS, (currentFPS * ratio).rounded())
        let remaining = Swift.min(1, ratio / (nextFPS / currentFPS))
        let nextWidth = Swift.max(minimumTargetGIFWidth,
                                  Int((Double(currentWidth) * remaining.squareRoot()).rounded()))
        guard nextWidth < currentWidth || nextFPS < currentFPS else { return nil }
        return MediaGIFSizePlan(width: nextWidth, fps: nextFPS)
    }

    package static func imageDecodeMaxPixel(sourceSize: CGSize,
                                    targetSize: CGSize,
                                    resizeMode: MediaImageResizeMode) -> Int? {
        let sourceWidth = max(1, abs(sourceSize.width))
        let sourceHeight = max(1, abs(sourceSize.height))
        let targetWidth = max(1, abs(targetSize.width))
        let targetHeight = max(1, abs(targetSize.height))
        guard resizeMode.kind == .exact else {
            let maxPixel = max(1, Int(max(targetWidth, targetHeight).rounded(.up)))
            return imageRenderSizeIsSafe(targetSize) ? maxPixel : nil
        }
        let horizontalScale = targetWidth / sourceWidth
        let verticalScale = targetHeight / sourceHeight
        let requiredScale: CGFloat
        switch resizeMode.exactMode {
        case .fit:
            requiredScale = min(horizontalScale, verticalScale)
        case .fill, .stretch:
            requiredScale = max(horizontalScale, verticalScale)
        }
        let decodeScale = min(1, max(0, requiredScale))
        let decodedSize = CGSize(width: sourceWidth * decodeScale,
                                 height: sourceHeight * decodeScale)
        guard imageRenderSizeIsSafe(decodedSize) else { return nil }
        return max(1, Int((max(sourceWidth, sourceHeight) * decodeScale).rounded(.up)))
    }

    package static func scaledEvenSize(source: CGSize, maxDimension: Int) -> CGSize {
        let width = max(1, abs(source.width))
        let height = max(1, abs(source.height))
        let maxSide = CGFloat(max(2, maxDimension))
        let scale = min(1, maxSide / max(width, height))
        return CGSize(width: CGFloat(even(max(2, Int((width * scale).rounded())))),
                      height: CGFloat(even(max(2, Int((height * scale).rounded())))))
    }

    package static func scaledVideoSize(source: CGSize, maxDimension: Int) -> CGSize {
        let size = scaledEvenSize(source: source, maxDimension: maxDimension)
        return CGSize(width: CGFloat(multipleOf16(Int(size.width))),
                      height: CGFloat(multipleOf16(Int(size.height))))
    }

    package static func outputURL(for inputURL: URL, suffix: String, fileExtension: String) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let base = visibleOutputBaseName(for: inputURL)
        return outputURL(in: directory, baseName: "\(base)\(suffix)", fileExtension: fileExtension)
    }

    package static func outputURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        directory
            .appendingPathComponent(sanitizedFileBaseName(baseName,
                                                          fileExtension: fileExtension,
                                                          uniquenessSuffixByteReservation: 4))
            .appendingPathExtension(fileExtension)
    }

    package static func visibleOutputBaseName(for inputURL: URL) -> String {
        let raw = inputURL.deletingPathExtension().lastPathComponent
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = trimmed.drop { $0 == "." }
        return visible.isEmpty ? "Output" : String(visible)
    }

    package static func uniqueOutputURL(for inputURL: URL, suffix: String, fileExtension: String,
                                fileManager: FileManager = .default) -> URL {
        let candidate = outputURL(for: inputURL, suffix: suffix, fileExtension: fileExtension)
        return uniqueOutputURL(candidate: candidate, fileManager: fileManager)
    }

    package static func uniqueOutputURL(in directory: URL, baseName: String, fileExtension: String,
                                reservedPaths: Set<String> = [],
                                fileManager: FileManager = .default) -> URL {
        uniqueOutputURL(candidate: outputURL(in: directory, baseName: baseName, fileExtension: fileExtension),
                        reservedPaths: reservedPaths,
                        fileManager: fileManager)
    }

    package static func imageOutputURL(for inputURL: URL,
                               outputDirectory: URL,
                               options: MediaImageOptions,
                               index: Int,
                               outputSize: CGSize,
                               reservedPaths: Set<String> = [],
                               fileManager: FileManager = .default) -> URL {
        let baseName = options.renamePattern.outputBaseName(for: inputURL,
                                                            index: index,
                                                            size: outputSize,
                                                            format: options.format)
        return uniqueOutputURL(in: outputDirectory,
                               baseName: baseName,
                               fileExtension: options.format.fileExtension,
                               reservedPaths: reservedPaths,
                               fileManager: fileManager)
    }

    package static func outputURLByReplacingExtension(_ outputURL: URL,
                                              fileExtension: String,
                                              fileManager: FileManager = .default) -> URL {
        guard outputURL.pathExtension.caseInsensitiveCompare(fileExtension) != .orderedSame else {
            return outputURL
        }
        let candidate = outputURL.deletingPathExtension().appendingPathExtension(fileExtension)
        return uniqueOutputURL(candidate: candidate, fileManager: fileManager)
    }

    package static func urlsInProviderOrder(_ indexedURLs: [(offset: Int, url: URL)]) -> [URL] {
        indexedURLs.sorted { $0.offset < $1.offset }.map(\.url)
    }

    package static func sanitizedFileBaseName(_ value: String,
                                      fileExtension: String = "",
                                      uniquenessSuffixByteReservation: Int = 0) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\\0")
            .union(.newlines)
            .union(.controlCharacters)
        let parts = value.components(separatedBy: invalid)
        let clean = parts.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        let visible = clean.isEmpty ? "Output" : clean
        let extensionBytes = fileExtension.isEmpty ? 0 : fileExtension.utf8.count + 1
        let byteLimit = max(1, maxFilenameBytes - extensionBytes - max(0, uniquenessSuffixByteReservation))
        guard visible.utf8.count > byteLimit else { return visible }
        let shortened = prefix(visible, maxUTF8Bytes: byteLimit)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        return shortened.isEmpty ? "Output" : shortened
    }

    package static func imageDisplaySize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else { return nil }
        return imageDisplaySize(properties: properties)
    }

    package static func watermarkLogo(atPath path: String, maxPixel: Int = 2_048) -> CGImage? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return imageThumbnail(at: URL(fileURLWithPath: trimmed), maxPixel: maxPixel)
    }

    package static func imageThumbnail(at url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ] as CFDictionary)
    }

    package static func imageDisplaySize(properties: [CFString: Any]) -> CGSize? {
        guard let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0,
              width < Double(Int.max), height < Double(Int.max) else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if 5...8 ~= orientation {
            return integralImageSize(width: CGFloat(height), height: CGFloat(width))
        }
        return integralImageSize(width: CGFloat(width), height: CGFloat(height))
    }

    package static func imageRenderSizeIsSafe(_ size: CGSize,
                                      maxDimension: Int = maxImageRenderDimension,
                                      maxPixels: Int = maxImageRenderPixels) -> Bool {
        let width = abs(size.width)
        let height = abs(size.height)
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width <= CGFloat(maxDimension), height <= CGFloat(maxDimension) else { return false }
        return width * height <= CGFloat(maxPixels)
    }

    package static func sanitizedImageProfiles(_ profiles: [MediaImageProfile]) -> [MediaImageProfile] {
        var seenIDs = Set<String>()
        return profiles.enumerated().map { offset, profile in
            let trimmedID = profile.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = trimmedID.isEmpty || seenIDs.contains(trimmedID) ? UUID().uuidString : trimmedID
            seenIDs.insert(id)
            let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmedName.isEmpty ? "Profile \(offset + 1)" : trimmedName
            return MediaImageProfile(id: id, name: name, options: profile.options)
        }
    }

    package static func portableImageProfiles(_ rawValue: String) -> String? {
        guard let data = rawValue.data(using: .utf8),
              var profiles = try? JSONDecoder().decode([MediaImageProfile].self, from: data) else {
            return nil
        }
        for index in profiles.indices {
            var watermark = profiles[index].options.watermark
            watermark.logoPath = ""
            switch watermark.kind {
            case .logo:
                watermark.kind = .off
            case .textAndLogo:
                watermark.kind = watermark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .off : .text
            case .off, .text:
                break
            }
            profiles[index].options.watermark = watermark
        }
        guard let portableData = try? JSONEncoder().encode(profiles) else { return nil }
        return String(data: portableData, encoding: .utf8)
    }

    package static func integralImageSize(width: CGFloat, height: CGFloat) -> CGSize {
        CGSize(width: max(1, width.rounded()),
               height: max(1, height.rounded()))
    }

    private static func uniqueOutputURL(candidate: URL,
                                        reservedPaths: Set<String> = [],
                                        fileManager: FileManager = .default) -> URL {
        guard !reservedPaths.contains(candidate.standardizedFileURL.path),
              !fileManager.fileExists(atPath: candidate.path) else {
            let directory = candidate.deletingLastPathComponent()
            let base = candidate.deletingPathExtension().lastPathComponent
            let ext = candidate.pathExtension
            var index = 2
            while true {
                let suffix = " \(index)"
                let uniqueBase = sanitizedFileBaseName(base,
                                                       fileExtension: ext,
                                                       uniquenessSuffixByteReservation: suffix.utf8.count)
                let url = directory.appendingPathComponent("\(uniqueBase)\(suffix)").appendingPathExtension(ext)
                if !reservedPaths.contains(url.standardizedFileURL.path),
                   !fileManager.fileExists(atPath: url.path) { return url }
                index += 1
            }
        }
        return candidate
    }

    package static func fileURLsReferToSameItem(_ lhs: URL, _ rhs: URL) -> Bool {
        var left = stat()
        var right = stat()
        let leftExists = lhs.withUnsafeFileSystemRepresentation { path in
            path.map { stat($0, &left) == 0 } ?? false
        }
        let rightExists = rhs.withUnsafeFileSystemRepresentation { path in
            path.map { stat($0, &right) == 0 } ?? false
        }
        if leftExists, rightExists {
            return left.st_dev == right.st_dev && left.st_ino == right.st_ino
        }
        let leftPath = lhs.resolvingSymlinksInPath().standardizedFileURL.path
        let rightPath = rhs.resolvingSymlinksInPath().standardizedFileURL.path
        return leftPath == rightPath
    }

    package static func temporaryOutputURL(for outputURL: URL,
                                   fileManager: FileManager = .default) throws -> URL {
        let directory = try fileManager.url(for: .itemReplacementDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: outputURL,
                                            create: true)
        let ext = outputURL.pathExtension
        var temporary = directory.appendingPathComponent("Output")
        if !ext.isEmpty { temporary.appendPathExtension(ext) }
        return temporary
    }

    package static func discardStagedOutput(_ stagedURL: URL,
                                    fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: stagedURL.deletingLastPathComponent())
    }

    package static func installStagedOutput(_ stagedURL: URL, at outputURL: URL,
                                    replacingExisting: Bool = true) throws {
        let result: Int32 = stagedURL.withUnsafeFileSystemRepresentation { stagedPath in
            outputURL.withUnsafeFileSystemRepresentation { outputPath in
                guard let stagedPath, let outputPath else { return Int32(-1) }
                return replacingExisting ? rename(stagedPath, outputPath)
                    : renamex_np(stagedPath, outputPath, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    package static func makeVisibleIfNeeded(_ outputURL: URL, fileManager: FileManager = .default) {
        guard shouldForceVisibleOutput(outputURL),
              fileManager.fileExists(atPath: outputURL.path) else { return }
        try? (outputURL as NSURL).setResourceValue(false, forKey: .isHiddenKey)
        var info = stat()
        guard outputURL.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return lstat(path, &info) == 0
        }) else { return }
        let flags = UInt32(info.st_flags)
        let visibleFlags = flags & ~UInt32(UF_HIDDEN)
        guard visibleFlags != flags else { return }
        outputURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = chflags(path, visibleFlags)
        }
    }

    /// Whether a dropped file fits the selected tool, mirroring the open
    /// panel's filter. Without this, dropping a PDF on the image tool would
    /// "succeed" by silently rasterizing page one (ImageIO opens PDFs).
    package static func inputMatchesTool(contentType: UTType?, inputTypes: [UTType]) -> Bool {
        guard let contentType else { return false }
        return inputTypes.contains { contentType.conforms(to: $0) }
    }

    /// Whether the result deserves the "came out larger" caption: growth is
    /// normal (PDF wraps the image, high quality can beat the source) but a
    /// "compressor" should say so instead of looking broken. Unknown sizes
    /// (zero) never trigger it.
    package static func outputGrew(originalBytes: Int64, outputBytes: Int64) -> Bool {
        originalBytes > 0 && outputBytes > originalBytes
    }

    package static func recognitionLanguages(for languageRawValue: String) -> [String] {
        switch languageRawValue {
        case "pt-BR": return ["pt-BR", "en-US"]
        case "tr": return ["tr-TR", "en-US"]
        case "ru": return ["ru-RU", "en-US"]
        case "es": return ["es-ES", "en-US"]
        case "de": return ["de-DE", "en-US"]
        case "fr": return ["fr-FR", "en-US"]
        case "it": return ["it-IT", "en-US"]
        case "ja": return ["ja-JP", "en-US"]
        case "ko": return ["ko-KR", "en-US"]
        case "uk": return ["uk-UA", "en-US"]
        case "zh-Hans": return ["zh-Hans", "en-US"]
        case "zh-TW", "zh-HK": return ["zh-Hant", "en-US"]
        default: return ["en-US"]
        }
    }

    private static func shouldForceVisibleOutput(_ outputURL: URL) -> Bool {
        let name = outputURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !name.hasPrefix(".")
    }

    private static func even(_ value: Int) -> Int {
        let positive = max(2, value)
        return positive.isMultiple(of: 2) ? positive : positive - 1
    }

    private static func multipleOf16(_ value: Int) -> Int {
        max(16, (max(16, value) / 16) * 16)
    }

    private static func prefix(_ value: String, maxUTF8Bytes: Int) -> String {
        var result = ""
        var usedBytes = 0
        for character in value {
            let count = String(character).utf8.count
            guard usedBytes + count <= maxUTF8Bytes else { break }
            result.append(character)
            usedBytes += count
        }
        return result
    }
}
