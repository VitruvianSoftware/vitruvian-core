// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO

/// Title and channel read from YouTube's oEmbed endpoint when a bridge link preview gave none.
public struct YouTubeMetadata: Equatable, Sendable {
    public let title: String
    public let authorName: String?

    public init(title: String, authorName: String? = nil) {
        self.title = title
        self.authorName = authorName
    }
}

/// Where a video's still picture and title live, and small in-memory caches for fetching them.
public enum EmbedThumbnail {
    private static func isValidYouTubeVideoID(_ videoID: String) -> Bool {
        videoID.utf8.count == 11
            && videoID.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
            }
    }

    /// YouTube's picture for `videoID` (480 by 360, with black bars above and below the 16:9 still; the card crops them), or nil when the ID is not exactly 11 letters, digits, `-` or `_`.
    public static func youTubeURL(videoID: String) -> URL? {
        guard isValidYouTubeVideoID(videoID) else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    /// YouTube's oEmbed JSON endpoint for `videoID`, or nil when the ID is not exactly 11 letters, digits, `-` or `_`.
    public static func youTubeOEmbedURL(videoID: String) -> URL? {
        guard isValidYouTubeVideoID(videoID) else { return nil }
        return URL(string: "https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D\(videoID)&format=json")
    }

    private static let cache: NSCache<NSString, CGImageBox> = {
        let cache = NSCache<NSString, CGImageBox>()
        cache.countLimit = 100
        cache.totalCostLimit = 32 * 1024 * 1024 // pixel bytes
        return cache
    }()

    private static let metadataCache: NSCache<NSString, MetadataBox> = {
        let cache = NSCache<NSString, MetadataBox>()
        cache.countLimit = 200
        return cache
    }()

    private final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private final class MetadataBox {
        let metadata: YouTubeMetadata
        init(_ metadata: YouTubeMetadata) { self.metadata = metadata }
    }

    private struct OEmbedPayload: Decodable {
        let title: String?
        let author_name: String?
    }

    /// Forgets every kept picture and metadata entry (for tests).
    public static func clearCache() {
        cache.removeAllObjects()
        metadataCache.removeAllObjects()
    }

    /// Synchronous in-memory lookup for a previously fetched YouTube still.
    public static func cachedThumbnail(videoID: String) -> CGImage? {
        guard isValidYouTubeVideoID(videoID) else { return nil }
        return cache.object(forKey: videoID as NSString)?.image
    }

    /// Synchronous in-memory lookup for previously fetched YouTube oEmbed metadata.
    public static func cachedMetadata(videoID: String) -> YouTubeMetadata? {
        guard isValidYouTubeVideoID(videoID) else { return nil }
        return metadataCache.object(forKey: videoID as NSString)?.metadata
    }

    /// The still picture of a YouTube video, kept in memory for next time. The only address ever asked for is the one
    /// `youTubeURL` builds, on i.ytimg.com, so an ID that is not exactly right asks for nothing. Nil on any failure or
    /// a non-picture; no cookies are sent.
    public static func fetch(videoID: String, session: URLSession = .shared) async -> CGImage? {
        guard let url = youTubeURL(videoID: videoID) else { return nil }
        let key = videoID as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= 2_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        cache.setObject(CGImageBox(image), forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    /// The video title and channel from YouTube's oEmbed JSON endpoint, kept in memory for next time. Cookieless and
    /// strictly bounded to validated 11-character IDs.
    public static func fetchMetadata(videoID: String, session: URLSession = .shared) async -> YouTubeMetadata? {
        guard let url = youTubeOEmbedURL(videoID: videoID) else { return nil }
        let key = videoID as NSString
        if let hit = metadataCache.object(forKey: key) { return hit.metadata }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= 64_000,
              let payload = try? JSONDecoder().decode(OEmbedPayload.self, from: data),
              let rawTitle = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTitle.isEmpty
        else { return nil }
        let rawAuthor = payload.author_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadata = YouTubeMetadata(
            title: rawTitle,
            authorName: rawAuthor?.isEmpty == false ? rawAuthor : nil
        )
        metadataCache.setObject(MetadataBox(metadata), forKey: key)
        return metadata
    }
}
