// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// The time filter. Inferred (inventory 01 §12): a period counts back from now, by fixed lengths of time.
public enum SearchPeriod: String, CaseIterable, Sendable {
    case anyTime, lastHour, lastWeek, last30Days, lastYear

    /// The earliest time a message may be sent at; nil for any time.
    public func since(now: Date) -> Date? {
        let day: TimeInterval = 86400
        switch self {
        case .anyTime: return nil
        case .lastHour: return now.addingTimeInterval(-3600)
        case .lastWeek: return now.addingTimeInterval(-7 * day)
        case .last30Days: return now.addingTimeInterval(-30 * day)
        case .lastYear: return now.addingTimeInterval(-365 * day)
        }
    }
}

/// The kind filter, as SearchFilters.kinds has it. A link is a text message holding an http(s) URL.
public enum SearchKind: String, CaseIterable, Sendable {
    case text, image, video, audio, file, sticker, link
}

/// The filters the search bar offers. Every one narrows; "Show partial matches" (`partial`) widens, so it isn't
/// counted as a filter.
public struct SearchFilterSet: Equatable, Sendable {
    /// Network names, as hello lists them.
    public var networks: Set<String> = []
    /// "me" or "others": sent or received. nil is both.
    public var sender: String? = nil
    /// "dm" or "group". nil is both.
    public var chatType: String? = nil
    public var kinds: Set<SearchKind> = []
    public var period: SearchPeriod = .anyTime
    /// Inferred (inventory 01 §12): after every full match, the messages that match some but not all of the words.
    public var partial = false

    public init(networks: Set<String> = [], sender: String? = nil, chatType: String? = nil,
                kinds: Set<SearchKind> = [], period: SearchPeriod = .anyTime, partial: Bool = false) {
        self.networks = networks
        self.sender = sender
        self.chatType = chatType
        self.kinds = kinds
        self.period = period
        self.partial = partial
    }

    /// No filter narrows the search. `partial` doesn't count.
    public var isEmpty: Bool {
        networks.isEmpty && sender == nil && chatType == nil && kinds.isEmpty && period == .anyTime
    }

    /// As search.query takes them, in a fixed order; nil when there are none. `period` becomes `since`, counted
    /// back from `now`.
    func wire(now: Date, roomIDs: [String]?) -> SearchFilters? {
        let since = period.since(now: now).map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
        let filters = SearchFilters(
            roomIDs: roomIDs, networks: networks.isEmpty ? nil : networks.sorted(), sender: sender,
            chatType: chatType,
            kinds: kinds.isEmpty ? nil : SearchKind.allCases.filter(kinds.contains).map(\.rawValue),
            since: since, partial: partial ? true : nil)
        return filters == SearchFilters() ? nil : filters
    }
}

/// What activating a result opens.
public enum SearchTarget: Equatable, Sendable {
    case chat(roomID: String)
    /// The chat, at this message (room.events `around`).
    case message(roomID: String, eventID: String)
}

/// One row of the search panel.
public enum SearchItem: Identifiable, Equatable, Sendable {
    case chat(InboxRow)
    case person(PersonHit)
    case message(MessageHit)
    case recentSearch(String)

    /// Unique across the panel: a chat shows once (home leaves Last archived out when it is also Recent).
    public var id: String {
        switch self {
        case let .chat(row): return "chat:" + row.roomID
        case let .person(person): return "person:" + person.userID
        case let .message(hit): return "message:" + hit.eventID
        case let .recentSearch(text): return "search:" + text
        }
    }
}

/// One section of the panel, in display order.
public struct SearchSection: Identifiable, Equatable, Sendable {
    /// Before typing: recent, lastArchived, bookmarks (the five newest), recentSearches. While searching: chats,
    /// inGroups, bookmarks, media, messages (01 §12's order).
    public enum Kind: String, Sendable {
        case recent, lastArchived, recentSearches, chats, inGroups, bookmarks, media, messages
    }

    public let kind: Kind
    public var items: [SearchItem]
    /// "Show more": chats and in groups ask for up to 100; bookmarks, media and messages read the next page.
    public var canShowMore: Bool

    public var id: Kind { kind }

    public init(kind: Kind, items: [SearchItem], canShowMore: Bool = false) {
        self.kind = kind
        self.items = items
        self.canShowMore = canShowMore
    }

    /// Where the "Partial matches" divider goes: the first partial hit (the engine lists every full match first).
    /// nil when there is none.
    public var partialMatchesStart: Int? {
        items.firstIndex {
            if case let .message(hit) = $0 { return hit.partial }
            return false
        }
    }
}

