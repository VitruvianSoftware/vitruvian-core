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
/// Whether a request may be made at all is `LinkPreviewPolicy`'s ("Show link previews"): with it off the answer is nil
/// and nothing is asked. Each address is asked of the engine at most once while this lives (the answer, a picture or
/// none, is kept; calls that arrive together share one request), and the engine keeps its own answer per address
/// across launches, so a card that scrolls away and back, or is drawn twice, never asks again. A question that could not
/// be asked (the engine is not up) is not kept: the next card to be drawn asks again.
@MainActor
public final class LinkPreviewImages {
    /// Asks for the picture of a page: nil when it has none, a throw when the question could not be asked (no engine).
    public typealias Fetch = @MainActor (URL) async throws -> LinkPreviewImage?

    private enum Entry {
        case found(LinkPreviewImage)
        case noPicture
    }

    private let fetch: Fetch
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<LinkPreviewImage?, Error>] = [:]
    /// How many requests went to `fetch`, for tests.
    public private(set) var requestCount = 0

    public init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// Asks the engine that is up when a request is made.
    public convenience init(client: @escaping @MainActor () -> EngineClient?) {
        self.init { url in
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
    /// shows it with no wait.
    public func cached(for url: URL) -> LinkPreviewImage? {
        if case let .found(image)? = entries[Self.key(url)] { return image }
        return nil
    }

    /// The picture of the page at `url`, asking the engine once if it hasn't been asked. nil when "Show link previews"
    /// is off (nothing is asked), when the address isn't http(s), or when the page has no picture.
    public func image(for url: URL, showLinkPreviews: Bool) async -> LinkPreviewImage? {
        guard LinkPreviewPolicy.mayRequest(url, showLinkPreviews: showLinkPreviews) else { return nil }
        let key = Self.key(url)
        switch entries[key] {
        case let .found(image)?: return image
        case .noPicture?: return nil
        case nil: break
        }
        if let running = inFlight[key] { return try? await running.value }
        requestCount += 1
        let fetch = self.fetch
        let task = Task { @MainActor in try await fetch(url) }
        inFlight[key] = task
        let answer = await task.result
        inFlight[key] = nil
        guard case let .success(image) = answer else { return nil }
        entries[key] = image.map(Entry.found) ?? Entry.noPicture
        return image
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
