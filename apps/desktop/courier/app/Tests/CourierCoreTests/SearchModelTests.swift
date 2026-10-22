// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The ⌘K search model against a stand-in engine. What search.query answers comes from a `SearchScript` the test
/// edits; recent searches live in a UserDefaults suite of the test's own; `now` is a clock the test moves.
@MainActor
final class SearchModelTests: XCTestCase {
    private var harnesses: [SearchHarness] = []

    override func tearDown() async throws {
        for harness in harnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        harnesses = []
    }

    private func start(rooms: [[String: Any]] = []) async throws -> SearchHarness {
        let harness = try await startSearch(rooms: rooms)
        harnesses.append(harness)
        return harness
    }

    // MARK: - Requests

    func testTypingSearchesOnceAfterTheDebounce() async throws {
        let h = try await start()
        try await h.showHome()
        let before = h.searches.count

        h.search.text = "d"
        h.search.text = "di"
        h.search.text = "din"
        try await waitUntil { h.time.pendingSleeps.contains(0.15) }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(h.time.pendingSleeps, [0.15], "one pause, for din")
        h.time.advance(0.1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(h.searches.count, before, "nothing is sent until typing pauses for 150 ms")

        h.time.advance(0.05)
        try await waitUntil { h.searches.count == before + 1 }
        try await waitUntil { h.search.phase == .results }
        XCTAssertEqual(h.searches.dropFirst(before).map { $0["text"] as? String }, ["din"], "one request, for din")
    }

    func testOlderAnswersAreDropped() async throws {
        let h = try await start()
        try await h.showHome()
        h.script.hold = true
        try await h.type("di")
        try await waitUntil { h.searches.last?["text"] as? String == "di" }
        try await h.type("din")
        try await waitUntil { h.searches.last?["text"] as? String == "din" }
        let held = h.server.received.filter { $0["method"] as? String == "search.query" }.suffix(2)
            .compactMap { $0["id"] as? Int }
        XCTAssertEqual(held.count, 2)

        h.server.reply(to: held[1], with: searchResult(chats: [room("!din", ts: 2, name: "Dinner")]))
        try await waitUntil { h.search.phase == .results }
        XCTAssertEqual(h.chatIDs(.chats), ["!din"])

        h.server.reply(to: held[0], with: searchResult(chats: [room("!di", ts: 1, name: "Dig")]))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(h.chatIDs(.chats), ["!din"], "the answer for di came too late, and changes nothing")
        XCTAssertEqual(h.search.text, "din")
    }

    func testSectionsInOrderAndEmptyOnesLeftOut() async throws {
        let h = try await start()
        h.script.results["picnic"] = searchResult(
            chats: [room("!c", ts: 3, name: "Picnic planning")], inGroups: [],
            media: [messageHit("$m1", room: "!c", kind: "image")],
            messages: [messageHit("$t1", room: "!c"), messageHit("$t2", room: "!d")],
            complete: false)
        h.script.results["p"] = searchResult(
            chats: [], inGroups: [personHit("@one", room: "!g")], media: nil, messages: nil,
            hint: "need_more_letters")
        try await h.showHome()

        try await h.type("picnic")
        try await waitUntil { h.search.phase == .results }
        XCTAssertEqual(h.search.sections.map(\.kind), [.chats, .media, .messages], "In groups found nobody")
        XCTAssertEqual(h.search.sections.last?.items.map(\.id), ["message:$t1", "message:$t2"])
        XCTAssertFalse(h.search.complete, "older messages are still being added")
        XCTAssertEqual(h.search.hint, "")
        XCTAssertEqual(h.search.selection, "chat:!c", "the first result is selected, for Return")

        try await h.type("p")
        try await waitUntil { h.search.sections.map(\.kind) == [.inGroups] }
        XCTAssertEqual(h.search.hint, "need_more_letters")
        XCTAssertTrue(h.search.complete)
        XCTAssertEqual(h.search.sections.first?.items, [.person(PersonHit(
            userID: "@one", name: "Person @one", network: "whatsapp", roomID: "!g", roomName: "Group !g", groups: 2))])
    }

    func testHomeShowsRecentLastArchivedAndRecentSearches() async throws {
        let h = try await start(rooms: [room("!a", ts: 1), room("!b", ts: 2), room("!open", ts: 3)])
        h.script.lastArchived = room("!z", ts: 0, archived: true)
        h.recents.addSearch("lunch")
        h.recents.addSearch("picnic")
        // Opening chats is what makes them recent.
        h.app.selectedRoomID = "!a"
        h.app.selectedRoomID = "!b"
        h.app.selectedRoomID = "!open"
        XCTAssertEqual(h.recents.chats, ["!open", "!b", "!a"])

        h.search.show()
        XCTAssertEqual(h.search.phase, .home)
        try await waitUntil { h.search.sections.count == 3 }
        XCTAssertEqual(h.search.sections.map(\.kind), [.recent, .lastArchived, .recentSearches])
        XCTAssertEqual(h.chatIDs(.recent), ["!b", "!a"], "the open chat isn't in Recent")
        XCTAssertEqual(h.chatIDs(.lastArchived), ["!z"])
        XCTAssertEqual(h.search.sections.last?.items, [.recentSearch("picnic"), .recentSearch("lunch")])
        XCTAssertEqual(dicts(h.server.receivedParams("inbox.list")), dicts([["room_ids": ["!b", "!a"]]]))
        XCTAssertEqual(dicts(h.searches), dicts([["text": "", "open_room_id": "!open"]]),
                       "last archived leaves out the open chat")

        // Activating a recent search searches it.
        h.search.select("search:picnic")
        h.search.activate()
        XCTAssertEqual(h.search.text, "picnic")
        XCTAssertNotEqual(h.search.phase, .closed)
        try await waitUntil { h.searches.last?["text"] as? String == "picnic" }
        XCTAssertEqual(h.time.pendingSleeps.filter { $0 == 0.15 }, [], "a recent search is searched at once, no pause")

        // Clear Recent Searches empties the section at once.
        h.search.text = ""
        try await waitUntil { h.search.sections.map(\.kind) == [.recent, .lastArchived, .recentSearches] }
        h.search.clearRecentSearches()
        XCTAssertEqual(h.recents.searches, [])
        XCTAssertEqual(h.search.sections.map(\.kind), [.recent, .lastArchived])
    }

    func testFiltersAndPeriodsGoOnTheWire() async throws {
        let h = try await start()
        try await h.showHome()
        try await h.type("picnic")
        try await waitUntil { h.searches.last?["text"] as? String == "picnic" }
        XCTAssertEqual(dicts([h.searches.last!]), dicts([["text": "picnic"]]), "no filters, no filters key")

        var filters = SearchFilterSet()
        filters.period = .lastWeek
        filters.kinds = [.link, .image]
        filters.sender = "me"
        filters.networks = ["whatsapp", "signal"]
        filters.chatType = "group"
        filters.partial = true
        let count = h.searches.count
        h.search.filters = filters
        try await waitUntil { h.searches.count == count + 1 }
        let sent = try XCTUnwrap(h.searches.last)
        XCTAssertEqual(sent["text"] as? String, "picnic")
        XCTAssertEqual(sent["filters"] as? NSDictionary, [
            "since": h.nowMillis - 7 * 86_400_000, "kinds": ["image", "link"], "sender": "me",
            "networks": ["signal", "whatsapp"], "chat_type": "group", "partial": true,
        ] as NSDictionary)

        // Only "Show partial matches" isn't a filter: empty text with it still shows home.
        XCTAssertTrue(SearchFilterSet(partial: true).isEmpty)
        XCTAssertFalse(SearchFilterSet(kinds: [.file]).isEmpty)
    }

    func testPeriodsCountBackFromNow() {
        let now = Date(timeIntervalSince1970: 1_760_600_000)
        XCTAssertNil(SearchPeriod.anyTime.since(now: now))
        XCTAssertEqual(SearchPeriod.lastHour.since(now: now), now.addingTimeInterval(-3600))
        XCTAssertEqual(SearchPeriod.lastWeek.since(now: now), now.addingTimeInterval(-7 * 86400))
        XCTAssertEqual(SearchPeriod.last30Days.since(now: now), now.addingTimeInterval(-30 * 86400))
        XCTAssertEqual(SearchPeriod.lastYear.since(now: now), now.addingTimeInterval(-365 * 86400))
    }

    func testScopeSearchesOnlyThatChat() async throws {
        let h = try await start(rooms: [room("!a", ts: 1, name: "Picnic planning")])
        h.script.results["pic"] = searchResult(
            chats: [room("!a", ts: 1)], inGroups: [personHit("@one", room: "!g")],
            messages: [messageHit("$t1", room: "!a")])
        h.search.show(in: "!a")
        try await waitUntil { h.search.scope?.roomID == "!a" }
        XCTAssertEqual(h.search.phase, .home)

        try await h.type("pic")
        try await waitUntil { h.search.phase == .results }
        XCTAssertEqual(h.searches.last?["filters"] as? NSDictionary, ["room_ids": ["!a"]] as NSDictionary)
        XCTAssertEqual(h.search.sections.map(\.kind), [.messages], "no Chats or In groups inside a chat")

        let count = h.searches.count
        h.search.removeScope()
        XCTAssertNil(h.search.scope)
        try await waitUntil { h.searches.count == count + 1 && h.search.sections.count == 3 }
        XCTAssertNil(h.searches.last?["filters"], "every chat again")
        XCTAssertEqual(h.search.sections.map(\.kind), [.chats, .inGroups, .messages])
    }

    // MARK: - Keys

    func testSelectionMovesAcrossSectionsAndTabJumps() async throws {
        let h = try await start()
        h.script.results["pic"] = searchResult(
            chats: [room("!c1", ts: 2), room("!c2", ts: 1)],
            messages: [messageHit("$m1", room: "!c1"), messageHit("$m2", room: "!c1"), messageHit("$m3", room: "!c2")])
        try await h.showHome()
        try await h.type("pic")
        try await waitUntil { h.search.phase == .results }

        XCTAssertEqual(h.search.selection, "chat:!c1")
        h.search.moveSelection(1)
        XCTAssertEqual(h.search.selection, "chat:!c2")
        h.search.moveSelection(1)
        XCTAssertEqual(h.search.selection, "message:$m1", "down from a section's last row goes to the next section")
        h.search.moveSelection(5)
        XCTAssertEqual(h.search.selection, "message:$m3", "no wrap")
        h.search.moveSelection(-1)
        XCTAssertEqual(h.search.selection, "message:$m2")
        h.search.moveSection(-1)
        XCTAssertEqual(h.search.selection, "chat:!c1", "⇧Tab: the previous section's first row")
        h.search.moveSection(1)
        XCTAssertEqual(h.search.selection, "message:$m1", "Tab: the next section's first row")
        h.search.moveSection(1)
        XCTAssertEqual(h.search.selection, "message:$m1", "no section after the last")
        h.search.moveSelection(-10)
        XCTAssertEqual(h.search.selection, "chat:!c1")
    }

    func testEscapeCascade() async throws {
        let h = try await start(rooms: [room("!a", ts: 1)])
        h.search.show(in: "!a")
        try await waitUntil { h.search.scope != nil }
        h.search.text = "pic"
        h.search.filters.sender = "me"
        h.search.filters.partial = true
        try await waitUntil { h.search.phase == .results }

        XCTAssertFalse(h.search.escape())
        XCTAssertTrue(h.search.filters.isEmpty, "first the filters")
        XCTAssertTrue(h.search.filters.partial, "Show partial matches isn't a filter")
        XCTAssertEqual(h.search.text, "pic")
        XCTAssertNotNil(h.search.scope)

        XCTAssertFalse(h.search.escape())
        XCTAssertEqual(h.search.text, "", "then the text")
        XCTAssertNotNil(h.search.scope)

        XCTAssertFalse(h.search.escape())
        XCTAssertNil(h.search.scope, "then the chat searched in")
        XCTAssertNotEqual(h.search.phase, .closed)

        XCTAssertTrue(h.search.escape(), "then the panel closes")
        XCTAssertEqual(h.search.phase, .closed)
        XCTAssertEqual(h.search.sections, [])
    }

    func testActivatingAMessageJumpsAndRemembersTheSearch() async throws {
        let h = try await start()
        h.script.results["half"] = searchResult(chats: [room("!h", ts: 1)])
        h.script.results["picnic"] = searchResult(
            chats: [room("!c", ts: 1)], inGroups: [personHit("@one", room: "!g")],
            messages: [messageHit("$e1", room: "!r")])

        // Typing alone keeps nothing: half-typed words aren't recent searches.
        try await h.showHome()
        try await h.type("half")
        try await waitUntil { h.search.phase == .results }
        h.search.close()
        XCTAssertEqual(h.recents.searches, [])
        XCTAssertEqual(h.opened, [])

        try await h.showHome()
        try await h.type("picnic")
        try await waitUntil { h.search.phase == .results }
        h.search.select("message:$e1")
        h.search.activate()
        XCTAssertEqual(h.opened, [.message(roomID: "!r", eventID: "$e1")])
        XCTAssertEqual(h.recents.searches.first, "picnic")
        XCTAssertEqual(h.search.phase, .closed, "the panel closes")
        XCTAssertEqual(h.search.text, "")

        // A chat opens it; a person opens the group I share with them.
        try await h.showHome()
        try await h.type("picnic")
        try await waitUntil { h.search.phase == .results }
        h.search.activate()
        try await h.showHome()
        try await h.type("picnic")
        try await waitUntil { h.search.phase == .results }
        h.search.select("person:@one")
        h.search.activate()
        XCTAssertEqual(h.opened, [.message(roomID: "!r", eventID: "$e1"), .chat(roomID: "!c"), .chat(roomID: "!g")])
        XCTAssertEqual(h.recents.searches, ["picnic"])
    }

    func testShowMoreReadsTheNextPage() async throws {
        let h = try await start()
        let chats = (0 ..< 5).map { room("!c\($0)", ts: Int64(10 - $0)) }
        h.script.results["picnic"] = searchResult(
            chats: chats, messages: [messageHit("$1", room: "!c0")], messagesCursor: "page-2")
        h.script.respond = { params in
            if params["cursor"] as? String == "page-2" {
                return searchResult(chats: nil, inGroups: nil, media: nil,
                                    messages: [messageHit("$2", room: "!c1"), messageHit("$1", room: "!c0")])
            }
            if params["limit"] as? Int == 100 {
                return searchResult(chats: chats + [room("!c5", ts: 1), room("!c6", ts: 0)], inGroups: nil,
                                    media: nil, messages: nil)
            }
            return nil
        }
        try await h.showHome()
        h.search.filters.period = .lastWeek
        try await h.type("picnic")
        try await waitUntil { h.search.phase == .results }
        let first = try XCTUnwrap(h.searches.last)
        XCTAssertEqual(h.search.sections.map(\.canShowMore), [true, true])

        // A later page is the same query: "last 7 days" is the first page's, not counted again from a later now.
        h.time.advance(3600)
        await h.search.showMore(.messages)
        var expected = first
        expected["sections"] = ["messages"]
        expected["cursor"] = "page-2"
        XCTAssertEqual(h.searches.last.map { $0 as NSDictionary }, expected as NSDictionary)
        XCTAssertEqual(h.search.sections.last?.items.map(\.id), ["message:$1", "message:$2"],
                       "the next page is added below, and a message already shown isn't shown twice")
        XCTAssertEqual(h.search.sections.last?.canShowMore, false)

        await h.search.showMore(.chats)
        var moreChats = first
        moreChats["sections"] = ["chats"]
        moreChats["limit"] = 100
        XCTAssertEqual(h.searches.last.map { $0 as NSDictionary }, moreChats as NSDictionary)
        XCTAssertEqual(h.chatIDs(.chats).count, 7)
        XCTAssertEqual(h.search.sections.first?.canShowMore, false)
    }

    func testPartialMatchesComeAfterTheFullOnes() async throws {
        let h = try await start()
        h.script.results["picnic blanket"] = searchResult(messages: [
            messageHit("$full", room: "!a"), messageHit("$some", room: "!a", partial: true),
        ])
        try await h.showHome()
        h.search.filters.partial = true
        try await h.type("picnic blanket")
        try await waitUntil { h.search.phase == .results }
        XCTAssertEqual(h.searches.last?["filters"] as? NSDictionary, ["partial": true] as NSDictionary)
        XCTAssertEqual(h.search.sections.last?.partialMatchesStart, 1, "the Partial matches divider sits above $some")
    }

    func testFailureOffersTryAgain() async throws {
        let h = try await start()
        h.script.results["pic"] = searchResult(chats: [room("!c", ts: 1)])
        try await h.showHome()
        h.script.fail = true
        try await h.type("pic")
        try await waitUntil { h.search.phase == .failed }

        h.script.fail = false
        h.search.retry()
        try await waitUntil { h.search.phase == .results }
        XCTAssertEqual(h.chatIDs(.chats), ["!c"])
    }

    func testNoticesSayWhatAnEmptyPanelMeans() async throws {
        let h = try await start()
        XCTAssertNil(h.search.notice, "closed")
        try await h.showHome()
        XCTAssertEqual(h.search.notice, .welcome, "home with nothing recent")

        try await h.type("  zzz ")
        try await waitUntil { h.search.phase == .results }
        XCTAssertEqual(h.search.notice, .noMatches("zzz"), "the words, without the spaces around them")

        h.search.filters.partial = true
        h.search.filters.sender = "me"
        try await waitUntil { h.search.notice == .nothingMatchesFilters }
        h.search.clearFilters()
        XCTAssertTrue(h.search.filters.isEmpty)
        XCTAssertTrue(h.search.filters.partial, "Show partial matches isn't a filter")
        try await waitUntil { h.search.notice == .noMatches("zzz") }

        h.script.results["🎉"] = searchResult(chats: [], inGroups: [], media: nil, messages: nil, hint: "emoji_only")
        try await h.type("🎉")
        try await waitUntil { h.search.notice == .emojiOnly }

        // One letter: no messages yet. Alone it is the notice; under chats that matched, it is a line.
        h.script.results["p"] = searchResult(chats: [], inGroups: [], media: nil, messages: nil,
                                             hint: "need_more_letters")
        try await h.type("p")
        try await waitUntil { h.search.notice == .needMoreLetters }
        XCTAssertFalse(h.search.needsMoreLettersUnderChats)
        h.script.results["q"] = searchResult(chats: [room("!q", ts: 1)], media: nil, messages: nil,
                                             hint: "need_more_letters")
        try await h.type("q")
        try await waitUntil { h.search.sections.map(\.kind) == [.chats] }
        XCTAssertNil(h.search.notice)
        XCTAssertTrue(h.search.needsMoreLettersUnderChats)

        h.script.fail = true
        try await h.type("qr")
        try await waitUntil { h.search.notice == .failed }
    }

    /// Ruling 34: filters with no words list their messages. "Nothing matches these filters" is only for a search the
    /// engine ran and found nothing for; when it ran nothing at all (every section null), the panel says what to do.
    func testFiltersAloneSayNothingMatchesOnlyWhenTheSearchRan() async throws {
        let h = try await start()
        try await h.showHome()
        h.script.respond = { params in
            let filters = params["filters"] as? [String: Any]
            if filters?["chat_type"] as? String == "dm" {
                return searchResult(chats: nil, inGroups: nil, media: [], messages: [messageHit("$dm", room: "!d")])
            }
            if filters?["sender"] as? String == "others" {
                return searchResult(chats: nil, inGroups: nil, media: [], messages: []) // ran, found nothing
            }
            return searchResult(chats: nil, inGroups: nil, media: nil, messages: nil) // ran nothing
        }

        h.search.filters = SearchFilterSet(chatType: "dm")
        try await waitUntil { h.search.sections.map(\.kind) == [.messages] }
        XCTAssertEqual(h.searches.last?["text"] as? String, "")
        XCTAssertNil(h.search.notice)

        h.search.filters = SearchFilterSet(sender: "others", period: .lastWeek)
        try await waitUntil { h.search.notice == .nothingMatchesFilters }

        h.search.filters = SearchFilterSet(period: .lastYear)
        try await waitUntil { h.search.notice == .welcome }
        XCTAssertEqual(h.search.phase, .results)
    }

    /// Ruling 37c: ⌘F's home inside one chat, with no recent searches, speaks of that chat.
    func testHomeInsideAChatSaysWhatItSearches() async throws {
        let h = try await start(rooms: [room("!a", ts: 1)])
        h.search.show(in: "!a")
        try await waitUntil { h.search.scope?.roomID == "!a" }
        XCTAssertEqual(h.search.notice, .welcomeInChat)
        h.search.removeScope()
        try await waitUntil { h.search.notice == .welcome }
    }

    func testCommandKTogglesOnlyAPanelInView() async throws {
        let h = try await start(rooms: [room("!a", ts: 1)])
        h.search.toggle(visible: true)
        XCTAssertEqual(h.search.phase, .home, "closed: ⌘K opens it")
        h.search.toggle(visible: true)
        XCTAssertEqual(h.search.phase, .closed, "open in front: ⌘K closes it")

        // Open in a window that is closed or behind another: ⌘K shows it, over every chat, and never closes it unseen.
        h.search.show(in: "!a")
        try await waitUntil { h.search.scope?.roomID == "!a" }
        h.search.toggle(visible: false)
        XCTAssertEqual(h.search.phase, .home)
        XCTAssertNil(h.search.scope, "⌘K searches every chat")
        h.search.toggle(visible: false)
        XCTAssertEqual(h.search.phase, .home)
        h.search.toggle(visible: true)
        XCTAssertEqual(h.search.phase, .closed)
    }

    func testSearchingShowsOnlyAfterADelay() async throws {
        let h = try await start()
        try await h.showHome()
        h.script.hold = true
        try await h.type("pic")
        try await waitUntil { h.searches.last?["text"] as? String == "pic" && h.time.pendingSleeps == [0.3] }
        h.time.advance(0.29)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(h.search.phase, .home, "a quick answer never flashes Searching…")
        h.time.advance(0.01)
        try await waitUntil { h.search.phase == .searching }
        let id = try XCTUnwrap(h.server.received.last { $0["method"] as? String == "search.query" }?["id"] as? Int)
        h.server.reply(to: id, with: searchResult(chats: [room("!c", ts: 1)]))
        try await waitUntil { h.search.phase == .results }
    }

    func testAChangeDoesNotRerunAnOpenSearch() async throws {
        let h = try await start()
        h.script.results["pic"] = searchResult(chats: [room("!c", ts: 1)])
        try await h.showHome()
        try await h.type("pic")
        try await waitUntil { h.search.phase == .results }
        let count = h.searches.count
        h.server.notify(["kind": "event", "room_id": "!c", "event_id": "$new"])
        h.server.notify(["kind": "room", "room_id": "!c"])
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(h.searches.count, count, "rows never move under the keyboard")
        XCTAssertEqual(h.chatIDs(.chats), ["!c"])
    }

    func testLongTextIsCutAt500UnicodeScalars() async throws {
        let h = try await start()
        try await h.showHome()
        // 300 Characters, each an e and a combining accent: 600 scalars, which is what the engine counts.
        try await h.type(String(repeating: "e\u{301}", count: 300))
        try await waitUntil { h.searches.count == 2 }
        let sent = try XCTUnwrap(h.searches.last?["text"] as? String)
        XCTAssertEqual(sent.unicodeScalars.count, 500)
        XCTAssertTrue(h.search.text.unicodeScalars.starts(with: sent.unicodeScalars))
    }

    // MARK: - Return while a search is pending

    func testReturnBeforeThePauseEndsOpensTheNewAnswersFirstRow() async throws {
        let h = try await start(rooms: [room("!old", ts: 1)])
        h.recents.addChat("!old")
        h.script.results["dinne"] = searchResult(chats: [room("!dinette", ts: 2)])
        h.script.results["din"] = searchResult(chats: [room("!din", ts: 3)])
        h.script.results["dinner"] = searchResult(messages: [messageHit("$dinner", room: "!din")])
        try await h.showHome()
        XCTAssertEqual(h.chatIDs(.recent), ["!old"])

        // From home: Return inside the pause never opens the Recent chat on screen.
        h.search.text = "din"
        h.search.activate()
        try await waitUntil { h.opened == [.chat(roomID: "!din")] }
        XCTAssertEqual(h.searches.last?["text"] as? String, "din", "searched at once, without the rest of the pause")
        XCTAssertEqual(h.recents.searches, ["din"], "kept with the result it opened")
        XCTAssertEqual(h.search.phase, .closed)

        // From results: the top hit for "dinne" isn't the one for "dinner".
        try await h.showHome()
        try await h.type("dinne")
        try await waitUntil { h.chatIDs(.chats) == ["!dinette"] }
        h.search.text = "dinner"
        h.search.activate()
        try await waitUntil { h.opened.count == 2 }
        XCTAssertEqual(h.opened.last, .message(roomID: "!din", eventID: "$dinner"))
        XCTAssertEqual(h.recents.searches.first, "dinner")
    }

    func testAKeystrokeAfterReturnCancelsTheOpen() async throws {
        let h = try await start()
        h.script.results["din"] = searchResult(chats: [room("!din", ts: 3)])
        try await h.showHome()
        h.script.hold = true
        h.search.text = "din"
        h.search.activate()
        try await waitUntil { h.searches.last?["text"] as? String == "din" }
        let id = try XCTUnwrap(h.server.received.last { $0["method"] as? String == "search.query" }?["id"] as? Int)

        // Return, then typing on before the answer: the open is off.
        h.search.text = "dinn"
        h.server.reply(to: id, with: searchResult(chats: [room("!din", ts: 3)]))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(h.opened, [])
        XCTAssertEqual(h.recents.searches, [])
        XCTAssertNotEqual(h.search.phase, .closed)
    }

    func testReturnOnAnEmptyAnswerOrAFailureOpensNothing() async throws {
        let h = try await start()
        try await h.showHome()
        h.search.text = "zzz"
        h.search.activate()
        try await waitUntil { h.search.phase == .results }
        XCTAssertEqual(h.search.sections, [])
        XCTAssertEqual(h.opened, [])
        XCTAssertEqual(h.recents.searches, [], "nothing opened, nothing kept")

        h.script.fail = true
        h.search.text = "pic"
        h.search.activate()
        try await waitUntil { h.search.phase == .failed }
        h.search.activate()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(h.opened, [])
        XCTAssertEqual(h.recents.searches, [])
        XCTAssertEqual(h.search.phase, .failed, "Return on a failure is not Try Again")
    }

    // MARK: - Snippets

    func testSnippetRangesAreUTF16CodeUnits() {
        // 🎉 is 2 UTF-16 code units and 1 Character: counted in Characters, both ranges would land one early.
        let hit = MessageHit(
            eventID: "$1", roomID: "!a", roomName: "A", network: "whatsapp", isDirect: true, sender: "@x",
            senderName: "X", mine: false, ts: 1, seq: 1, snippet: "🎉 東京タワー picnic",
            ranges: [TextRange(start: 3, length: 2), TextRange(start: 9, length: 6), TextRange(start: 14, length: 9)])
        let snippet = hit.snippet as NSString
        XCTAssertEqual(hit.matchRanges.map { snippet.substring(with: $0) }, ["東京", "picnic"],
                       "a range past the end is left out")
        let highlighted = hit.highlightedSnippet
        let bold = highlighted.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(highlighted[$0.range].characters) }
        XCTAssertEqual(bold, ["東京", "picnic"])
        XCTAssertEqual(String(highlighted.characters), hit.snippet)
    }
}

