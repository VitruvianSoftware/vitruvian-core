// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Where Vitruvian's own releases are published, and how the update check
/// reads them.
///
/// Releases are tags of the public monorepo, `vitruvian-v3.51.0` and so on.
/// That repository releases many products, so GitHub's "latest release" is
/// usually some other product's. The check lists the tags that start with
/// `vitruvian-v`, keeps those that name a version, and takes the newest.
///
/// None of it uses api.github.com. Without a token that API allows 60
/// requests an hour per network address, shared by every program on the
/// network, and something on a home network can spend them all (2026-10-15:
/// "Couldn't check: GitHub is limiting requests" while the app had made no
/// request). Instead the check asks:
/// - git itself for the tags (the request `git ls-remote` makes), which is
///   not counted against that limit and answers with every matching tag;
/// - the release's download link, with HEAD, for whether the universal disk
///   image is uploaded yet and how large it is;
/// - the changelog at the tag, as raw text, for the notes, and only when the
///   release will be offered.
///
/// GitHub's releases Atom feed is not used: it lists the newest ten releases
/// of every product in the repository, so a run of other products' releases
/// pushes Vitruvian's out of it.
package enum VitruvianReleases {
    package static let owner = "VitruvianSoftware"
    package static let repository = "vitruvian-core"
    package static let tagPrefix = "vitruvian-v"

    // MARK: - Where

    /// Git's own endpoint for listing a repository's refs.
    package static var tagListURL: URL {
        URL(string: "https://github.com/\(owner)/\(repository).git/git-upload-pack")!
    }

    /// The universal disk image of a release. A fixed address per tag, which
    /// GitHub redirects to the file; not an API call.
    package static func diskImageURL(tag: String, version: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases/download/\(tag)/\(diskImageName(version: version))")!
    }

    /// The app's changelog as it was at the tag. release-please writes the
    /// release's notes from the same section.
    package static func changelogURL(tag: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/\(owner)/\(repository)/\(tag)/apps/desktop/vitruvian/CHANGELOG.md")!
    }

    /// The disk image the updater installs: the universal build, signed with
    /// the Developer ID and notarized, which runs on Apple silicon and Intel
    /// alike. Named exactly, because a release carries per-architecture
    /// images too.
    package static func diskImageName(version: String) -> String {
        "Vitruvian-\(version)-universal.dmg"
    }

    // MARK: - The requests

    /// Git protocol version 2's `ls-refs`, asking only for tags that start
    /// with `tagPrefix`: the request `git ls-remote <repo> 'refs/tags/vitruvian-v*'`
    /// sends. Each line is a pkt-line (four hex digits giving its length,
    /// those four included); `0001` ends the command and `0000` the request.
    package static var tagListRequestBody: Data {
        pktLine("command=ls-refs\n") + Data("0001".utf8)
            + pktLine("ref-prefix refs/tags/\(tagPrefix)\n") + Data("0000".utf8)
    }

    private static func pktLine(_ text: String) -> Data {
        let payload = Data(text.utf8)
        return Data(String(format: "%04x", payload.count + 4).utf8) + payload
    }

    package static func tagListRequest() -> URLRequest {
        var request = request(tagListURL)
        request.httpMethod = "POST"
        request.setValue("version=2", forHTTPHeaderField: "Git-Protocol")
        request.setValue("application/x-git-upload-pack-request", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-git-upload-pack-result", forHTTPHeaderField: "Accept")
        request.httpBody = tagListRequestBody
        return request
    }

    /// HEAD, so nothing is downloaded: the status says whether the image is
    /// there, and Content-Length its size.
    package static func diskImageRequest(tag: String, version: String) -> URLRequest {
        var request = request(diskImageURL(tag: tag, version: version))
        request.httpMethod = "HEAD"
        return request
    }

    package static func changelogRequest(tag: String) -> URLRequest {
        var request = request(changelogURL(tag: tag))
        // The changelog is long and changes only with a release; GitHub lets
        // it be reused for five minutes.
        request.cachePolicy = .useProtocolCachePolicy
        return request
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Vitruvian/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        return request
    }

    // MARK: - Reading the replies

    /// The tag names in an `ls-refs` reply, in the order git sent them. Nil
    /// for a reply that is not one: an error line, a malformed length, or a
    /// reply cut short before its closing `0000`.
    package static func tags(fromRefList data: Data) -> [String]? {
        let bytes = [UInt8](data)
        var index = 0
        var tags: [String] = []
        while index + 4 <= bytes.count {
            let header = bytes[index..<(index + 4)]
            guard header.allSatisfy({ Character(UnicodeScalar($0)).isHexDigit }),
                  let length = Int(String(decoding: header, as: UTF8.self), radix: 16) else { return nil }
            if length == 0 { return tags }
            // `0001` and `0002` are separators with no payload.
            if length < 4 { index += 4; continue }
            guard index + length <= bytes.count else { return nil }
            let line = String(decoding: bytes[(index + 4)..<(index + length)], as: UTF8.self)
                .trimmingCharacters(in: .newlines)
            index += length
            if line.hasPrefix("ERR ") { return nil }
            // "<object id> <ref name>", then attributes this request did not ask for.
            let fields = line.split(separator: " ")
            guard fields.count >= 2 else { return nil }
            let ref = fields[1]
            if ref.hasPrefix("refs/tags/") { tags.append(String(ref.dropFirst("refs/tags/".count))) }
        }
        return nil
    }

    /// The version a tag names, or nil when it is not a Vitruvian release:
    /// another product whose name happens to start the same way
    /// (`vitruvian-viewer-v1.0.0`), the rolling beta (`vitruvian-beta-latest`,
    /// whose version label sorts below the release it was built after), or
    /// anything malformed.
    package static func version(ofTag tag: String) -> String? {
        guard tag.hasPrefix(tagPrefix) else { return nil }
        let version = String(tag.dropFirst(tagPrefix.count))
        guard version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$"#,
                            options: .regularExpression) != nil else { return nil }
        return version
    }

    /// The newest release tag, by version, not by the order listed (which is
    /// alphabetical, so 3.9.0 comes after 3.52.1). Pre-releases count only
    /// when the person asked for betas. Nil when none names a release.
    package static func newestTag(in tags: [String], includeBetas: Bool) -> String? {
        var newest: (tag: String, version: UpdateServiceSupport.SemanticVersion)?
        for tag in tags {
            guard let raw = version(ofTag: tag),
                  let version = UpdateServiceSupport.SemanticVersion(raw: raw),
                  includeBetas || !version.isPrerelease else { continue }
            if newest.map({ version > $0.version }) ?? true {
                newest = (tag, version)
            }
        }
        return newest?.tag
    }

    // MARK: - The check

    /// One HTTP reply, with the parts the check reads.
    package struct Reply: Sendable {
        package let status: Int
        package let body: Data
        package let headers: [String: String]

        package init(status: Int, body: Data = Data(), headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        }

        package func header(_ name: String) -> String? { headers[name.lowercased()] }
    }

    /// Sends one request. The app's is `live`; tests answer from fixtures.
    package typealias Transport = @Sendable (URLRequest) async throws -> Reply

    package static let live: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return Reply(status: http.statusCode, body: data, headers: headers)
    }

    /// The newest Vitruvian release, as the check found it.
    package struct Found: Sendable, Equatable {
        package let tag: String
        package let version: String
        /// Nil when the release is tagged but its universal image is not
        /// uploaded yet (the release pipeline adds it after tagging).
        package let diskImageURL: URL?
        package let diskImageBytes: Int64?

        package init(tag: String, version: String, diskImageURL: URL?, diskImageBytes: Int64?) {
            self.tag = tag
            self.version = version
            self.diskImageURL = diskImageURL
            self.diskImageBytes = diskImageBytes
        }

        /// What the update selection weighs. The tag name is the bare version,
        /// which is what the installer expects inside the image.
        package func candidate(notes: String?) -> UpdateServiceSupport.ReleaseCandidate {
            let parsed = UpdateServiceSupport.SemanticVersion(raw: version)
            return UpdateServiceSupport.ReleaseCandidate(
                tagName: version,
                isPrerelease: parsed?.isPrerelease ?? false,
                isDraft: false,
                dmgURL: diskImageURL,
                dmgExpectedBytes: diskImageBytes,
                body: notes)
        }
    }

    /// Why the check found nothing to offer or compare.
    package enum Failure: Error, Equatable, Sendable {
        /// GitHub refused for sending too many requests.
        case rateLimited
        case status(Int)
        /// No reply at all, in the system's words.
        case unreachable(String)
        /// The tag list names no Vitruvian release, or is not a tag list.
        case noRelease
    }

    /// Lists the release tags, takes the newest, and asks whether its
    /// universal image is uploaded and how large it is. Two requests, neither
    /// to api.github.com.
    package static func findNewest(includeBetas: Bool, transport: Transport) async -> Result<Found, Failure> {
        let list: Reply
        do {
            list = try await transport(tagListRequest())
        } catch {
            return .failure(.unreachable(error.localizedDescription))
        }
        if let refused = refusal(of: list) { return .failure(refused) }
        guard let tags = tags(fromRefList: list.body),
              let tag = newestTag(in: tags, includeBetas: includeBetas),
              let version = version(ofTag: tag) else {
            return .failure(.noRelease)
        }

        let image: Reply
        do {
            image = try await transport(diskImageRequest(tag: tag, version: version))
        } catch {
            return .failure(.unreachable(error.localizedDescription))
        }
        let url: URL?
        let bytes: Int64?
        switch image.status {
        case 200:
            url = diskImageURL(tag: tag, version: version)
            bytes = image.header("Content-Length").flatMap { Int64($0) }.flatMap { $0 > 0 ? $0 : nil }
        case 404:
            // Tagged, but the pipeline has not uploaded the image yet.
            url = nil
            bytes = nil
        default:
            return .failure(refusal(of: image) ?? .status(image.status))
        }
        return .success(Found(tag: tag, version: version, diskImageURL: url, diskImageBytes: bytes))
    }

    /// The release's notes, from the changelog at its tag: markdown, as the
    /// update preview shows it. Nil when it cannot be read, which leaves the
    /// offer without notes rather than failing the check.
    package static func releaseNotes(for found: Found, transport: Transport) async -> String? {
        guard let reply = try? await transport(changelogRequest(tag: found.tag)), reply.status == 200 else {
            return nil
        }
        let notes = ReleaseNotes.rawNotes(for: found.version, changelog: String(decoding: reply.body, as: UTF8.self))
        return notes.isEmpty ? nil : notes
    }

    private static func refusal(of reply: Reply) -> Failure? {
        switch refusal(status: reply.status, rateLimitRemaining: reply.header("x-ratelimit-remaining")) {
        case .none: return nil
        case .rateLimited: return .rateLimited
        case let .status(code): return .status(code)
        }
    }

    /// Why a reply cannot be read as an answer.
    package enum Refusal: Equatable {
        /// Too many requests, said with a 429, or with a 403 and no requests
        /// left.
        case rateLimited
        case status(Int)
    }

    /// Nil for a reply the check can read; otherwise why not.
    package static func refusal(status: Int, rateLimitRemaining: String?) -> Refusal? {
        switch status {
        case 200: return nil
        case 429: return .rateLimited
        case 403 where rateLimitRemaining == "0": return .rateLimited
        default: return .status(status)
        }
    }
}
