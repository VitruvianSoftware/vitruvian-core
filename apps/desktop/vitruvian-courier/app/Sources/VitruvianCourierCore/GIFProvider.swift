// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct GIFCandidate: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// The GIF to send (an MP4 only when the service has no GIF for it).
    public var mediaURL: String
    public var mimeType: String
    /// The same GIF as an MP4 loop, a fraction of the size, for a chat whose network takes MP4 as a GIF.
    public var mp4URL: String?
    public var width: Int?
    public var height: Int?
    /// A small animated GIF for the picker's tile, when the provider has one.
    public var previewURL: String?

    public init(
        id: String,
        title: String,
        mediaURL: String,
        mimeType: String,
        width: Int? = nil,
        height: Int? = nil,
        previewURL: String? = nil,
        mp4URL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.mediaURL = mediaURL
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.previewURL = previewURL
        self.mp4URL = mp4URL
    }
}

/// Why a GIF could not be fetched.
public enum GIFProviderError: Error, Equatable, Sendable {
    /// There is no key, or the provider is not available for another reason.
    case unavailable
    /// The provider answered with something that is not what its API says.
    case badResponse
    /// The provider answered with an error status.
    case status(Int)
    /// A file's address is not one the provider serves from, or the file is too big.
    case refusedFile
}

public protocol GIFProvider: Sendable {
    var isAvailable: Bool { get }
    var unavailableReason: String { get }
    func trending() async throws -> [GIFCandidate]
    func search(_ query: String) async throws -> [GIFCandidate]
    /// Downloads the file to send for `candidate` to this Mac and returns where it is: its MP4 loop with `asMP4` (when
    /// it has one), else its GIF.
    func fetchFile(for candidate: GIFCandidate, asMP4: Bool) async throws -> URL
    /// Downloads the small animated preview for `candidate`; nil when it has none.
    func fetchPreview(for candidate: GIFCandidate) async throws -> URL?
}

extension GIFProvider {
    public var unavailableReason: String {
        String(localized: "Online GIF search isn’t available yet in Vitruvian Courier. You can still send GIFs from your recent history or local files on this Mac.")
    }

    public func fetchFile(for candidate: GIFCandidate, asMP4: Bool) async throws -> URL { throw GIFProviderError.unavailable }
    /// The GIF itself.
    public func fetchFile(for candidate: GIFCandidate) async throws -> URL {
        try await fetchFile(for: candidate, asMP4: false)
    }
    public func fetchPreview(for candidate: GIFCandidate) async throws -> URL? { nil }
}

public struct StubGIFProvider: GIFProvider {
    public init() {}
    public var isAvailable: Bool { false }
    public var unavailableReason: String {
        String(localized: "Online GIF search isn’t available yet in Vitruvian Courier. You can still send GIFs from your recent history or local files on this Mac.")
    }
    public func trending() async throws -> [GIFCandidate] { [] }
    public func search(_ query: String) async throws -> [GIFCandidate] { [] }
}

// MARK: - The question asked before any GIF request

/// The one question every request Courier makes to a GIF service asks first: "Search GIFs online"
/// (`ComposerPreferences.searchGIFsOnline`, on by default), and is there a key to ask with.
///
/// Off, Courier asks the GIF service for nothing, so it never learns what was typed in GIF search, or this Mac's
/// address. The picker then offers recent GIFs and "Choose GIF from Mac…". The same goes for downloading a GIF that
/// was picked from the results.
public enum GIFSearchPolicy {
    /// The line under the setting.
    public static var settingExplanation: String {
        String(localized: "What you type in GIF search, and your network address, go to KLIPY.")
    }

    /// Whether Courier may make a request to the GIF service.
    public static func mayRequest(searchGIFsOnline: Bool, providerAvailable: Bool) -> Bool {
        searchGIFsOnline && providerAvailable
    }
}

// MARK: - KLIPY

/// One HTTP exchange, so tests can answer from fixtures and never reach the network.
public protocol GIFHTTPTransport: Sendable {
    /// The reply's body and status code.
    func send(_ request: URLRequest) async throws -> (body: Data, status: Int)
}

/// The real network: URLSession, with no cookies sent.
public struct URLSessionGIFTransport: GIFHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (body: Data, status: Int) {
        var request = request
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Where the KLIPY key is read from. It is never in git or in a Bazel output: the build tooling adds it to the finished
/// app as `Contents/Resources/KlipyApp.plist` (`api_key`, a string), as it does the Telegram app ID
/// (`apps/desktop/vitruvian-courier/app/README.md`, "KLIPY key"). An app without the file hides online GIF search.
public enum KlipyConfiguration {
    /// The file in the app's Resources, and the key inside it.
    public static let resourceName = "KlipyApp"
    public static let resourceExtension = "plist"
    public static let plistKey = "api_key"

    /// A key is a run of letters, digits and `._~-`, up to 200 long: the characters that are safe in an address, so it
    /// can sit in the request's path as it is.
    public static func validKey(_ raw: String?) -> String? {
        guard let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty, key.utf8.count <= 200,
              key.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._~-".unicodeScalars.contains($0)) })
        else { return nil }
        return key
    }