// MARK: - Harness

/// A search model on an app model on a stand-in engine, with what it opened written down.
@MainActor
final class SearchHarness {
    let script: SearchScript
    let server: TestEngineServer
    let app: AppModel
    let recents: RecentSearches
    let search: SearchModel
    let store: TestDefaults
    let time: FakeTime
    private let targets = OpenedTargets()

    init(script: SearchScript, server: TestEngineServer, app: AppModel, store: TestDefaults, time: FakeTime) {
        self.script = script
        self.server = server
        self.app = app
        self.store = store
        self.time = time
        recents = RecentSearches(defaults: store.defaults)
        let targets = targets
        search = SearchModel(appModel: app, recents: recents, open: { targets.all.append($0) },
                             now: { Date(timeIntervalSince1970: time.now) }, sleep: { try await time.sleep(for: $0) })
    }

    /// What the model opened, in order.
    var opened: [SearchTarget] { targets.all }

    /// search.query's params, in order.
    var searches: [[String: Any]] { server.receivedParams("search.query") }

    /// `now` in Unix milliseconds.
    var nowMillis: Int64 { Int64((time.now * 1000).rounded()) }

    /// Types `text`, and lets the pause after typing pass on the clock.
    func type(_ text: String) async throws {
        search.text = text
        try await waitUntil { self.time.pendingSleeps.contains(0.15) }
        time.advance(0.15)
    }

