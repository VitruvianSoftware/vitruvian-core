// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import CryptoKit
import Foundation

/// The newest Vitruvian Remote for Android, read from the same signed update
/// feed the phone's Settings → About reads (`UpdateFeed.kt`), so the Mac can say
/// when the paired phone is behind.
///
/// Trust comes from the Ed25519 signature, not from the website: a feed that
/// fails the check, or that this code does not fully understand, is treated as
/// if there were no feed at all, and the menu says nothing.
public enum PhoneAppFeed {
    public static let feedURL = URL(string: "https://vitruviansoftware.dev/updates/android/vitruvian-remote.json")!
    public static let signatureURL = URL(string: "https://vitruviansoftware.dev/updates/android/vitruvian-remote.json.sig")!

    /// Same line as `catalog/public-key.txt`.
    public static let publicKey = "ysvqcMifelrOyxEx01sOS4B5VN585nBLKkdaaT0xyWY="

    static let kind = "vitruvian-android-update"
    static let packageName = "dev.vitruvian.remote"
    static let downloadPrefix =
        "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-remote-v"
    static let maxFeedBytes = 64 * 1024

    /// The version the feed names, or nil when the signature does not check
    /// out or the feed is not one this code fully understands. Mirrors the
    /// checks in `UpdateFeed.verify` / `UpdateFeed.parse` on the phone.
    public static func verifiedVersion(feed: Data, signature: String, publicKey: String = publicKey) -> String? {
        guard feed.count <= maxFeedBytes,
              let sig = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
              let keyBytes = Data(base64Encoded: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes),
              key.isValidSignature(sig, for: feed)
        else { return nil }
        guard let o = (try? JSONSerialization.jsonObject(with: feed)) as? [String: Any],
              o["kind"] as? String == kind,
              (o["schema"] as? NSNumber)?.doubleValue == 1,
              o["packageName"] as? String == packageName,
              let version = o["version"] as? String,
              let code = PhoneAppVersion.code(version),
              (o["versionCode"] as? NSNumber)?.int64Value == code,
              let apk = o["apk"] as? [String: Any],
              apk["url"] as? String == "\(downloadPrefix)\(version)/VitruvianRemote-\(version).apk"
        else { return nil }
        return version
    }
}

/// Release versions are `major.minor.patch`; the Android versionCode is
/// `major*10000 + minor*100 + patch` (the phone's `Versions.code`).
public enum PhoneAppVersion {
    public static func code(_ version: String) -> Int64? {
        let parts = version.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let limits = [999, 99, 99]
        var nums: [Int64] = []
        for (part, limit) in zip(parts, limits) {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                  let n = Int64(part), n <= limit
            else { return nil }
            nums.append(n)
        }
        return nums[0] * 10000 + nums[1] * 100 + nums[2]
    }

    /// True only when both are plain releases and `latest` is newer. A phone on
    /// a dev build, or a feed older than the phone, says nothing.
    public static func isBehind(phone: String, latest: String) -> Bool {
        guard let p = code(phone), let l = code(latest) else { return false }
        return l > p
    }
}

/// Fetches the feed and its signature at most every few hours and remembers
/// the verified version. Never blocks a status poll: `latest()` answers from
/// memory at once and starts a refresh in the background when it is due.
public actor PhoneAppFeedCache {
    public static let shared = PhoneAppFeedCache()

    private var version: String?
    private var checkedAt: Date?
    private var inFlight = false
    private let fetch: @Sendable () async -> (Data, String)?
    private let okInterval: TimeInterval
    private let failInterval: TimeInterval
    private let publicKey: String

    public init(
        okInterval: TimeInterval = 6 * 3600,
        failInterval: TimeInterval = 30 * 60,
        publicKey: String = PhoneAppFeed.publicKey,
        fetch: (@Sendable () async -> (Data, String)?)? = nil
    ) {
        self.publicKey = publicKey
        self.okInterval = okInterval
        self.failInterval = failInterval
        self.fetch = fetch ?? PhoneAppFeedCache.download
    }

    /// The last verified version (nil when none yet, or the last check failed).
    public func latest(now: Date = Date()) -> String? {
        let due: Bool
        if let checkedAt {
            due = now.timeIntervalSince(checkedAt) >= (version == nil ? failInterval : okInterval)
        } else {
            due = true
        }
        if due, !inFlight {
            inFlight = true
            Task { await self.refresh() }
        }
        return version
    }

    /// Fetch and verify now. Anything short of a verified feed clears the
    /// version, so a feed that stops verifying stops being believed.
    public func refresh() async {
        let got = await fetch()
        version = got.flatMap { PhoneAppFeed.verifiedVersion(feed: $0.0, signature: $0.1, publicKey: publicKey) }
        checkedAt = Date()
        inFlight = false
    }

    /// Both files over HTTPS; any non-200 (the feed is 404 until its first
    /// signed copy is published) means no answer.
    @Sendable static func download() async -> (Data, String)? {
        func get(_ url: URL, limit: Int) async -> Data? {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            req.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= limit
            else { return nil }
            return data
        }
        guard let feed = await get(PhoneAppFeed.feedURL, limit: PhoneAppFeed.maxFeedBytes),
              let sig = await get(PhoneAppFeed.signatureURL, limit: 1024),
              let sigText = String(data: sig, encoding: .utf8)
        else { return nil }
        return (feed, sigText)
    }
}