    /// The key in the contents of a `KlipyApp.plist`, when it holds one that fits.
    public static func apiKey(plist data: Data?) -> String? {
        guard let data,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return validKey(plist[plistKey] as? String)
    }

    /// The key in an app's Resources, when it has the file and it holds one that fits.
    public static func apiKey(in bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else { return nil }
        return apiKey(plist: try? Data(contentsOf: url))
    }
}

/// KLIPY's GIF API (docs.klipy.com, "GIF API"): `GET https://api.klipy.com/api/v1/{app_key}/gifs/trending` and
/// `.../gifs/search?q=`, both paged (`page`, `per_page`) and answering
/// `{"result": true, "data": {"data": [item, …], "current_page", "per_page", "has_next"}}`, where each item has `id`,
/// `slug`, `title` and `file`, a map from a size (`hd`, `md`, `sm`, `xs`) to a map from a format (`gif`, `webp`, `jpg`,
/// `mp4`, `webm`) to `{url, width, height, size}`.
///
/// Everything that knows that shape is here, in `KlipyAPI`: the requests it builds and the way a reply becomes
/// `GIFCandidate`s. If KLIPY's shape differs from the docs in some detail, this is the one place to fix.
public enum KlipyAPI {
    public static let host = "api.klipy.com"
    public static let defaultPageSize = 24

    /// KLIPY serves media from `static.klipy.com`, `static1.klipy.com` and so on; nothing else is downloaded.
    public static func isMediaHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "klipy.com" || host.hasSuffix(".klipy.com")
    }

    public static func trendingRequest(apiKey: String, page: Int = 1, perPage: Int = defaultPageSize) -> URLRequest? {
        request(apiKey: apiKey, endpoint: "trending", query: [], page: page, perPage: perPage)
    }

    public static func searchRequest(
        apiKey: String,
        query: String,
        page: Int = 1,
        perPage: Int = defaultPageSize
    ) -> URLRequest? {
        request(apiKey: apiKey, endpoint: "search", query: [URLQueryItem(name: "q", value: query)], page: page, perPage: perPage)
    }

    private static func request(
        apiKey: String,
        endpoint: String,
        query: [URLQueryItem],
        page: Int,
        perPage: Int
    ) -> URLRequest? {
        guard let key = KlipyConfiguration.validKey(apiKey) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v1/\(key)/gifs/\(endpoint)"
        // No customer_id and no locale: they are optional, and both would tell KLIPY more than a search needs.
        components.queryItems = query + [
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "per_page", value: String(min(max(perPage, 1), 50))),
            URLQueryItem(name: "content_filter", value: "medium"),
            URLQueryItem(name: "format_filter", value: "gif,mp4"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        return request
    }

    private struct Reply: Decodable {
        struct Page: Decodable {
            var data: [LossyItem]?
        }

        var result: Bool?
        var data: Page?
    }

    /// An item that does not decode is dropped on its own; the rest of the page is kept.
    private struct LossyItem: Decodable {
        var item: Item?

        init(from decoder: Decoder) throws {
            item = try? Item(from: decoder)
        }
    }

    private struct Item: Decodable {
        struct Format: Decodable {
            var url: String?
            var width: Int?
            var height: Int?
        }

        // KLIPY's ids are large numbers; a string id is accepted too.
        var id: FlexibleID?
        var slug: String?
        var title: String?
        /// "gif" for a GIF. KLIPY can mix adverts into a page (type "ad"); only a GIF is offered (a clip is a video with sound).
        var type: String?
        var file: [String: [String: Format]]?
    }

    /// An `id` that is a number or a string.
    private struct FlexibleID: Decodable {
        var text: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int64.self) {
                text = String(number)
            } else {
                text = try container.decode(String.self)
            }
        }
    }

    /// The GIFs in a reply. An item with no file to send is left out; the rest are kept.
    public static func candidates(from body: Data) throws -> [GIFCandidate] {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: body), reply.result != false, let items = reply.data?.data
        else { throw GIFProviderError.badResponse }
        return items.compactMap { $0.item.flatMap(candidate) }
    }

    private static func candidate(_ item: Item) -> GIFCandidate? {
        // Never an advert or a clip (a video with sound): only an item that says it is a GIF is shown. No type, or another one, is skipped.
        guard let type = item.type?.lowercased(), type == "gif" else { return nil }
        guard let id = item.id?.text ?? item.slug, !id.isEmpty, let file = item.file else { return nil }
        // To send: the GIF (medium, else small), or its MP4 loop where the chat takes one. To show: a small GIF.
        let sending = pick(file, sizes: ["md", "sm", "hd", "xs"], formats: ["gif", "mp4"])
        guard let (format, media) = sending, let mediaURL = media.url else { return nil }
        let loop = pick(file, sizes: ["md", "sm", "hd", "xs"], formats: ["mp4"])?.1.url
        let preview = pick(file, sizes: ["sm", "xs", "md"], formats: ["gif"])?.1.url
        let named = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = named.isEmpty ? (item.slug ?? "GIF").trimmingCharacters(in: .whitespacesAndNewlines) : named
        return GIFCandidate(
            id: id,
            title: title.isEmpty ? "GIF" : title,
            mediaURL: mediaURL,
            mimeType: format == "mp4" ? "video/mp4" : "image/gif",
            width: media.width,
            height: media.height,
            previewURL: preview,
            mp4URL: loop
        )
    }

    private static func pick(
        _ file: [String: [String: Item.Format]],
        sizes: [String],
        formats: [String]
    ) -> (String, Item.Format)? {
        for format in formats {
            for size in sizes {
                if let found = file[size]?[format], found.url != nil { return (format, found) }
            }
        }
        return nil
    }
}