    /// The chats of a section, by room.
    func chatIDs(_ kind: SearchSection.Kind) -> [String] {
        search.sections.first { $0.kind == kind }?.items.compactMap {
            if case let .chat(row) = $0 { return row.roomID }
            return nil
        } ?? []
    }

    /// Opens the panel and waits for home's answer.
    func showHome() async throws {
        let count = searches.count
        search.show()
        try await waitUntil { self.searches.count == count + 1 }
        try await Task.sleep(for: .milliseconds(50))
    }

    func cleanUp() {
        server.stop()
        store.remove()
    }
}

@MainActor
func startSearch(rooms: [[String: Any]]) async throws -> SearchHarness {
    let script = SearchScript(rooms: rooms)
    let server = try TestEngineServer(handler: script.handle)
    let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
    let supervisor = EngineSupervisor(
        enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
        dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:], launcher: launcher,
        credentials: InMemoryCredentialStore(), clientName: "Courier/test", timing: FakeTime().timing())
    let app = AppModel(supervisor: supervisor)
    let time = FakeTime()
    time.advance(1_760_600_000 - time.now)
    let harness = SearchHarness(script: script, server: server, app: app, store: TestDefaults(), time: time)
    app.start()
    try await waitUntil { app.client != nil }
    return harness
}

@MainActor
final class OpenedTargets {
    var all: [SearchTarget] = []
}

