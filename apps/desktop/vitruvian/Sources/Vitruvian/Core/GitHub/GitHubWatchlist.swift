// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Encodes and decodes the watchlist preference: a JSON array of `owner/name` strings.
package enum GitHubWatchlist {
    package static let defaultRepository = RepoKey(owner: "VitruvianSoftware", name: "vitruvian-core")
    package static let defaultRepositories = [defaultRepository]
    package static let defaultEncoded = encode(defaultRepositories)

    package static func encode(_ repos: [RepoKey]) -> String {
        let names = repos.map(\.fullName)
        guard let data = try? JSONEncoder().encode(names),
              let string = String(data: data, encoding: .utf8) else {
            return #"["VitruvianSoftware/vitruvian-core"]"#
        }
        return string
    }

    package static func decode(_ raw: String) -> [RepoKey] {
        guard let data = raw.data(using: .utf8),
              let strings = try? JSONDecoder().decode([String].self, from: data) else {
            return defaultRepositories
        }
        if strings.isEmpty { return [] }
        var result: [RepoKey] = []
        var seen = Set<RepoKey>()
        for s in strings {
            guard let key = RepoKey(fullName: s) else { continue }
            if seen.insert(key).inserted {
                result.append(key)
            }
        }
        return result
    }
}
