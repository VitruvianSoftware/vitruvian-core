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

    private static let cache = NSCache<NSURL, CGImageBox>()

    private final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// The picture at an `https` address, kept in memory for next time. Nil on any failure or a non-picture; nothing
    /// is sent but the request itself (no cookies, no referrer).
    public static func fetch(_ url: URL, session: URLSession = .shared) async -> CGImage? {
        guard url.scheme?.lowercased() == "https" else { return nil }
        if let hit = cache.object(forKey: url as NSURL) { return hit.image }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= 2_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        cache.setObject(CGImageBox(image), forKey: url as NSURL)
        return image
    }
}