/// What the stand-in engine answers search.query and inbox.list with. Empty text with no filters is home (only
/// last_archived); other text answers `results[text]`, or every section empty; room_ids leaves out chats and
/// in_groups, as the engine does. `respond` answers first when it gives something.
final class SearchScript: @unchecked Sendable {
    private let lock = NSLock()
    private var _rooms: [[String: Any]]
    private var _results: [String: [String: Any]] = [:]
    private var _lastArchived: [String: Any]?
    private var _hold = false
    private var _fail = false
    private var _respond: (@Sendable ([String: Any]) -> [String: Any]?)?

    init(rooms: [[String: Any]]) { _rooms = rooms }

    var results: [String: [String: Any]] {
        get { lock.withLock { _results } }
        set { lock.withLock { _results = newValue } }
    }

    var lastArchived: [String: Any]? {
        get { lock.withLock { _lastArchived } }
        set { lock.withLock { _lastArchived = newValue } }
    }

    /// While set, search.query isn't answered until the test replies.
    var hold: Bool {
        get { lock.withLock { _hold } }
        set { lock.withLock { _hold = newValue } }
    }

    /// While set, search.query fails.
    var fail: Bool {
        get { lock.withLock { _fail } }
        set { lock.withLock { _fail = newValue } }
    }

    var respond: (@Sendable ([String: Any]) -> [String: Any]?)? {
        get { lock.withLock { _respond } }
        set { lock.withLock { _respond = newValue } }
    }

