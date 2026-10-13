// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// The watched repositories, as the `watchlist` preference holds them. The
/// person types them in the tool's detail in Settings, `owner/name` with
/// commas, spaces or lines between; the app's GitHub feature handed them
/// over as a JSON array of the same names, which is read too.
public enum Watchlist {
    public static let defaultRepository = RepoKey(owner: "VitruvianSoftware", name: "vitruvian-core")
    public static let defaultText = defaultRepository.fullName

    /// The repositories named, in order, each once. Empty for empty text.
    public static func parse(_ text: String) -> [RepoKey] {
        var names: [String]
        if let data = text.data(using: .utf8), let array = try? JSONDecoder().decode([String].self, from: data) {
            names = array
        } else {
            names = text.split(whereSeparator: { $0 == "," || $0.isNewline || $0.isWhitespace || $0 == ";" })
                .map(String.init)
        }
        var seen = Set<RepoKey>()
        var result: [RepoKey] = []
        for name in names {
            guard let key = RepoKey(fullName: name), seen.insert(key).inserted else { continue }
            result.append(key)
        }
        return result
    }

    /// `owner/name, owner/name`: what the preference reads best as.
    public static func text(_ repos: [RepoKey]) -> String {
        repos.map(\.fullName).joined(separator: ", ")
    }
}
