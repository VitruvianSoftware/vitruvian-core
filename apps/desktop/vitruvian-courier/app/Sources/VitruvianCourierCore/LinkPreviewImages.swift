// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A link page's own picture, saved on this Mac by the engine (`linkPreview.image`).
public struct LinkPreviewImage: Equatable, Sendable {
    public let path: String
    public let width: Int?
    public let height: Int?

    public init(path: String, width: Int? = nil, height: Int? = nil) {
        self.path = path
        self.width = width
        self.height = height
    }
}

/// Gets the picture of a link's page for a link card whose chat network sent a preview with none (Google Chat's
/// previews carry the title and site only; Beeper fetches the picture itself). One of these is shared by every card of
/// a chat window.
///
/// Whether a request may be made at all is `LinkPreviewPolicy`'s ("Show link previews", https addresses only): with it
/// off the answer is nil, nothing is asked, requests that are waiting their turn are dropped, and a picture got earlier
/// is not handed out (`cached`) until it is on again. Each address is asked of the engine at most once while this
/// lives (the answer, a picture or none, is kept; calls that arrive together share one request; at most
/// `maxConcurrent` run at once and the rest wait), and the engine keeps its own answer per address across launches, so a
/// card that scrolls away and back, or is drawn twice, never asks again.
///
/// A question the engine cannot answer at all (an older engine without `linkPreview.image`, or one that refuses the
/// address) is remembered as "no picture" for the session. A question that could not be asked yet (the engine is not up,
/// or did not answer in time) is asked again only after a wait that grows (5 s, 15 s, 45 s, up to 5 minutes).
@MainActor
public final class LinkPreviewImages {
    /// Asks for the picture of a page: nil when it has none, a throw when the question could not be answered.
    public typealias Fetch = @MainActor (URL) async throws -> LinkPreviewImage?

    private enum Entry {
        case found(LinkPreviewImage)
        case noPicture
    }

    /// A request that was waiting its turn when Show link previews went off: not asked, and not remembered.
    private struct Dropped: Error {}

    private let fetch: Fetch
    private let allows: @MainActor () -> Bool
    private let now: () -> Date
    private let maxConcurrent: Int
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<LinkPreviewImage?, Error>] = [:]
    private var failures: [String: (count: Int, retryAfter: Date)] = [:]
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// How many requests went to `fetch`, for tests.
    public private(set) var requestCount = 0

    /// - Parameters:
    ///   - allows: whether "Show link previews" is on right now; asked again when a waiting request gets its turn.
    ///   - now: the clock the retry wait is measured by.
    ///   - maxConcurrent: how many requests run at once; the rest wait their turn.
    public init(allows: @escaping @MainActor () -> Bool = { true }, now: @escaping () -> Date = Date.init,
                maxConcurrent: Int = 3, fetch: @escaping Fetch) {
        self.allows = allows
        self.now = now
        self.maxConcurrent = max(1, maxConcurrent)
        self.fetch = fetch
    }

    /// Asks the engine that is up when a request is made.
    public convenience init(allows: @escaping @MainActor () -> Bool = { true },
                            client: @escaping @MainActor () -> EngineClient?) {
        self.init(allows: allows) { url in
            guard let client = client() else { throw EngineError.notConnected }
            let result: LinkPreviewImageResult = try await client.call(
                "linkPreview.image", LinkPreviewImageParams(url: url.absoluteString))
            guard let path = result.imagePath, !path.isEmpty else { return nil }
            return LinkPreviewImage(path: path, width: result.imageWidth, height: result.imageHeight)
        }
    }

    private static func key(_ url: URL) -> String {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.fragment = nil
        return parts?.string ?? url.absoluteString
    }

    /// The picture already got for `url`: memory only, never a request. What a card draws first, so a card drawn again
    /// shows it with no wait. nil while Show link previews is off.
    public func cached(for url: URL) -> LinkPreviewImage? {
        guard allows(), case let .found(image)? = entries[Self.key(url)] else { return nil }
        return image
    }

    private func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) } // the slot is handed over: `running` stays
    }

    private func release() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }

    /// How long to wait before asking again after the `count`th question that could not be answered.
    static func retryDelay(afterFailures count: Int) -> TimeInterval {
        min(300, 5 * pow(3, Double(max(0, count - 1))))
    }

    /// The picture of the page at `url`, asking the engine once if it hasn't been asked. nil when "Show link previews"
    /// is off (nothing is asked), when the address isn't https, when the page has no picture, or while a question that
    /// could not be answered waits to be asked again.
    public func image(for url: URL, showLinkPreviews: Bool) async -> LinkPreviewImage? {
        guard allows(), LinkPreviewPolicy.mayRequestPageImage(url, showLinkPreviews: showLinkPreviews) else { return nil }
        let key = Self.key(url)
        switch entries[key] {
        case let .found(image)?: return image
        case .noPicture?: return nil
        case nil: break
        }
        if let running = inFlight[key] { return try? await running.value }
        if let failure = failures[key], now() < failure.retryAfter { return nil }
        requestCount += 1
        let fetch = self.fetch
        let task = Task { @MainActor () -> LinkPreviewImage? in
            await self.acquire()
            defer { self.release() }
            guard self.allows() else { throw Dropped() }
            return try await fetch(url)
        }
        inFlight[key] = task
        let answer = await task.result
        inFlight[key] = nil
        switch answer {
        case let .success(image):
            failures[key] = nil
            entries[key] = image.map(Entry.found) ?? Entry.noPicture
            return allows() ? image : nil
        case let .failure(error):
            if error is Dropped {
                requestCount -= 1
            } else if let engineError = error as? EngineError, case let .rpc(code, _, _) = engineError,
                      code == .methodNotFound || code == .invalidParams {
                entries[key] = Entry.noPicture // this engine can't, or won't, answer for this link: not asked again
            } else {
                let count = (failures[key]?.count ?? 0) + 1
                failures[key] = (count, now().addingTimeInterval(Self.retryDelay(afterFailures: count)))
            }
            return nil
        }
    }
}

extension LinkPreviewItem {
    /// The page the card opens: the preview's own address, else the one matched in the text; http(s) only.
    public var pageURL: URL? {
        let raw = (url?.isEmpty == false ? url : matchedURL) ?? ""
        guard let page = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = page.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return page
    }
}
