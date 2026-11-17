// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO

/// Where a video's still picture lives, and a small in-memory cache for fetching it.
public enum EmbedThumbnail {
    /// YouTube's picture for `videoID` (320 by 180), or nil when the ID is not exactly 11 letters, digits, `-` or `_`.
    public static func youTubeURL(videoID: String) -> URL? {
        guard videoID.utf8.count == 11,
              videoID.unicodeScalars.allSatisfy({ scalar in
                  scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
              })
        else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
    }

    private static let cache: NSCache<NSString, CGImageBox> = {
        let cache = NSCache<NSString, CGImageBox>()
        cache.countLimit = 100
        cache.totalCostLimit = 32 * 1024 * 1024 // pixel bytes
        return cache
    }()

    private final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// Forgets every kept picture (for tests).
    public static func clearCache() { cache.removeAllObjects() }

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
}