/// KLIPY as a `GIFProvider`: what Beeper uses, and a GIF API meant for apps like this one.
public struct KlipyGIFProvider: GIFProvider {
    /// The biggest file Courier downloads for one GIF.
    public static let maximumFileBytes = 30 * 1024 * 1024

    private let apiKey: String?
    private let transport: any GIFHTTPTransport
    private let cacheDirectory: URL
    private let pageSize: Int

    public init(
        apiKey: String?,
        transport: any GIFHTTPTransport = URLSessionGIFTransport(),
        cacheDirectory: URL = KlipyGIFProvider.defaultCacheDirectory(),
        pageSize: Int = KlipyAPI.defaultPageSize
    ) {
        self.apiKey = KlipyConfiguration.validKey(apiKey)
        self.transport = transport
        self.cacheDirectory = cacheDirectory
        self.pageSize = pageSize
    }

    /// The provider for the running app: the key from its Resources, or none (then search is off).
    public static func fromBundle(_ bundle: Bundle = .main) -> KlipyGIFProvider {
        KlipyGIFProvider(apiKey: KlipyConfiguration.apiKey(in: bundle))
    }

    public static func defaultCacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("Vitruvian Courier GIFs", isDirectory: true)
    }

    public var isAvailable: Bool { apiKey != nil }

    public var unavailableReason: String {
        String(localized: "Online GIF search isn’t set up in this copy of Vitruvian Courier. You can still send GIFs from your recent history or local files on this Mac.")
    }

    public func trending() async throws -> [GIFCandidate] {
        guard let apiKey, let request = KlipyAPI.trendingRequest(apiKey: apiKey, perPage: pageSize) else {
            throw GIFProviderError.unavailable
        }
        return try await fetchCandidates(request)
    }

    public func search(_ query: String) async throws -> [GIFCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return try await trending() }
        guard let apiKey, let request = KlipyAPI.searchRequest(apiKey: apiKey, query: String(trimmed.prefix(200)), perPage: pageSize)
        else { throw GIFProviderError.unavailable }
        return try await fetchCandidates(request)
    }

    public func fetchFile(for candidate: GIFCandidate, asMP4: Bool) async throws -> URL {
        if asMP4, let loop = candidate.mp4URL {
            return try await download(loop, as: Self.fileName(candidate.id, suffix: "", mimeType: "video/mp4"))
        }
        return try await download(candidate.mediaURL, as: Self.fileName(candidate.id, suffix: "", mimeType: candidate.mimeType))
    }

    public func fetchPreview(for candidate: GIFCandidate) async throws -> URL? {
        guard let preview = candidate.previewURL else { return nil }
        return try await download(preview, as: Self.fileName(candidate.id, suffix: "-preview", mimeType: "image/gif"))
    }

    private func fetchCandidates(_ request: URLRequest) async throws -> [GIFCandidate] {
        let reply = try await transport.send(request)
        guard (200..<300).contains(reply.status) else { throw GIFProviderError.status(reply.status) }
        return try KlipyAPI.candidates(from: reply.body)
    }

    /// A name made only of letters, digits and dashes, so no id can reach outside the cache folder.
    static func fileName(_ id: String, suffix: String, mimeType: String) -> String {
        var safe = ""
        for scalar in id.unicodeScalars where scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) {
            safe.unicodeScalars.append(scalar)
            if safe.count >= 40 { break }
        }
        return "klipy-\(safe.isEmpty ? "gif" : safe)\(suffix).\(mimeType == "video/mp4" ? "mp4" : "gif")"
    }

    private func download(_ address: String, as name: String) async throws -> URL {
        guard apiKey != nil else { throw GIFProviderError.unavailable }
        guard let url = URL(string: address), KlipyAPI.isMediaHost(url) else { throw GIFProviderError.refusedFile }
        let file = cacheDirectory.appendingPathComponent(name, isDirectory: false)
        if let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? Int, size > 0 { return file }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        let reply = try await transport.send(request)
        guard (200..<300).contains(reply.status) else { throw GIFProviderError.status(reply.status) }
        guard !reply.body.isEmpty, reply.body.count <= Self.maximumFileBytes else { throw GIFProviderError.refusedFile }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try reply.body.write(to: file, options: .atomic)
        return file
    }
}
