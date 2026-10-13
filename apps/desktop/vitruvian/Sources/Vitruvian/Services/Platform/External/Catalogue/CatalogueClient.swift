// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianToolProtocol

/// One tool the catalog lists, as `catalog/catalog.schema.json` describes
/// it: what its manifest says, copied so the list can be shown without
/// downloading anything, and the one download it is pinned to.
package struct CatalogueEntry: Equatable, Sendable {
    package struct Download: Equatable, Sendable {
        package let url: URL
        /// The zip's SHA-256, in lower-case hex.
        package let sha256: String
        /// The zip's size in bytes.
        package let size: Int
    }

    package struct Command: Equatable, Sendable {
        package let id: String
        package let title: LocalizedText
    }

    package let id: ToolID
    package let name: LocalizedText
    package let publisher: String
    package let summary: LocalizedText
    package let version: String
    package let protocolVersion: String
    package let minimumAppVersion: String
    /// Where the tool's source is.
    package let source: URL
    package let download: Download
    /// The services its manifest names in `uses`, as the manifest spells them.
    package let uses: [String]
    package let commands: [Command]
}

/// The list of tools, read and checked. It is only ever made from bytes whose
/// signature `CatalogueSigning` accepted.
package struct Catalogue: Equatable, Sendable {
    /// The one version of the file this app reads.
    package static let version = 1
    /// The most bytes of the list the app reads.
    package static let mostBytes = 1_048_576

    /// When the list was last changed. The app refuses a list older than one
    /// it has accepted before.
    package let generated: Date
    /// Every entry the app could read, in the list's order.
    package let tools: [CatalogueEntry]

    package init(generated: Date, tools: [CatalogueEntry]) {
        self.generated = generated
        self.tools = tools
    }

    private struct File: Decodable {
        struct Tool: Decodable {
            struct Download: Decodable {
                let url: String
                let sha256: String
                let size: Int
            }

            struct Command: Decodable {
                let id: String
                let title: LocalizedText
            }

            let id: String
            let name: LocalizedText
            let publisher: String
            let summary: LocalizedText
            let version: String
            let `protocol`: String
            let minimumAppVersion: String
            let source: String
            let download: Download
            let uses: [String]
            let commands: [Command]
        }

        let version: Int
        let generated: String
        let tools: [Failable<Tool>]
    }

    /// One entry, or nothing when it cannot be read, so that one entry this
    /// app cannot read does not cost it the others.
    private struct Failable<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    /// Reads a list. Nil when it is not version 1 or not a list at all. An
    /// entry that breaks a rule is left out: a version that is not semver, a
    /// checksum that is not 64 lower-case hex digits, a size that is no size,
    /// an address `permits` refuses, an id that is not an outside tool's, or
    /// an id listed before it.
    package static func read(_ data: Data, permits: (URL) -> Bool) -> Catalogue? {
        guard data.count <= mostBytes, let file = try? JSONDecoder().decode(File.self, from: data),
              file.version == version, let generated = ISO8601DateFormatter().date(from: file.generated) else {
            return nil
        }
        var seen = Set<ToolID>()
        var tools: [CatalogueEntry] = []
        for case let tool? in file.tools.map(\.value) {
            guard let id = ToolID(tool.id), !id.isBundledForm, !seen.contains(id),
                  isVersion(tool.version), isVersion(tool.minimumAppVersion),
                  tool.download.sha256.count == 64,
                  tool.download.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                  (1...ToolLimits.standard.folderBytes).contains(tool.download.size),
                  let url = URL(string: tool.download.url), permits(url),
                  let source = URL(string: tool.source), source.scheme == "https",
                  tool.name.english != nil, tool.summary.english != nil else { continue }
            seen.insert(id)
            tools.append(CatalogueEntry(
                id: id, name: tool.name, publisher: tool.publisher, summary: tool.summary, version: tool.version,
                protocolVersion: tool.protocol, minimumAppVersion: tool.minimumAppVersion, source: source,
                download: .init(url: url, sha256: tool.download.sha256, size: tool.download.size),
                uses: tool.uses, commands: tool.commands.map { .init(id: $0.id, title: $0.title) }))
        }
        return Catalogue(generated: generated, tools: tools)
    }

    /// The entries this app can install: each speaks a protocol the app
    /// speaks, and asks for no newer app than this one. A build whose
    /// version is not semver, a development build, is new enough for all.
    package func installable(appVersion: String) -> [CatalogueEntry] {
        let app = Self.isVersion(appVersion) ? UpdateServiceSupport.SemanticVersion(raw: appVersion) : nil
        return tools.filter { entry in
            guard ProtocolVersion.supported.contains(entry.protocolVersion) else { return false }
            guard let app, let needed = UpdateServiceSupport.SemanticVersion(raw: entry.minimumAppVersion) else {
                return true
            }
            return !(app < needed)
        }
    }

    /// Strictly `1.2.3` or `1.2.3-beta.1`.
    package static func isVersion(_ text: String) -> Bool {
        text.range(of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$"#,
                   options: .regularExpression) != nil
    }

    /// True when `candidate` is a later version than `current`; false when
    /// either is not a version.
    package static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard isVersion(candidate), isVersion(current),
              let new = UpdateServiceSupport.SemanticVersion(raw: candidate),
              let old = UpdateServiceSupport.SemanticVersion(raw: current) else { return false }
        return old < new
    }
}

