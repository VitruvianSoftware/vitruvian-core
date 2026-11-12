// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The forward picker (02 §2.6, "Forward message"): the chats to send a copy to, found by name, at most
/// `ForwardParams.maxRooms` of them. With nothing typed it lists the inbox's chats, newest first (inbox.list); typed,
/// the chats whose name matches (search.query's chats section). An answer older than the newest asked for is
/// dropped. What is typed is never logged.
@MainActor
public final class ForwardPickerModel: ObservableObject {
    /// What is typed.
    @Published public var query = "" {
        didSet { if query != oldValue { find() } }
    }
    /// The chats found, in the engine's order.
    @Published public private(set) var results: [InboxRow] = []
    /// The chats chosen, in the order they were.
    @Published public private(set) var selected: [InboxRow] = []
    /// The search could not be read: the list stays as it was.
    @Published public private(set) var failed = false

    public static var maxChats: Int { ForwardParams.maxRooms }

    private let lookUp: (String) async throws -> [InboxRow]
    private var serial = 0
    /// Tests: answers come back so far, shown or dropped.
    private(set) var answersSeen = 0

    /// - Parameter lookUp: the chats for what is typed ("" for the inbox's); the engine's by default.
    public init(lookUp: @escaping (String) async throws -> [InboxRow]) {
        self.lookUp = lookUp
    }

    /// The engine's chats: the inbox's newest for nothing typed, else search's chats section.
    public convenience init(appModel: AppModel) {
        self.init { [weak appModel] text in
            guard let client = appModel?.client else { throw EngineError.notConnected }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                let page: InboxResult = try await client.call("inbox.list", InboxListParams(limit: 50))
                return page.rooms
            }
            let found: SearchResult = try await client.call(
                "search.query", SearchParams(text: String(String.UnicodeScalarView(trimmed.unicodeScalars.prefix(SearchParams.maxTextScalars))),
                                             sections: [.chats], limit: 50))
            return found.chats ?? []
        }
    }

    /// Reads the chats for what is typed now.
    public func find() {
        serial += 1
        let mine = serial
        let text = query
        Task { [weak self] in
            guard let self else { return }
            defer { self.answersSeen += 1 }
            do {
                let rows = try await self.lookUp(text)
                guard mine == self.serial else { return }
                self.results = rows
                self.failed = false
            } catch {
                guard mine == self.serial else { return }
                self.failed = true
            }
        }
    }

    public func isSelected(_ row: InboxRow) -> Bool {
        selected.contains { $0.roomID == row.roomID }
    }

    /// Chooses a chat, or unchooses it. False when it would be one more than the most a forward takes.
    @discardableResult
    public func toggle(_ row: InboxRow) -> Bool {
        if let index = selected.firstIndex(where: { $0.roomID == row.roomID }) {
            selected.remove(at: index)
            return true
        }
        guard selected.count < Self.maxChats else { return false }
        selected.append(row)
        return true
    }

    /// No more can be chosen.
    public var isFull: Bool { selected.count >= Self.maxChats }
}