/// What the panel says in place of its rows.
public enum SearchNotice: Equatable, Sendable {
    /// Home over every chat, with nothing recent to list; or a search the engine ran nothing for (every section
    /// null), where nothing was looked for and so nothing "doesn't match".
    case welcome
    /// The same inside one chat (⌘F).
    case welcomeInChat
    /// A search has taken longer than `SearchModel.searchingDelay`.
    case searching
    /// Nothing found for these words (as typed, without the spaces around them).
    case noMatches(String)
    /// Nothing found, and filters narrow the search: Clear Filters may find something.
    case nothingMatchesFilters
    /// Only emoji or punctuation were typed, and those aren't searched.
    case emojiOnly
    /// Too few letters to search messages, and no chat or person matched either.
    case needMoreLetters
    /// The search failed: Try Again.
    case failed
}

/// The ⌘K (and ⌘F) search panel: what is typed and filtered, the sections found, and the row selected.
///
/// **Requests.** A change to `text` searches once typing pauses for `debounce`; a change to `filters` or the scope
/// searches at once. Every change bumps a generation, and an answer for an older one is dropped, so a slow answer
/// for "di" never replaces the one for "din". "Searching…" (`phase == .searching`) shows only once a search has
/// taken `searchingDelay`, so a quick answer never flashes it. A failure is `.failed`, and `retry()` runs it again.
///
/// **Results don't refresh themselves.** The model never listens to the engine's changes: a new message doesn't
/// re-run an open search, so rows never move under the keyboard. The next keystroke or filter change does.
///
/// **Pages.** "Show more" pages from the exact request that found the results shown: the same text, `since` and
/// filters (the engine binds a cursor to them), never "last 7 days" counted again from a later now.
///
/// **Recents.** A search is remembered only once one of its results is opened. Every chat opened anywhere
/// (`AppModel.selectedRoomID`) becomes a recent chat.
@MainActor
public final class SearchModel: ObservableObject {
    public enum Phase: Equatable, Sendable { case closed, home, searching, results, failed }

    /// What is typed. A change searches after `debounce`.
    @Published public var text: String = "" {
        didSet { if text != oldValue { queryChanged(debounced: !isHome && !searchingNow) } }
    }
    /// A change searches at once.
    @Published public var filters = SearchFilterSet() {
        didSet { if filters != oldValue { queryChanged(debounced: false) } }
    }
    /// ⌘F: the chat searched in. nil searches every chat.
    @Published public private(set) var scope: InboxRow?
    @Published public private(set) var phase: Phase = .closed
    /// In display order; a section with nothing in it is left out.
    @Published public private(set) var sections: [SearchSection] = []
    @Published public private(set) var selection: SearchItem.ID?
    /// SearchResult.hint: "", "emoji_only" or "need_more_letters".
    @Published public private(set) var hint: String = ""
    /// false while older messages are still being added to search: results may be missing some.
    @Published public private(set) var complete = true

    public static let debounce: Duration = .milliseconds(150)
    /// "Searching…" only after this.
    public static let searchingDelay: Duration = .milliseconds(300)
    /// The chats (and people) a search shows first; the engine's default.
    public static let chatsShown = 5
    /// What "Show more" asks for in chats and in groups.
    public static let moreChats = 100

    private let appModel: AppModel
    private let recents: RecentSearches
    private let open: @MainActor (SearchTarget) -> Void
    private let now: @Sendable () -> Date
    /// The chat searched in, at once; `scope` is its row, once read.
    private var scopeRoomID: String?
    private var generation = 0
    /// The debounce and the request of the newest change.
    private var running: Task<Void, Never>?
    private var searchingTimer: Task<Void, Never>?
    /// The request that found the results shown. Show more pages from it.
    private var firstPage: SearchParams?
    private var cursors: [SearchSection.Kind: String] = [:]
    private var showingMore: Set<SearchSection.Kind> = []
    private var openedChats: AnyCancellable?
    private let sleep: @Sendable (Duration) async throws -> Void
    /// The generation the rows on screen were found for. Older than `generation` while a newer query is pending.
    private var shownGeneration = 0
    /// The newest generation whose request has been sent.
    private var requestedGeneration = 0
    /// Return was pressed on rows older than the query: the generation whose answer's first row opens on arrival.
    private var pendingOpen: Int?
    /// The next text change searches at once, without the pause (a recent search chosen).
    private var searchingNow = false
    /// The answer shown ran at least one section (one of them isn't null). An answer that ran none found nothing
    /// because nothing was looked for, and doesn't say "Nothing matches these filters" (Ruling 34).
    private var engineRan = false