/// Where the list is, and the key it must be signed with.
package struct CatalogueSource: Equatable, Sendable {
    package let list: URL
    package let signature: URL
    /// The public half of the signing key, in base64.
    package let publicKey: String
    /// True only for a rehearsal: plain http to this Mac itself is allowed.
    package let allowsThisMac: Bool

    package init(list: URL, signature: URL, publicKey: String, allowsThisMac: Bool = false) {
        self.list = list
        self.signature = signature
        self.publicKey = publicKey
        self.allowsThisMac = allowsThisMac
    }

    /// The website's copy, signed in CI.
    package static let production = CatalogueSource(
        list: URL(string: "https://vitruviansoftware.dev/tools/catalog/tools.json")!,
        signature: URL(string: "https://vitruviansoftware.dev/tools/catalog/tools.json.sig")!,
        publicKey: CatalogueSigning.publicKey)

    /// The source the app uses. Only `main.swift`, in a build made with
    /// `--define=vitruvian_sample_tool=true`, ever sets it: the source rule
    /// `only_a_by_hand_build_rehearses_the_catalog` fails for any other line.
    @MainActor package static var inUse = production

    /// A rehearsal of the catalog on this Mac, from two variables:
    /// `VITRUVIAN_CATALOGUE_URL`, the list's address on 127.0.0.1, and
    /// `VITRUVIAN_CATALOGUE_KEY`, the public half of the key
    /// `bazel run //catalog:rehearse` made. Nil unless both are there.
    package static func rehearsal(_ environment: [String: String]) -> CatalogueSource? {
        guard let text = environment["VITRUVIAN_CATALOGUE_URL"], let list = URL(string: text),
              list.scheme == "http", list.host == "127.0.0.1",
              let key = environment["VITRUVIAN_CATALOGUE_KEY"], Data(base64Encoded: key)?.count == 32 else {
            return nil
        }
        return CatalogueSource(list: list, signature: list.appendingPathExtension("sig"), publicKey: key,
                               allowsThisMac: true)
    }

    /// Whether the app may fetch `url`: https anywhere, or plain http to
    /// 127.0.0.1 in a rehearsal. A redirect is asked the same question.
    package func permits(_ url: URL) -> Bool {
        if url.scheme == "https", url.host?.isEmpty == false { return true }
        return allowsThisMac && url.scheme == "http" && url.host == "127.0.0.1"
    }
}

/// One fetch: the address, the ETag the app has for it, and the most bytes
/// it reads.
package struct CatalogueRequest: Equatable, Sendable {
    package let url: URL
    package let etag: String?
    package let limit: Int

    package init(url: URL, etag: String? = nil, limit: Int) {
        self.url = url
        self.etag = etag
        self.limit = limit
    }
}

/// How a fetch ended.
package enum CatalogueResponse: Equatable, Sendable {
    /// All of it arrived. The ETag is the server's, if it sent one.
    case complete(etag: String?)
    /// The server said the copy the app has is current (304).
    case notModified
    /// Stopped by the app: past the limit, or the body said stop.
    case stopped
    /// Anything else: no answer, an error status, a refused redirect.
    case failed
}

/// Fetches for the catalog. Everything it calls back on is off the main
/// thread, in order: `body` for each piece as it arrives, returning false to
/// stop, then `done` once.
package protocol CatalogueFetching: Sendable {
    func fetch(_ request: CatalogueRequest, permits: @escaping @Sendable (URL) -> Bool,
               body: @escaping @Sendable (Data) -> Bool, done: @escaping @Sendable (CatalogueResponse) -> Void)
}

/// The network, through `URLSession`: an ephemeral session with no cookies
/// and no stored credentials, one per fetch. What it writes is written by
/// the app, so macOS sets no quarantine on it.
package struct URLSessionCatalogueFetcher: CatalogueFetching {
    package init() {}

    /// The request as it is sent: no cache but the app's own, and the ETag
    /// when there is one.
    package static func urlRequest(for request: CatalogueRequest) -> URLRequest {
        var made = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if let etag = request.etag { made.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        return made
    }

    package func fetch(_ request: CatalogueRequest, permits: @escaping @Sendable (URL) -> Bool,
                       body: @escaping @Sendable (Data) -> Bool, done: @escaping @Sendable (CatalogueResponse) -> Void) {
        guard permits(request.url) else {
            done(.failed)
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let delegate = Loader(limit: request.limit, permits: permits, body: body, done: done)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: Self.urlRequest(for: request)).resume()
        session.finishTasksAndInvalidate()
    }

    /// Lives until the session is done with it. URLSession calls it on its
    /// own serial queue, one call at a time.
    private final class Loader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let limit: Int
        private let permits: @Sendable (URL) -> Bool
        private let body: @Sendable (Data) -> Bool
        private let done: @Sendable (CatalogueResponse) -> Void
        private var received = 0
        private var redirects = 0
        private var ending: CatalogueResponse?

        init(limit: Int, permits: @escaping @Sendable (URL) -> Bool, body: @escaping @Sendable (Data) -> Bool,
             done: @escaping @Sendable (CatalogueResponse) -> Void) {
            self.limit = limit
            self.permits = permits
            self.body = body
            self.done = done
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            let http = response as? HTTPURLResponse
            switch http?.statusCode {
            case 304?:
                ending = .notModified
                completionHandler(.cancel)
            case let status? where (200..<300).contains(status) && response.expectedContentLength <= Int64(limit):
                ending = .complete(etag: http?.value(forHTTPHeaderField: "ETag"))
                completionHandler(.allow)
            default:
                ending = .failed
                completionHandler(.cancel)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
            received += chunk.count
            guard received <= limit, body(chunk) else {
                ending = .stopped
                dataTask.cancel()
                return
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            redirects += 1
            guard redirects <= 5, let url = request.url, permits(url) else {
                ending = .failed
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            switch ending {
            case .complete? where error != nil: done(.failed)
            case let ending?: done(ending)
            case nil: done(.failed)
            }
        }
    }
}