    func handle(_ method: String, _ params: [String: Any]?) -> TestEngineServer.Reply {
        let params = params ?? [:]
        switch method {
        case "hello": return TestEngineServer.helloOK
        case "accounts.list": return .result(["accounts": [[String: Any]]()])
        case "inbox.list":
            let ids = params["room_ids"] as? [String] ?? []
            let rooms = lock.withLock { _rooms }
            return .result(page(ids.compactMap { id in rooms.first { $0["room_id"] as? String == id } }))
        case "search.query":
            if fail { return .error(code: -32603, message: "internal error") }
            if hold { return .later }
            if let answer = respond?(params) { return .result(answer) }
            let text = params["text"] as? String ?? ""
            let filters = params["filters"] as? [String: Any]
            if text.trimmingCharacters(in: .whitespaces).isEmpty, filters == nil {
                return .result(searchResult(chats: nil, inGroups: nil, media: nil, messages: nil,
                                            lastArchived: lastArchived))
            }
            var result = results[text] ?? searchResult()
            if filters?["room_ids"] != nil {
                result["chats"] = NSNull()
                result["in_groups"] = NSNull()
            }
            return .result(result)
        default: return .result([String: Any]())
        }
    }
}

// MARK: - Fixtures

/// A SearchResult as the engine writes it. A section given as nil is null.
func searchResult(chats: [[String: Any]]? = [], inGroups: [[String: Any]]? = [], media: [[String: Any]]? = [],
                  messages: [[String: Any]]? = [], messagesCursor: String? = nil, lastArchived: [String: Any]? = nil,
                  complete: Bool = true, hint: String = "") -> [String: Any] {
    func hits(_ list: [[String: Any]]?, _ cursor: String?) -> Any {
        guard let list else { return NSNull() }
        return ["hits": list, "next_cursor": cursor as Any? ?? NSNull()]
    }
    return [
        "chats": chats as Any? ?? NSNull(), "in_groups": inGroups as Any? ?? NSNull(), "bookmarks": NSNull(),
        "media": hits(media, nil), "messages": hits(messages, messagesCursor),
        "last_archived": lastArchived as Any? ?? NSNull(), "complete": complete, "hint": hint,
    ]
}

/// A MessageHit as the engine writes it.
func messageHit(_ id: String, room: String, kind: String = "text", partial: Bool = false,
                snippet: String = "a picnic on Saturday") -> [String: Any] {
    [
        "event_id": id, "room_id": room, "room_name": "Chat \(room)", "network": "whatsapp", "is_direct": false,
        "place": "inbox", "sender": "@whatsapp_x:courier.local", "sender_name": "X", "mine": false,
        "ts": 1_760_600_000_000, "seq": 1, "kind": kind, "snippet": snippet,
        "ranges": [["start": 2, "length": 6]], "media_path": "", "partial": partial,
    ]
}

/// A PersonHit as the engine writes it.
func personHit(_ user: String, room: String) -> [String: Any] {
    [
        "user_id": user, "name": "Person \(user)", "network": "whatsapp", "avatar_path": "", "room_id": room,
        "room_name": "Group \(room)", "groups": 2,
    ]
}
