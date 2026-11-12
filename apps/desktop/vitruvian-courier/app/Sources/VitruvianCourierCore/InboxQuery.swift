// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// An inbox.list filter. Filters of one group are or'ed and the groups and'ed (protocol.json's InboxListParams).
/// There is no "all" filter: All is no filter at all.
public enum InboxFilter: String, CaseIterable, Codable, Sendable {
    case unread, dms, groups, drafts, unanswered, noReply = "no_reply",
         unknown, muted, hidden, archived, lowPriority = "low_priority", requests, reminders, sendLater = "send_later"

    /// protocol.json's order. Filters are sent in it, so a query always reads the same on the wire.
    public static let wireOrder: [InboxFilter] = [
        .unread, .drafts, .unanswered, .noReply, .dms, .groups, .unknown, .muted, .archived, .lowPriority, .hidden,
        .requests, .reminders, .sendLater,
    ]

    /// Cycle Filters (⌥Tab), one at a time; after the last comes All.
    public static let cycle: [InboxFilter] = [.unread, .drafts, .unanswered, .dms, .groups]
}

/// An inbox.list sort. Pinned chats come first in every one.
public enum InboxSort: String, CaseIterable, Codable, Sendable {
    case newest, oldest,
         leastTimeRemaining = "least_time_remaining", mostTimeRemaining = "most_time_remaining"
}

/// What the inbox lists: a space, narrowed by filters, in a sort.
public struct InboxQuery: Equatable, Sendable {
    /// A space_id from spaces.list.
    public var space = "inbox"
    /// Empty is All.
    public var filters: Set<InboxFilter> = []
    public var sort = InboxSort.newest

    public init(space: String = "inbox", filters: Set<InboxFilter> = [], sort: InboxSort = .newest) {
        self.space = space
        self.filters = filters
        self.sort = sort
    }

    /// The inbox.list params for a page of this query. What is the default is left out: the inbox space, All
    /// (never an "all" filter) and newest.
    func params(cursor: String?, limit: Int) -> InboxListParams {
        InboxListParams(
            space: space == "inbox" ? nil : space,
            filters: filters.isEmpty ? nil : InboxFilter.wireOrder.filter(filters.contains),
            sort: sort == .newest ? nil : sort,
            cursor: cursor,
            limit: limit)
    }
}

/// A short message under the inbox about what was just done, with Undo when it can be undone.
public struct Toast: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let message: String
    public let canUndo: Bool

    public init(id: UUID = UUID(), message: String, canUndo: Bool) {
        self.id = id
        self.message = message
        self.canUndo = canUndo
    }
}
