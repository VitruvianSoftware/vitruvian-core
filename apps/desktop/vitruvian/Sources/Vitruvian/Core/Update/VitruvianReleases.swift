// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Where Vitruvian's own releases are published, and how the update check
/// reads them.
///
/// Releases are tags of the public monorepo, `vitruvian-v3.51.0` and so on.
/// That repository releases many products, so GitHub's "latest release" is
/// usually some other product's. The check lists the tags that start with
/// `vitruvian-v` (one reply, never paged), keeps those that name a version,
/// and asks for the release of the newest.
package enum VitruvianReleases {
    package static let owner = "VitruvianSoftware"
    package static let repository = "vitruvian-core"
    package static let tagPrefix = "vitruvian-v"

    /// Every tag that starts with `tagPrefix`, as GitHub's matching-refs reply.
    package static var tagsURL: URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)/git/matching-refs/tags/\(tagPrefix)")!
    }

    /// The release a tag names.
    package static func releaseURL(tag: String) -> URL {
        URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/tags/\(tag)")!
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

    private struct Ref: Decodable {
        let ref: String
    }

    /// The newest release tag in a matching-refs reply, by version, not by the
    /// reply's order (which is alphabetical, so 3.9.0 comes after 3.51.0).
    /// Pre-releases count only when the person asked for betas. Nil when the
    /// reply is unreadable or names no release.
    package static func newestTag(refsJSON data: Data, includeBetas: Bool) -> String? {
        guard let refs = try? JSONDecoder().decode([Ref].self, from: data) else { return nil }
        var newest: (tag: String, version: UpdateServiceSupport.SemanticVersion)?
        for ref in refs where ref.ref.hasPrefix("refs/tags/") {
            let tag = String(ref.ref.dropFirst("refs/tags/".count))
            guard let raw = version(ofTag: tag),
                  let version = UpdateServiceSupport.SemanticVersion(raw: raw),
                  includeBetas || !version.isPrerelease else { continue }
            if newest.map({ version > $0.version }) ?? true {
                newest = (tag, version)
            }
        }
        return newest?.tag
    }

    /// The disk image the updater installs: the universal build, signed with
    /// the Developer ID and notarized, which runs on Apple silicon and Intel
    /// alike. Named exactly, because a release lists its per-architecture
    /// images too, and GitHub lists the arm64 one first.
    package static func diskImageName(version: String) -> String {
        "Vitruvian-\(version)-universal.dmg"
    }

    /// A release as GitHub's API describes it, the fields the check reads.
    package struct Release: Decodable {
        package let tagName: String
        package let prerelease: Bool?
        package let draft: Bool?
        package let assets: [Asset]
        package let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case prerelease, draft, assets, body
        }

        package struct Asset: Decodable {
            package let name: String
            package let browserDownloadURL: URL
            package let size: Int64?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size
            }

            // Spelled out because a memberwise initializer never leaves its module.
            package init(name: String, browserDownloadURL: URL, size: Int64?) {
                self.name = name
                self.browserDownloadURL = browserDownloadURL
                self.size = size
            }
        }

        // Spelled out because a memberwise initializer never leaves its module.
        package init(tagName: String, prerelease: Bool?, draft: Bool?, assets: [Asset], body: String?) {
            self.tagName = tagName
            self.prerelease = prerelease
            self.draft = draft
            self.assets = assets
            self.body = body
        }
    }

    /// What the update selection weighs from one release: its version (not
    /// its tag, which does not parse as one) and its universal disk image.
    /// Nil for a release that is not Vitruvian's. A release whose universal
    /// image is not attached yet has no download, so it is not offered.
    package static func candidate(from release: Release) -> UpdateServiceSupport.ReleaseCandidate? {
        guard let version = version(ofTag: release.tagName) else { return nil }
        let image = release.assets.first { $0.name == diskImageName(version: version) }
        return UpdateServiceSupport.ReleaseCandidate(
            tagName: version,
            isPrerelease: release.prerelease ?? false,
            isDraft: release.draft ?? false,
            dmgURL: image?.browserDownloadURL,
            dmgExpectedBytes: image?.size,
            body: release.body)
    }

    /// Why a reply cannot be read as an answer.
    package enum Refusal: Equatable {
        /// GitHub allows 60 unsigned requests an hour from one address, and
        /// says so with a 403 or 429 once they are spent.
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