    /// - Parameters:
    ///   - open: opens a chat, or a chat at a message.
    ///   - now: the time a period counts back from.
    ///   - sleep: the pause after typing and before "Searching…"; tests give one on a clock they move.
    public init(appModel: AppModel, recents: RecentSearches, open: @escaping @MainActor (SearchTarget) -> Void,
                now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.appModel = appModel
        self.sleep = sleep
        self.recents = recents
        self.open = open
        self.now = now
        openedChats = appModel.$selectedRoomID.compactMap { $0 }.removeDuplicates()
            .sink { [weak appModel, recents] id in
                for roomID in appModel?.scopeRoomIDs(for: id) ?? [id] where !roomID.hasPrefix("merge:") {
                    recents.addChat(roomID)
                }
            }
    }

    // MARK: - Opening and closing

    /// ⌘K with no chat; ⌘F with the open chat, to search in it (nil is like ⌘K).
    public func show(in roomID: String? = nil) {
        if phase == .closed { phase = .home }
        scopeRoomID = roomID
        scope = nil
        if let roomID { readScope(roomID) }
        queryChanged(debounced: false)
    }

    /// ⌘K: opens the panel over every chat, or closes it when it is open and `visible` (its window is in front).
    /// Over a window that is closed or behind another, a panel left open is never closed unseen: it opens, and
    /// the caller brings the window forward.
    public func toggle(visible: Bool) {
        if phase != .closed, visible {
            close()
        } else {
            show()
        }
    }

    /// Closes the panel and forgets what was typed, filtered and found.
    public func close() {
        phase = .closed // first, so the resets below search nothing
        generation += 1
        running?.cancel()
        running = nil
        searchingTimer?.cancel()
        text = ""
        filters = SearchFilterSet()
        scopeRoomID = nil
        scope = nil
        sections = []
        selection = nil
        hint = ""
        engineRan = false
        complete = true
        firstPage = nil
        cursors = [:]
        pendingOpen = nil
    }

    /// Esc: clears the filters, then the text, then the chat searched in, then closes. True once closed.
    public func escape() -> Bool {
        if !filters.isEmpty {
            clearFilters()
            return false
        }
        if !text.isEmpty {
            text = ""
            return false
        }
        if scopeRoomID != nil {
            removeScope()
            return false
        }
        close()
        return true
    }

    /// ⌫ on empty text: searches every chat again.
    public func removeScope() {
        guard scopeRoomID != nil else { return }
        scopeRoomID = nil
        scope = nil
        queryChanged(debounced: false)
    }

    /// "Clear Filters": every filter off. "Show partial matches" isn't a filter, and stays as it is.
    public func clearFilters() {
        filters = SearchFilterSet(partial: filters.partial)
    }

