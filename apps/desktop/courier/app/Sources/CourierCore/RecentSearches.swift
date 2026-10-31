// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What ⌘K shows before anything is typed: the searches that led somewhere, and the chats opened most recently.
///
/// Kept in the app's UserDefaults (as InboxPreferences is), never in the engine: the engine doesn't keep or log
/// search text. A search is added only once one of its results is opened, so half-typed words aren't kept.
public final class RecentSearches {
    public static let searchesKey = "courier.search.recentSearches"
    public static let chatsKey = "courier.search.recentChats"
    /// The most searches kept.
    public static let maxSearches = 10
    /// The most chats kept.
    public static let maxChats = 8

    /// Newest first.
    public private(set) var searches: [String]
    /// Room IDs, the chat opened most recently first. Inferred (inventory 01 §12): "recent" chats are the chats
    /// opened most recently.
    public private(set) var chats: [String]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        searches = defaults.stringArray(forKey: Self.searchesKey) ?? []
        chats = defaults.stringArray(forKey: Self.chatsKey) ?? []
    }

    /// Puts `text` first, without the spaces around it. The same words in another case are the same search (the
    /// index folds case), so the older spelling goes.
    public func addSearch(_ text: String) {
        guard AppLockGate.isCurrentActionAllowedForSettings else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let folded = text.lowercased()
        searches.removeAll { $0.lowercased() == folded }
        searches.insert(text, at: 0)
        searches = Array(searches.prefix(Self.maxSearches))
        defaults.set(searches, forKey: Self.searchesKey)
    }

    public func addChat(_ roomID: String) {
        guard AppLockGate.isCurrentActionAllowedForSettings else { return }
        chats.removeAll { $0 == roomID }
        chats.insert(roomID, at: 0)
        chats = Array(chats.prefix(Self.maxChats))
        defaults.set(chats, forKey: Self.chatsKey)
    }

    /// "Clear Recent Searches". The recent chats stay.
    public func clearSearches() {
        guard AppLockGate.isCurrentActionAllowedForSettings else { return }
        searches = []
        defaults.removeObject(forKey: Self.searchesKey)
    }
}