    /// What the panel shows in place of its rows; nil when it shows rows (or is closed).
    public var notice: SearchNotice? {
        switch phase {
        case .closed: return nil
        case .failed: return .failed
        case .searching: return .searching
        case .home: return sections.isEmpty ? welcome : nil
        case .results:
            guard sections.isEmpty else { return nil }
            if hint == SearchHint.emojiOnly.rawValue { return .emojiOnly }
            if hint == SearchHint.needMoreLetters.rawValue { return .needMoreLetters }
            guard engineRan else { return welcome }
            if !filters.isEmpty { return .nothingMatchesFilters }
            return .noMatches(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private var welcome: SearchNotice { scopeRoomID == nil ? .welcome : .welcomeInChat }

    /// Too few letters were typed to search messages, and Chats has rows: the line under them says so.
    public var needsMoreLettersUnderChats: Bool {
        phase == .results && hint == SearchHint.needMoreLetters.rawValue && !sections.isEmpty
    }

    /// Try Again, after a failure.
    public func retry() {
        guard phase == .failed else { return }
        queryChanged(debounced: false)
    }

    /// "Clear Recent Searches".
    public func clearRecentSearches() {
        recents.clearSearches()
        sections.removeAll { $0.kind == .recentSearches }
        if let selection, !allItems.contains(where: { $0.id == selection }) { self.selection = allItems.first?.id }
    }

    // MARK: - Keys

    /// A row clicked, or hovered with the keys.
    public func select(_ id: SearchItem.ID?) {
        selection = id
    }

    /// ↑ ↓ ⌃P ⌃N: the row `delta` rows away, across sections, stopping at either end.
    public func moveSelection(_ delta: Int) {
        let ids = allItems.map(\.id)
        guard !ids.isEmpty else { return }
        guard let selection, let index = ids.firstIndex(of: selection) else {
            self.selection = ids.first
            return
        }
        self.selection = ids[max(0, min(ids.count - 1, index + delta))]
    }

    /// Tab, ⇧Tab: the first row of the next or previous section, stopping at either end.
    public func moveSection(_ delta: Int) {
        guard !sections.isEmpty else { return }
        let current = sections.firstIndex { $0.items.contains { $0.id == selection } }
        let target = current.map { max(0, min(sections.count - 1, $0 + delta)) } ?? 0
        selection = sections[target].items.first?.id
    }

    /// Return: opens the selected row and closes the panel. A recent search is searched again, at once, instead.
    ///
    /// Rows found for an older query (Return inside the pause after typing, or before the answer) are never
    /// opened: the search runs now, and the first row of its answer opens when it lands. An empty answer or a
    /// failure opens nothing and keeps nothing; a keystroke before the answer cancels the open.
    public func activate() {
        guard phase != .closed else { return }
        if shownGeneration != generation {
            if requestedGeneration == generation, phase == .failed { return } // this query failed: Try Again
            pendingOpen = generation
            if requestedGeneration != generation {
                // Skip the rest of the pause.
                let generation = generation
                running?.cancel()
                running = Task { [weak self] in await self?.run(generation) }
            }
            return
        }
        guard let selection, let item = allItems.first(where: { $0.id == selection }) else { return }
        let target: SearchTarget
        switch item {
        case let .recentSearch(words):
            searchingNow = true
            text = words
            searchingNow = false
            return
        case let .chat(row):
            target = .chat(roomID: row.roomID)
        case let .person(person):
            // Their most recent shared group. Starting a direct chat with them comes with ⌘N (part 4.5).
            target = .chat(roomID: person.roomID)
        case let .message(hit):
            target = .message(roomID: hit.roomID, eventID: hit.eventID)
        }
        // Only now, when a result was opened, is what was typed worth keeping.
        recents.addSearch(text)
        close()
        open(target)
    }

    // MARK: - Show more

    /// "Show more" under a section: up to 100 chats or people, or the next page of media or messages.
    public func showMore(_ kind: SearchSection.Kind) async {
        guard phase == .results, let base = firstPage, let client = appModel.client,
              sections.first(where: { $0.kind == kind })?.canShowMore == true,
              !showingMore.contains(kind) else { return }
        var params = base
        switch kind {
        case .chats, .inGroups:
            params.sections = [kind == .chats ? .chats : .inGroups]
            params.limit = Self.moreChats
        case .bookmarks, .media, .messages:
            guard let cursor = cursors[kind] else { return }
            params.sections = [kind == .bookmarks ? .bookmarks : kind == .media ? .media : .messages]
            params.cursor = cursor
        case .recent, .lastArchived, .recentSearches:
            return
        }
        let generation = generation
        showingMore.insert(kind)
        defer { showingMore.remove(kind) }
        // A failure leaves the section as it was, with Show more to try again.
        guard let result: SearchResult = try? await client.call("search.query", params),
              generation == self.generation,
              let index = sections.firstIndex(where: { $0.kind == kind }) else { return }
        switch kind {
        case .chats:
            if let chats = result.chats, !chats.isEmpty {
                sections[index].items = Self.dedupeMergedChats(chats).map(SearchItem.chat)
            }
            sections[index].canShowMore = false
        case .inGroups:
            if let people = result.inGroups, !people.isEmpty { sections[index].items = people.map(SearchItem.person) }
            sections[index].canShowMore = false
        case .bookmarks, .media, .messages:
            let page = kind == .bookmarks ? result.bookmarks : kind == .media ? result.media : result.messages
            // A row's id is unique in the panel: a message already listed (under Bookmarks, say) isn't added again.
            let shown = Set(allItems.map(\.id))
            let added = (page?.hits ?? []).map(SearchItem.message).filter { !shown.contains($0.id) }
            sections[index].items += added
            sections[index].canShowMore = page?.nextCursor != nil
            cursors[kind] = page?.nextCursor
        case .recent, .lastArchived, .recentSearches:
            break
        }
    }

    // MARK: - Searching

    private var allItems: [SearchItem] { sections.flatMap(\.items) }

    /// Empty text and no filters: the panel shows home, not results.
    private var isHome: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filters.isEmpty
    }

    private func queryChanged(debounced: Bool) {
        guard phase != .closed else { return }
        generation += 1
        pendingOpen = nil // a keystroke after Return cancels the open
        let generation = generation
        let sleep = sleep
        running?.cancel()
        searchingTimer?.cancel()
        running = Task { [weak self] in
            if debounced {
                do { try await sleep(Self.debounce) } catch { return }
            }
            await self?.run(generation)
        }
    }

    private func run(_ generation: Int) async {
        guard generation == self.generation, phase != .closed, requestedGeneration != generation else { return }
        requestedGeneration = generation
        if isHome, scopeRoomID != nil {
            // Inside one chat, home is the recent searches alone: recent and archived chats aren't in it.
            showHome(recent: [], lastArchived: nil, bookmarks: [], complete: complete, of: generation)
            return
        }
        guard let client = appModel.client else {
            fail()
            return
        }
        if isHome {
            await runHome(client, generation)
        } else {
            await runSearch(client, generation)
        }
    }

    private func runHome(_ client: EngineClient, _ generation: Int) async {
        let openRoomID = appModel.openRoomIDs.first { !$0.hasPrefix("merge:") }
        // The open chat is left out of Recent here and, through open_room_id, of Last archived. Inferred (inventory
        // 01 §12): Last archived also leaves out hidden chats (the engine does).
        let ids = recents.chats.filter { !$0.hasPrefix("merge:") && !appModel.isOpen(roomID: $0) }
        do {
            async let home: SearchResult = client.call("search.query", SearchParams(text: "", openRoomID: openRoomID))
            var found: [InboxRow] = []
            if !ids.isEmpty {
                let page: InboxResult = try await client.call("inbox.list", InboxListParams(roomIDs: ids))
                found = page.rooms
            }
            let result = try await home
            guard generation == self.generation, phase != .closed else { return }
            // In the order they were opened, not the engine's.
            let byID = Dictionary(found.map { ($0.roomID, $0) }, uniquingKeysWith: { first, _ in first })
            showHome(recent: ids.compactMap { byID[$0] }, lastArchived: result.lastArchived,
                     bookmarks: result.bookmarks?.hits ?? [], complete: result.complete, of: generation)
        } catch {
            guard generation == self.generation, phase != .closed else { return }
            fail()
        }
    }

    private func showHome(recent: [InboxRow], lastArchived: InboxRow?, bookmarks: [MessageHit], complete: Bool,
                          of generation: Int) {
        var built: [SearchSection] = []
        if !recent.isEmpty { built.append(SearchSection(kind: .recent, items: recent.map(SearchItem.chat))) }
        if let lastArchived, !appModel.isOpen(roomID: lastArchived.roomID),
           !recent.contains(where: { $0.roomID == lastArchived.roomID }) {
            built.append(SearchSection(kind: .lastArchived, items: [.chat(lastArchived)]))
        }
        // Inferred (inventory 01 §12): before typing, the five newest bookmarks follow the chats, as Bookmarks
        // follows the chat sections in results. The engine gives them, newest bookmark first, with no next page.
        if !bookmarks.isEmpty { built.append(SearchSection(kind: .bookmarks, items: bookmarks.map(SearchItem.message))) }
        if !recents.searches.isEmpty {
            built.append(SearchSection(kind: .recentSearches, items: recents.searches.map(SearchItem.recentSearch)))
        }
        searchingTimer?.cancel()
        firstPage = nil
        cursors = [:]
        sections = built
        hint = ""
        engineRan = false
        self.complete = complete
        selection = built.first?.items.first?.id
        phase = .home
        shown(generation)
    }

    private func runSearch(_ client: EngineClient, _ generation: Int) async {
        let params = currentParams()
        startSearchingTimer(generation)
        do {
            let result: SearchResult = try await client.call("search.query", params)
            guard generation == self.generation, phase != .closed else { return }
            showResults(result, of: params, generation: generation)
        } catch {
            guard generation == self.generation, phase != .closed else { return }
            fail()
        }
    }

    /// The member room IDs when `roomID` is a merged chat (`merge:...`), or `[roomID]` for a single room.
    private func scopeRoomIDs(for roomID: String) -> [String] {
        appModel.scopeRoomIDs(for: roomID).filter { !$0.hasPrefix("merge:") }
    }

    /// The request for what is shown now: the text (at most the engine's 500 Unicode scalars, counted as it counts
    /// them, not in Characters), the filters with the period counted back from now, and the chat searched in.
    private func currentParams() -> SearchParams {
        var words = text
        if words.unicodeScalars.count > SearchParams.maxTextScalars {
            words = String(String.UnicodeScalarView(words.unicodeScalars.prefix(SearchParams.maxTextScalars)))
        }
        return SearchParams(text: words, filters: filters.wire(now: now(), roomIDs: scopeRoomID.map { scopeRoomIDs(for: $0) }))
    }

    private func showResults(_ result: SearchResult, of params: SearchParams, generation: Int) {
        // Inside one chat there are no Chats or In groups (the engine leaves them null too).
        let everyChat = params.filters?.roomIDs == nil
        var built: [SearchSection] = []
        var cursors: [SearchSection.Kind: String] = [:]
        if everyChat, let chats = result.chats, !chats.isEmpty {
            let deduped = Self.dedupeMergedChats(chats)
            built.append(SearchSection(kind: .chats, items: deduped.map(SearchItem.chat),
                                       canShowMore: chats.count >= Self.chatsShown))
        }
        // Inferred (inventory 01 §12): In groups lists people I have no direct chat with (the engine decides).
        if everyChat, let people = result.inGroups, !people.isEmpty {
            built.append(SearchSection(kind: .inGroups, items: people.map(SearchItem.person),
                                       canShowMore: people.count >= Self.chatsShown))
        }
        // A bookmarked message that also matches shows once, under Bookmarks: a row's id is unique in the panel.
        var listed = Set<SearchItem.ID>()
        for (kind, page) in [(SearchSection.Kind.bookmarks, result.bookmarks), (.media, result.media),
                             (.messages, result.messages)] {
            guard let page else { continue }
            let items = page.hits.map(SearchItem.message).filter { listed.insert($0.id).inserted }
            guard !items.isEmpty else { continue }
            built.append(SearchSection(kind: kind, items: items, canShowMore: page.nextCursor != nil))
            cursors[kind] = page.nextCursor
        }
        searchingTimer?.cancel()
        firstPage = params
        self.cursors = cursors
        sections = built
        hint = result.hint.rawValue
        engineRan = result.chats != nil || result.inGroups != nil || result.bookmarks != nil || result.media != nil
            || result.messages != nil
        complete = result.complete
        selection = built.first?.items.first?.id
        phase = .results
        shown(generation)
    }

    /// The rows on screen are now `generation`'s. If Return was pressed for it, its first row opens (a recent
    /// search, on home, isn't a result: nothing opens).
    private func shown(_ generation: Int) {
        shownGeneration = generation
        guard pendingOpen == generation else { return }
        pendingOpen = nil
        guard let first = allItems.first else { return }
        if case .recentSearch = first { return }
        selection = first.id
        activate()
    }

    private func fail() {
        pendingOpen = nil
        searchingTimer?.cancel()
        phase = .failed
    }

    private func startSearchingTimer(_ generation: Int) {
        searchingTimer?.cancel()
        let sleep = sleep
        searchingTimer = Task { [weak self] in
            do { try await sleep(Self.searchingDelay) } catch { return }
            guard !Task.isCancelled, let self, generation == self.generation, self.phase != .closed else { return }
            self.phase = .searching
        }
    }

    /// Reads the row of the chat searched in, for its name. A chat the engine doesn't have widens the search.
    private func readScope(_ roomID: String) {
        guard let client = appModel.client else { return }
        let ids = scopeRoomIDs(for: roomID)
        guard !ids.isEmpty else {
            removeScope()
            return
        }
        let merge = appModel.mergedChats[roomID]
        Task { [weak self] in
            let result: InboxResult? = try? await client.call("inbox.list", InboxListParams(roomIDs: ids))
            guard let self, let result, self.scopeRoomID == roomID, self.phase != .closed else { return }
            if var row = result.rooms.first {
                if let merge {
                    row.mergeID = merge.mergeID
                    if !merge.name.isEmpty { row.name = merge.name }
                }
                self.scope = row
            } else {
                self.removeScope()
            }
        }
    }

    /// Deduplicates merged chat rows by `merge_id`, keeping the first row without summing unread counts.
    static func dedupeMergedChats(_ rows: [InboxRow]) -> [InboxRow] {
        var seen = Set<String>()
        var out: [InboxRow] = []
        for row in rows {
            if !row.mergeID.isEmpty {
                guard seen.insert(row.mergeID).inserted else { continue }
            }
            out.append(row)
        }
        return out
    }
}
