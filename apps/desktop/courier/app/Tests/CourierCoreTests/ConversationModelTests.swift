// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The conversation model against a stand-in engine that keeps a few chats' events and pages them as the real
/// engine does. All data here is made up.
@MainActor
final class ConversationModelTests: XCTestCase {
    private var servers: [TestEngineServer] = []
    /// Stopped even when a test fails before its own `stop`, so its engine can't hold on into the next test.
    private var apps: [AppModel] = []

    override func tearDown() async throws {
        for app in apps { await app.stop() }
        apps = []
        for server in servers { server.stop() }
        servers = []
    }

    // MARK: - Harness

    @MainActor private struct Harness {
        let script: ConversationScript
        let server: TestEngineServer
        let app: AppModel
        let conversation: ConversationModel
        let unread: UnreadBox

        func count(_ method: String) -> Int { server.receivedMethods().filter { $0 == method }.count }
        func messageIDs() -> [String] {
            conversation.items.compactMap { if case let .message(m) = $0 { m.id } else { nil } }
        }
    }

    /// What the inbox would say a chat's unread count is when it is opened.
    private final class UnreadBox: @unchecked Sendable {
        var counts: [String: Int] = [:]
    }

    private func start(_ events: [String: [[String: Any]]], windowIsKey: Bool = true,
                       presence: StaticPresence? = nil, time: FakeTime? = nil) async throws -> Harness {
        let script = ConversationScript(events: events)
        let server = try TestEngineServer(handler: script.handle)
        servers.append(server)
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:], launcher: launcher,
            credentials: InMemoryCredentialStore(), clientName: "Courier/test", timing: FakeTime().timing())
        let app = AppModel(supervisor: supervisor)
        apps.append(app)
        let unread = UnreadBox()
        let clock = time ?? FakeTime()
        let conversation = ConversationModel(appModel: app, unreadCount: { unread.counts[$0] ?? 0 },
                                             attention: Attention(source: presence ?? StaticPresence(), pollInterval: nil),
                                             sleep: { try await clock.sleep(for: $0) })
        conversation.setWindowKey(windowIsKey)
        app.start()
        try await waitUntil { app.client != nil }
        return Harness(script: script, server: server, app: app, conversation: conversation, unread: unread)
    }

    private func stop(_ harness: Harness) async {
        await harness.app.stop()
    }

    /// n events in a chat, `$1` oldest, each a minute after the last, from someone else unless `mineEvery` says so.
    private func history(_ count: Int, room: String = "!a") -> [[String: Any]] {
        (1 ... count).map { textEvent(id: "$\($0)", room: room, at: Int64($0), body: "Message \($0)") }
    }

    // MARK: - Opening

    func testOpeningLoadsTheNewestPageAndMarksRead() async throws {
        let h = try await start(["!a": history(3)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertEqual(h.messageIDs(), ["$1", "$2", "$3"], "oldest first, newest last")
        XCTAssertFalse(h.conversation.hasOlder)

        try await waitUntil { h.count("room.markRead") == 1 }
        XCTAssertEqual(h.server.receivedParams("room.markRead").first as? [String: String], ["room_id": "!a"])
        let first = h.server.receivedParams("room.events").first
        XCTAssertEqual(Set((first ?? [:]).keys), ["room_id", "limit"], "only documented keys, and no cursor for the newest page")
        await stop(h)
    }

    func testOpeningWithTheWindowNotKeyDoesNotMarkReadUntilItIs() async throws {
        let h = try await start(["!a": history(2)], windowIsKey: false)
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 0, "an open chat in a window nobody is looking at is not read")

        h.conversation.setWindowKey(true)
        try await waitUntil { h.count("room.markRead") == 1 }

        h.conversation.setWindowKey(false)
        h.conversation.setWindowKey(true)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 1, "already read: coming back to the window says nothing more")
        await stop(h)
    }

    func testTheNewDividerIsPlacedFromTheInboxsUnreadCountAndStays() async throws {
        let h = try await start(["!a": history(5)])
        h.unread.counts["!a"] = 2
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        let ids = h.conversation.items.map(\.id)
        let divider = try XCTUnwrap(ids.firstIndex(of: "new"))
        XCTAssertEqual(ids[divider + 1], "$4", "the two newest are new")

        // Reading it (the inbox's count drops to 0) and a refetch do not move the divider while the chat is open.
        h.unread.counts["!a"] = 0
        h.script.add("!a", textEvent(id: "$6", room: "!a", at: 6))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$6"])
        try await waitUntil { h.messageIDs().contains("$6") }
        XCTAssertEqual(h.conversation.items.map(\.id).firstIndex(of: "new"), divider)

        // Opening it again later has no divider: nothing is unread.
        h.app.selectedRoomID = nil
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.messageIDs().contains("$6") }
        XCTAssertFalse(h.conversation.items.contains { $0.id == "new" })
        await stop(h)
    }

    /// Ruling 35: a chat opened from outside the inbox's list has no count when it opens; the inbox looks its row up
    /// and passes the count on, and the divider goes where it would have, whichever comes first.
    func testAnUnreadCountLearnedAfterOpeningPlacesTheDivider() async throws {
        let h = try await start(["!a": history(5), "!b": history(5, room: "!b")])
        // The count arrives after the newest page.
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertFalse(h.conversation.items.contains { $0.id == "new" })
        h.conversation.learnUnreadCount(2, of: "!b")
        XCTAssertFalse(h.conversation.items.contains { $0.id == "new" }, "another chat's count changes nothing")
        h.conversation.learnUnreadCount(2, of: "!a")
        let ids = h.conversation.items.map(\.id)
        let divider = try XCTUnwrap(ids.firstIndex(of: "new"))
        XCTAssertEqual(ids[divider + 1], "$4", "the two newest are new")

        // The count arrives before it.
        h.script.hold("!b")
        h.app.selectedRoomID = "!b"
        try await waitUntil { h.server.receivedParams("room.events").contains { $0["room_id"] as? String == "!b" } }
        h.conversation.learnUnreadCount(1, of: "!b")
        h.server.releaseHeld(method: "room.events", room: "!b",
                             with: ["events": h.script.newestFirst("!b", limit: 50), "before": NSNull(), "after": NSNull()])
        try await waitUntil { h.conversation.isLoaded && h.conversation.items.contains { $0.id == "new" } }
        let idsB = h.conversation.items.map(\.id)
        XCTAssertEqual(idsB[try XCTUnwrap(idsB.firstIndex(of: "new")) + 1], "$5")
        await stop(h)
    }

    func testNothingOpenShowsNothing() async throws {
        let h = try await start(["!a": history(2)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.app.selectedRoomID = nil
        XCTAssertTrue(h.conversation.items.isEmpty)
        XCTAssertFalse(h.conversation.isLoaded)
        XCTAssertNil(h.conversation.roomID)
        await stop(h)
    }

    // MARK: - Paging and merging

    func testScrollingToTheTopLoadsTheNextPageWithTheCursor() async throws {
        let h = try await start(["!a": history(120)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertEqual(h.messageIDs().count, 50)
        XCTAssertTrue(h.conversation.hasOlder)

        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 100 }
        let params = try XCTUnwrap(h.server.receivedParams("room.events").last)
        XCTAssertEqual(Set(params.keys), ["room_id", "before", "limit"])
        let before = try XCTUnwrap(params["before"] as? [String: Any])
        XCTAssertEqual(before["ts"] as? Int64, ConversationScript.timestamp(71), "the oldest event of the page we have")
        XCTAssertEqual(before["seq"] as? Int64, 71)
        XCTAssertEqual(h.messageIDs().first, "$21")
        XCTAssertEqual(h.messageIDs().last, "$120")
        XCTAssertTrue(h.conversation.hasOlder)

        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 120 }
        XCTAssertFalse(h.conversation.hasOlder, "the engine said there is nothing older")
        let calls = h.count("room.events")
        h.conversation.loadOlder()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(h.count("room.events"), calls, "no more pages, no more calls")
        await stop(h)
    }

    func testAnEventChangeRefetchesTheNewestPageAndKeepsOlderPages() async throws {
        let h = try await start(["!a": history(120)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 100 }

        // A message arrives, and one of the loaded ones changes status.
        h.script.add("!a", textEvent(id: "$121", room: "!a", at: 121))
        h.script.replace("!a", textEvent(id: "$120", room: "!a", at: 120, body: "Message 120, changed"))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$121"])
        try await waitUntil { h.messageIDs().last == "$121" }

        XCTAssertEqual(h.messageIDs().count, 101, "the older pages stayed")
        XCTAssertEqual(h.messageIDs().first, "$21")
        let last = h.server.receivedParams("room.events").last ?? [:]
        XCTAssertNil(last["before"], "the refetch is of the newest page")
        guard case let .message(changed)? = h.conversation.items.first(where: { $0.id == "$120" }) else {
            return XCTFail("$120 is missing")
        }
        XCTAssertEqual(changed.body, "Message 120, changed")
        await stop(h)
    }

    func testResyncDropsOlderPages() async throws {
        let h = try await start(["!a": history(120)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 100 }

        h.server.notify(["kind": "resync"])
        try await waitUntil { h.messageIDs().count == 50 }
        XCTAssertEqual(h.messageIDs().first, "$71")
        XCTAssertTrue(h.conversation.hasOlder, "the older pages can be loaded again")
        await stop(h)
    }

    func testADiscardedMessageIsGoneAfterTheNextRead() async throws {
        let failed = textEvent(id: "$3", room: "!a", at: 3, mine: true, status: "failed", reason: "no network")
        let h = try await start(["!a": [textEvent(id: "$1", room: "!a", at: 1), textEvent(id: "$2", room: "!a", at: 2), failed]])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.messageIDs() == ["$1", "$2", "$3"] }

        await h.conversation.discard("$3")
        h.script.remove("!a", "$3")
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { h.messageIDs() == ["$1", "$2"] }
        await stop(h)
    }

    /// Protocol 4: a page may hold fewer events than asked for, even none, and still have older ones (here, every
    /// message of the newest page was deleted for me). Only the cursors say what there is.
    func testAPageWithFewerEventsThanAskedStillPagesByItsCursor() async throws {
        let h = try await start(["!a": history(60)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 60 }

        // Every message of the newest page is deleted for me: the page comes back empty, with older ones before it.
        h.script.deleteForMe((11 ... 60).map { "$\($0)" })
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$60"])
        try await waitUntil { h.messageIDs().count == 10 }
        XCTAssertEqual(h.messageIDs().first, "$1", "the older page stays: the empty page covers only its own")
        XCTAssertEqual(h.messageIDs().last, "$10")

        // Opened afresh, the empty newest page still offers the older ones.
        h.app.selectedRoomID = nil
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded && h.conversation.hasOlder }
        XCTAssertEqual(h.messageIDs(), [])
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 10 }
        XCTAssertFalse(h.conversation.hasOlder)
        await stop(h)
    }

    func testABurstLargerThanAPageDoesNotLeaveAHole() async throws {
        let h = try await start(["!a": history(60)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.messageIDs().last == "$60" }
        for n in 61 ... 130 { h.script.add("!a", textEvent(id: "$\(n)", room: "!a", at: Int64(n))) }
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$130"])
        try await waitUntil { h.messageIDs().last == "$130" }
        XCTAssertEqual(h.messageIDs().first, "$81", "the newest page only: what was loaded no longer joins it")
        XCTAssertEqual(h.messageIDs().count, 50)
        XCTAssertTrue(h.conversation.hasOlder)
        await stop(h)
    }

    func testAResyncDropsOlderPagesEvenWhenAnotherReadLandsFirst() async throws {
        let h = try await start(["!a": history(120)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 100 }

        // The resync's own read is held; another read (a send settling, "Try again"), started after it, answers
        // first. (The engine's changes wait behind the resync, so this is how one gets ahead.)
        let reads = h.count("room.events")
        h.script.hold("!a")
        h.server.notify(["kind": "resync"])
        try await waitUntil { h.count("room.events") == reads + 1 }
        h.script.add("!a", textEvent(id: "$121", room: "!a", at: 121))
        h.conversation.reload()
        try await waitUntil { h.messageIDs().last == "$121" }
        XCTAssertEqual(h.messageIDs().count, 50, "the older pages are gone, whichever answer came first")
        XCTAssertTrue(h.conversation.hasOlder)

        // The held answer, late, changes nothing.
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 50), "before": NSNull(), "after": NSNull()])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.messageIDs().count, 50)
        await stop(h)
    }

    func testAFailedOlderPageIsOfferedAgainAndCanBeLoaded() async throws {
        let h = try await start(["!a": history(120)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }

        h.script.failOlder = true
        h.conversation.loadOlder()
        try await waitUntil { h.conversation.olderFailed }
        XCTAssertFalse(h.conversation.isLoadingOlder)
        XCTAssertTrue(h.conversation.hasOlder)
        XCTAssertEqual(h.messageIDs().count, 50)

        h.script.failOlder = false
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 100 }
        XCTAssertFalse(h.conversation.olderFailed)
        await stop(h)
    }

    // MARK: - Answers that are not today's

    func testAnAnswerForAChatThatIsNoLongerOpenIsDropped() async throws {
        let h = try await start(["!a": history(3, room: "!a"), "!b": history(2, room: "!b")])
        h.script.hold("!a")
        h.script.hold("!b")
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.count("room.events") == 1 }
        h.app.selectedRoomID = "!b"
        try await waitUntil { h.count("room.events") == 2 }

        // Chat a's answer comes first, after the person moved on. It is the first answer of all, so only the
        // check of which chat is open can turn it away.
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 50), "before": NSNull(), "after": NSNull()])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.conversation.roomID, "!b")
        XCTAssertTrue(h.conversation.items.isEmpty, "chat a's late answer does not land in chat b")
        XCTAssertFalse(h.conversation.isLoaded)
        XCTAssertEqual(h.count("room.markRead"), 0)

        h.server.releaseHeld(method: "room.events", room: "!b",
                             with: ["events": h.script.newestFirst("!b", limit: 50), "before": NSNull(), "after": NSNull()])
        try await waitUntil { h.messageIDs() == ["$1", "$2"] }
        for case let .message(m) in h.conversation.items { XCTAssertEqual(m.roomID, "!b") }
        await stop(h)
    }

    func testAnEngineRestartReadsTheChatAgainAndTheOldEnginesLateAnswerIsDropped() async throws {
        let pending = textEvent(id: "$3", room: "!a", at: 3, mine: true, status: "pending")
        let first = ConversationScript(events: ["!a": [textEvent(id: "$1", room: "!a", at: 1), pending]])
        let sentNow = textEvent(id: "$3", room: "!a", at: 3, mine: true, status: "sent")
        let second = ConversationScript(events: ["!a": [
            textEvent(id: "$1", room: "!a", at: 1), sentNow, textEvent(id: "$4", room: "!a", at: 4),
        ]])
        let firstServer = try TestEngineServer(handler: first.handle)
        let secondServer = try TestEngineServer(handler: second.handle)
        servers += [firstServer, secondServer]
        let launcher = FakeLauncher { index, process in
            process.printReady(socket: index == 0 ? firstServer.path : secondServer.path)
        }
        let supervisor = EngineSupervisor(
            enginePath: "/x/courier-engine", dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"),
            environment: [:], launcher: launcher, credentials: InMemoryCredentialStore(), clientName: "Courier/test",
            timing: FakeTime().timing())
        let app = AppModel(supervisor: supervisor)
        let conversation = ConversationModel(appModel: app)
        app.start()
        try await waitUntil { app.client != nil }
        app.selectedRoomID = "!a"
        try await waitUntil { conversation.isLoaded }
        func statuses() -> [StatusLine?] {
            conversation.items.compactMap { if case let .message(m) = $0, m.id == "$3" { m.statusLine } else { nil } }
        }
        XCTAssertEqual(statuses(), [.sending], "the first engine's store has it pending")

        // The first engine is asked again, sits on the question, and dies.
        first.hold("!a")
        firstServer.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { firstServer.receivedMethods().filter { $0 == "room.events" }.count == 2 }
        launcher.processes[0].exit(1)
        firstServer.dropConnections()

        try await waitUntil { conversation.items.contains { $0.id == "$4" } }
        XCTAssertEqual(statuses(), [.sent], "shown as the new engine's store has it: not lost, not twice")
        XCTAssertEqual(conversation.items.filter { $0.id == "$3" }.count, 1)

        // The old engine's late answer has nowhere to go.
        firstServer.releaseHeld(method: "room.events", room: "!a",
                                with: ["events": first.newestFirst("!a", limit: 50), "before": NSNull(), "after": NSNull()])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(statuses(), [.sent])
        await app.stop()
    }

    // MARK: - Reading and counting while open

    func testAMessageArrivingWhileOpenAndKeyMarksRead() async throws {
        let h = try await start(["!a": history(2)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.count("room.markRead") == 1 }

        h.script.add("!a", textEvent(id: "$3", room: "!a", at: 3))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { h.count("room.markRead") == 2 }

        // My own message, a reaction and a status change are not messages to read.
        h.script.add("!a", textEvent(id: "$4", room: "!a", at: 4, mine: true, status: "pending"))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$4"])
        try await waitUntil { h.messageIDs().last == "$4" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 2)
        await stop(h)
    }

    func testAKeyWindowNobodyIsLookingAtDoesNotMarkReadUntilTheyAre() async throws {
        let presence = StaticPresence()
        presence.isScreenLocked = true
        let h = try await start(["!a": history(2)], presence: presence)
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 0, "the window is key, but the screen is locked")

        // Unlocked: the chat is read then.
        presence.isScreenLocked = false
        presence.onChange?()
        try await waitUntil { h.count("room.markRead") == 1 }

        // Away from the keyboard: a new message waits, and is read when they come back.
        presence.secondsSinceLastInput = Attention.idleLimit + 1
        h.conversation.attention.reevaluate()
        h.script.add("!a", textEvent(id: "$3", room: "!a", at: 3))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { h.messageIDs().last == "$3" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 1, "nobody has touched the Mac for three minutes")
        presence.secondsSinceLastInput = 0
        h.conversation.attention.reevaluate()
        try await waitUntil { h.count("room.markRead") == 2 }

        // The view went away (⌘W): an open chat in a closed window is not being read.
        h.conversation.setWindowKey(false)
        h.script.add("!a", textEvent(id: "$4", room: "!a", at: 4))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$4"])
        try await waitUntil { h.messageIDs().last == "$4" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 2)
        await stop(h)
    }

    func testAMessageArrivingWhileTheWindowIsNotKeyWaitsForIt() async throws {
        let h = try await start(["!a": history(2)], windowIsKey: false)
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.script.add("!a", textEvent(id: "$3", room: "!a", at: 3))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { h.messageIDs().last == "$3" }
        XCTAssertEqual(h.count("room.markRead"), 0)
        h.conversation.setWindowKey(true)
        try await waitUntil { h.count("room.markRead") == 1 }
        await stop(h)
    }

    func testMessagesWhileScrolledUpAreCountedUntilJumpToBottom() async throws {
        let h = try await start(["!a": history(3)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertEqual(h.conversation.newMessageCount, 0)

        // At the bottom, a new message is simply seen.
        h.script.add("!a", textEvent(id: "$4", room: "!a", at: 4))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$4"])
        try await waitUntil { h.messageIDs().last == "$4" }
        XCTAssertEqual(h.conversation.newMessageCount, 0)

        h.conversation.scrolled(toBottom: false)
        h.script.add("!a", textEvent(id: "$5", room: "!a", at: 5))
        h.script.add("!a", textEvent(id: "$6", room: "!a", at: 6, mine: true))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$5"])
        try await waitUntil { h.messageIDs().last == "$6" }
        XCTAssertEqual(h.conversation.newMessageCount, 1, "only messages from others count")

        let token = h.conversation.jumpToBottomRequest
        h.conversation.jumpToBottom()
        XCTAssertEqual(h.conversation.jumpToBottomRequest, token + 1, "⌘↓ asks the view to scroll")
        h.conversation.scrolled(toBottom: true)
        XCTAssertEqual(h.conversation.newMessageCount, 0)
        await stop(h)
    }

    // MARK: - Opening at a message

    func testJumpOpensAroundTheMessage() async throws {
        let h = try await start(["!a": history(200)])
        h.unread.counts["!a"] = 3
        h.app.open(.message(roomID: "!a", eventID: "$100"))
        XCTAssertEqual(h.app.selectedRoomID, "!a")
        try await waitUntil { h.conversation.isLoaded }

        let first = try XCTUnwrap(h.server.receivedParams("room.events").first)
        XCTAssertEqual(Set(first.keys), ["room_id", "around", "limit"], "the first read is the page around the message")
        XCTAssertEqual(first["around"] as? String, "$100")
        XCTAssertEqual(first["limit"] as? Int, ConversationModel.pageSize)
        XCTAssertEqual(h.count("room.events"), 1, "the newest page is not read")
        XCTAssertEqual(h.messageIDs().first, "$76")
        XCTAssertEqual(h.messageIDs().last, "$125")

        XCTAssertEqual(h.conversation.highlightedMessageID, "$100")
        XCTAssertEqual(h.conversation.scrollToMessageRequest?.messageID, "$100")
        XCTAssertTrue(h.conversation.isAwayFromLatest)
        XCTAssertTrue(h.conversation.hasOlder)
        XCTAssertFalse(h.conversation.hasNewerWhileAway)
        XCTAssertFalse(h.conversation.items.contains { $0.id == "new" }, "no New divider while away")

        // The newest messages have not been seen: the chat is not marked read, even when the person comes back.
        h.conversation.setWindowKey(false)
        h.conversation.setWindowKey(true)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 0)
        await stop(h)
    }

    func testPagesForADroppedWindowAreDropped() async throws {
        let h = try await start(["!a": history(120)])

        // The page around the message is late; the person sends (back to the latest) before it comes.
        h.script.hold("!a")
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.count("room.events") == 1 }
        h.conversation.jumpToBottom()
        try await waitUntil { h.messageIDs().last == "$120" }
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 115).suffix(50).map { $0 },
                                    "before": ["ts": ConversationScript.timestamp(6), "seq": 6],
                                    "after": ["ts": ConversationScript.timestamp(55), "seq": 55]])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.messageIDs().first, "$71", "the late window lands nowhere")
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertNil(h.conversation.highlightedMessageID)

        // A newer page of a window that "Jump to latest" let go of joins nothing either.
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isAwayFromLatest }
        let reads = h.count("room.events")
        h.script.hold("!a")
        h.conversation.loadNewer()
        try await waitUntil { h.count("room.events") == reads + 1 }
        h.conversation.jumpToBottom()
        try await waitUntil { h.messageIDs().first == "$71" }
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 65).suffix(50).map { $0 },
                                    "before": ["ts": ConversationScript.timestamp(56), "seq": 56],
                                    "after": ["ts": ConversationScript.timestamp(105), "seq": 105]])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.messageIDs(), (71 ... 120).map { "$\($0)" })
        XCTAssertFalse(h.conversation.isLoadingNewer)
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        await stop(h)
    }

    func testNewMessagesWhileAwayDoNotMoveTheView() async throws {
        let h = try await start(["!a": history(200)])
        h.app.open(.message(roomID: "!a", eventID: "$100"))
        try await waitUntil { h.conversation.isLoaded }
        let items = h.conversation.items
        let scroll = h.conversation.scrollToMessageRequest

        h.script.add("!a", textEvent(id: "$201", room: "!a", at: 201))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$201"])
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$100"])
        h.server.notify(["kind": "read", "room_id": "!a", "event_id": "$100"])
        h.server.notify(["kind": "room", "room_id": "!a"])
        try await waitUntil { h.conversation.hasNewerWhileAway }
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(h.count("room.events"), 1, "no newest-page read while away")
        XCTAssertEqual(h.conversation.items, items, "nothing is spliced in and nothing moves")
        XCTAssertTrue(h.conversation.isAwayFromLatest)
        XCTAssertEqual(h.conversation.scrollToMessageRequest, scroll)
        XCTAssertEqual(h.count("room.markRead"), 0)

        // Jump to latest: the newest page, without the window, and read now.
        h.conversation.jumpToBottom()
        try await waitUntil { h.messageIDs().last == "$201" }
        XCTAssertEqual(h.messageIDs().first, "$152", "the window is dropped")
        XCTAssertEqual(Set(try XCTUnwrap(h.server.receivedParams("room.events").last).keys), ["room_id", "limit"])
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertFalse(h.conversation.hasNewerWhileAway)
        XCTAssertEqual(h.conversation.jumpToBottomRequest, 1, "the view scrolls down once the newest page is in")
        try await waitUntil { h.count("room.markRead") == 1 }
        await stop(h)
    }

    func testLoadNewerReachesTheLatestAndResumesLiveUpdates() async throws {
        let h = try await start(["!a": history(120)])
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertEqual(h.messageIDs().first, "$6")
        XCTAssertEqual(h.messageIDs().last, "$55")

        h.conversation.loadNewer()
        try await waitUntil { h.messageIDs().last == "$105" }
        let params = try XCTUnwrap(h.server.receivedParams("room.events").last)
        XCTAssertEqual(Set(params.keys), ["room_id", "after", "limit"])
        let after = try XCTUnwrap(params["after"] as? [String: Any])
        XCTAssertEqual(after["ts"] as? Int64, ConversationScript.timestamp(55), "the newest event of the window")
        XCTAssertEqual(after["seq"] as? Int64, 55)
        XCTAssertTrue(h.conversation.isAwayFromLatest)
        XCTAssertEqual(h.count("room.markRead"), 0)

        h.conversation.loadNewer()
        try await waitUntil { h.messageIDs().last == "$120" }
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertEqual(h.messageIDs(), (6 ... 120).map { "$\($0)" }, "the pages join without gaps or repeats")
        try await waitUntil { h.count("room.markRead") == 1 }

        let calls = h.count("room.events")
        h.conversation.loadNewer()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(h.count("room.events"), calls, "at the latest: nothing newer to read")

        // Live again: a new message reads the newest page, and the window's older part stays.
        h.script.add("!a", textEvent(id: "$121", room: "!a", at: 121))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$121"])
        try await waitUntil { h.messageIDs().last == "$121" }
        XCTAssertEqual(Set(try XCTUnwrap(h.server.receivedParams("room.events").last).keys), ["room_id", "limit"])
        XCTAssertEqual(h.messageIDs().first, "$6")

        // And older pages go on from the window's start.
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().first == "$1" }
        XCTAssertEqual(h.messageIDs(), (1 ... 121).map { "$\($0)" })
        XCTAssertFalse(h.conversation.hasOlder)
        await stop(h)
    }

    func testSendingReturnsToTheLatest() async throws {
        let h = try await start(["!a": history(120)])
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertTrue(h.conversation.isAwayFromLatest)

        h.conversation.composer.text = "On my way"
        await h.conversation.composer.submit()?.value
        XCTAssertEqual(h.server.receivedParams("message.send").first as? [String: String],
                       ["room_id": "!a", "text": "On my way"])
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$sent"])
        try await waitUntil { h.messageIDs().last == "$sent" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.messageIDs().filter { $0 == "$sent" }.count, 1, "the sent message shows once")
        XCTAssertEqual(h.messageIDs().suffix(2), ["$120", "$sent"])
        XCTAssertFalse(h.messageIDs().contains("$30"), "the newest messages, without the window")
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertNil(h.conversation.highlightedMessageID)
        try await waitUntil { h.conversation.jumpToBottomRequest == 1 }
        try await waitUntil { h.count("room.markRead") == 1 }
        await stop(h)
    }

    func testAReadForAChatLeftBehindLandsNowhere() async throws {
        let h = try await start(["!a": history(120), "!b": history(2, room: "!b")])

        // The page around a message in chat a is late; the person opens chat b meanwhile.
        h.script.hold("!a")
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.count("room.events") == 1 }
        h.app.selectedRoomID = "!b"
        try await waitUntil { h.messageIDs() == ["$1", "$2"] }
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 115).suffix(50).map { $0 },
                                    "before": ["ts": ConversationScript.timestamp(6), "seq": 6],
                                    "after": ["ts": ConversationScript.timestamp(55), "seq": 55]])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.messageIDs(), ["$1", "$2"])
        for case let .message(m) in h.conversation.items { XCTAssertEqual(m.roomID, "!b") }
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertNil(h.conversation.highlightedMessageID)
        XCTAssertNil(h.conversation.scrollToMessageRequest)

        // A newer page of chat a is late; the person closes the chat meanwhile.
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isAwayFromLatest }
        let reads = h.count("room.events")
        h.script.hold("!a")
        h.conversation.loadNewer()
        try await waitUntil { h.count("room.events") == reads + 1 }
        h.app.selectedRoomID = nil
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 65).suffix(50).map { $0 },
                                    "before": ["ts": ConversationScript.timestamp(56), "seq": 56],
                                    "after": ["ts": ConversationScript.timestamp(105), "seq": 105]])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(h.conversation.items.isEmpty)
        XCTAssertFalse(h.conversation.isLoaded)
        XCTAssertFalse(h.conversation.isLoadingNewer)
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertEqual(h.count("room.markRead"), 1, "only chat b was read")
        await stop(h)
    }

    func testTryAgainWhileAwayReadsTheWindowAgain() async throws {
        let h = try await start(["!a": history(120)])
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadNewer()
        try await waitUntil { h.messageIDs().last == "$105" }
        let serial = try XCTUnwrap(h.conversation.scrollToMessageRequest?.serial)

        h.conversation.reload()
        try await waitUntil { h.messageIDs().last == "$55" }
        let params = try XCTUnwrap(h.server.receivedParams("room.events").last)
        XCTAssertEqual(Set(params.keys), ["room_id", "around", "limit"])
        XCTAssertEqual(params["around"] as? String, "$30")
        XCTAssertEqual(h.messageIDs().first, "$6")
        XCTAssertTrue(h.conversation.isAwayFromLatest)
        XCTAssertGreaterThan(try XCTUnwrap(h.conversation.scrollToMessageRequest?.serial), serial)
        XCTAssertEqual(h.count("room.markRead"), 0)
        await stop(h)
    }

    func testTheNewDividerAfterAWindowCountsWhatCameWhileAway() async throws {
        let h = try await start(["!a": history(120)])
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadNewer()
        try await waitUntil { h.messageIDs().last == "$105" }

        // The last newer page is on its way when two messages come; the inbox counts them unread. The page
        // reaches the newest message it knew of, without them.
        let reads = h.count("room.events")
        h.script.hold("!a")
        h.conversation.loadNewer()
        try await waitUntil { h.count("room.events") == reads + 1 }
        h.script.add("!a", textEvent(id: "$121", room: "!a", at: 121))
        h.script.add("!a", textEvent(id: "$122", room: "!a", at: 122))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$122"])
        try await waitUntil { h.conversation.hasNewerWhileAway }
        h.unread.counts["!a"] = 2
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 17).suffix(15).map { $0 },
                                    "before": ["ts": ConversationScript.timestamp(106), "seq": 106],
                                    "after": NSNull()])
        try await waitUntil { h.messageIDs().last == "$122" }
        let ids = h.conversation.items.map(\.id)
        let divider = try XCTUnwrap(ids.firstIndex(of: "new"))
        XCTAssertEqual(ids[divider + 1], "$121", "above the two that came while away, not two higher")
        await stop(h)
    }

    func testJumpToAMessageInTheOpenChat() async throws {
        let h = try await start(["!a": history(120), "!b": history(2, room: "!b")])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        try await waitUntil { h.count("room.markRead") == 1 }
        h.conversation.reply(to: "$120")
        h.conversation.composer.text = "Half-written"

        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isAwayFromLatest }
        XCTAssertEqual(h.messageIDs().first, "$6")
        XCTAssertEqual(h.messageIDs().last, "$55")
        XCTAssertEqual(h.server.receivedParams("room.events").last?["around"] as? String, "$30")
        XCTAssertEqual(h.conversation.highlightedMessageID, "$30")
        let request = try XCTUnwrap(h.conversation.scrollToMessageRequest)
        XCTAssertEqual(request.messageID, "$30")
        XCTAssertEqual(h.conversation.composer.text, "Half-written", "the composer is not reopened")
        XCTAssertEqual(h.conversation.composer.replyTarget?.eventID, "$120")

        // The same message again is asked for again.
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { (h.conversation.scrollToMessageRequest?.serial ?? 0) > request.serial }
        XCTAssertEqual(h.conversation.scrollToMessageRequest?.messageID, "$30")

        // A chat result opens the chat as the inbox does: at the newest.
        h.app.open(.chat(roomID: "!b"))
        XCTAssertEqual(h.app.selectedRoomID, "!b")
        try await waitUntil { h.messageIDs() == ["$1", "$2"] }
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertNil(h.conversation.highlightedMessageID)
        XCTAssertEqual(Set(try XCTUnwrap(h.server.receivedParams("room.events").last).keys), ["room_id", "limit"])
        await stop(h)
    }

    func testHighlightClearsAfterThreeSeconds() async throws {
        XCTAssertEqual(ConversationModel.highlightDuration, .seconds(3))
        let time = FakeTime()
        let h = try await start(["!a": history(120)], time: time)
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.highlightedMessageID == "$30" }
        try await waitUntil { time.pendingSleeps == [3] }
        time.advance(2.9)
        await Task.yield()
        XCTAssertEqual(h.conversation.highlightedMessageID, "$30")
        time.advance(0.1)
        try await waitUntil { h.conversation.highlightedMessageID == nil }
        XCTAssertEqual(h.conversation.scrollToMessageRequest?.messageID, "$30", "only the tint goes")

        // A second jump has its own three seconds: the first one's end doesn't cut it short.
        h.app.open(.message(roomID: "!a", eventID: "$40"))
        try await waitUntil { h.conversation.highlightedMessageID == "$40" && time.pendingSleeps == [3] }
        time.advance(2)
        h.app.open(.message(roomID: "!a", eventID: "$45"))
        try await waitUntil { h.conversation.highlightedMessageID == "$45" && time.pendingSleeps == [3] }
        time.advance(1)
        await Task.yield()
        XCTAssertEqual(h.conversation.highlightedMessageID, "$45")
        time.advance(2)
        try await waitUntil { h.conversation.highlightedMessageID == nil }
        await stop(h)
    }

    func testMissingMessageOpensTheNewestPage() async throws {
        let h = try await start(["!a": history(3)])
        h.unread.counts["!a"] = 1
        h.app.open(.message(roomID: "!a", eventID: "$gone"))
        try await waitUntil { h.messageIDs() == ["$1", "$2", "$3"] }

        XCTAssertEqual(h.conversation.problem, .messageGone, "a calm notice, not an error")
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertNil(h.conversation.highlightedMessageID)
        XCTAssertNil(h.conversation.scrollToMessageRequest)
        let reads = h.server.receivedParams("room.events")
        XCTAssertEqual(reads.first?["around"] as? String, "$gone")
        XCTAssertEqual(Set(try XCTUnwrap(reads.last).keys), ["room_id", "limit"])
        XCTAssertTrue(h.conversation.items.contains { $0.id == "new" }, "opened as the newest page is")
        try await waitUntil { h.count("room.markRead") == 1 }

        // A new message doesn't take the notice away; another chat does.
        h.script.add("!a", textEvent(id: "$4", room: "!a", at: 4))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$4"])
        try await waitUntil { h.messageIDs().last == "$4" }
        XCTAssertEqual(h.conversation.problem, .messageGone)
        h.app.selectedRoomID = nil
        XCTAssertNil(h.conversation.problem)
        await stop(h)
    }

    func testAFailedNewestPageAfterAMissingMessageSaysOnlyThatItFailed() async throws {
        let h = try await start(["!a": history(3)])
        h.script.failNewest = true
        h.app.open(.message(roomID: "!a", eventID: "$gone"))
        try await waitUntil { h.conversation.problem == .loadFailed }

        // Try again reads the newest page; the old notice doesn't come back with it.
        h.script.failNewest = false
        h.conversation.reload()
        try await waitUntil { h.messageIDs() == ["$1", "$2", "$3"] }
        XCTAssertNil(h.conversation.problem)
        await stop(h)
    }

    // MARK: - Actions

    func testActionsSendOnlyDocumentedKeys() async throws {
        let h = try await start(["!a": history(2)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }

        await h.conversation.react(to: "$1", key: "❤️")
        await h.conversation.retry("$2")
        await h.conversation.discard("$2")
        XCTAssertEqual(h.server.receivedParams("message.react").first as? [String: String],
                       ["room_id": "!a", "event_id": "$1", "key": "❤️"])
        XCTAssertEqual(h.server.receivedParams("message.retry").first as? [String: String], ["event_id": "$2"])
        XCTAssertEqual(h.server.receivedParams("message.discard").first as? [String: String], ["event_id": "$2"])
        await stop(h)
    }

    func testTheQuickReactionsStartWithAHeart() {
        XCTAssertEqual(ConversationModel.quickReactions, ["❤️", "👍", "😂", "😮", "😢", "🙏"])
    }

    func testSendingThroughTheComposerReachesTheEngineWithTheReply() async throws {
        let h = try await start(["!a": history(2)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }

        h.conversation.reply(to: "$1")
        XCTAssertEqual(h.conversation.composer.replyTarget?.eventID, "$1")
        XCTAssertEqual(h.conversation.composer.replyTarget?.text, "Message 1")
        h.conversation.composer.text = "On my way"
        await h.conversation.composer.submit()?.value
        XCTAssertEqual(h.server.receivedParams("message.send").first as? [String: String],
                       ["room_id": "!a", "text": "On my way", "reply_to": "$1"])
        XCTAssertEqual(h.conversation.jumpToBottomRequest, 1, "sending scrolls to the newest message")
        await stop(h)
    }

    func testReplyToTheSelectedMessage() async throws {
        let h = try await start(["!a": history(2)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.replyToSelected()
        XCTAssertNil(h.conversation.composer.replyTarget, "nothing selected")
        h.conversation.selectedMessageID = "$2"
        h.conversation.replyToSelected()
        XCTAssertEqual(h.conversation.composer.replyTarget?.eventID, "$2")
        await stop(h)
    }
}

// MARK: - Fixtures

/// A text message as the engine writes it. `at` is the minute (and the engine's seq) it arrived.
func textEvent(id: String, room: String, at n: Int64, body: String? = nil, mine: Bool = false, status: String = "sent",
          reason: String = "") -> [String: Any] {
    [
        "event_id": id, "room_id": room, "sender": mine ? "@me:courier.local" : "@ann:example.test",
        "sender_name": mine ? "me" : "Ann", "sender_avatar_path": "", "mine": mine, "type": "m.room.message",
        "content": ["msgtype": "m.text", "body": body ?? "Message \(n)"], "ts": ConversationScript.timestamp(n),
        "seq": n, "status": status, "status_reason": reason, "media_path": "",
        "bookmarked": false, "poll": NSNull(), "thread": NSNull(), "expires_at": 0,
    ]
}

/// What the stand-in engine keeps for each chat, and pages out newest first as room.events does.
final class ConversationScript: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String: [[String: Any]]]
    private var held: Set<String> = []
    /// Deleted for me: paged as stored, then left out of the page, as the engine does.
    private var deletedForMe: Set<String> = []
    private var _failOlder = false
    private var _failNewest = false

    init(events: [String: [[String: Any]]]) { self.events = events }

    /// Minute n of an October afternoon, in milliseconds.
    static func timestamp(_ n: Int64) -> Int64 { 1_760_600_000_000 + n * 60_000 }

    /// room.events with a cursor fails while set.
    var failOlder: Bool {
        get { lock.withLock { _failOlder } }
        set { lock.withLock { _failOlder = newValue } }
    }

    /// room.events for the newest page (no cursor, no around) fails while set.
    var failNewest: Bool {
        get { lock.withLock { _failNewest } }
        set { lock.withLock { _failNewest = newValue } }
    }

    func add(_ room: String, _ event: [String: Any]) { lock.withLock { events[room, default: []].append(event) } }

    func replace(_ room: String, _ event: [String: Any]) {
        lock.withLock {
            events[room, default: []].removeAll { $0["event_id"] as? String == event["event_id"] as? String }
            events[room, default: []].append(event)
        }
    }

    func deleteForMe(_ ids: [String]) { lock.withLock { deletedForMe.formUnion(ids) } }

    func remove(_ room: String, _ id: String) {
        lock.withLock { events[room, default: []].removeAll { $0["event_id"] as? String == id } }
    }

    /// room.events for this chat is not answered until the test releases it.
    func hold(_ room: String) { lock.withLock { _ = held.insert(room) } }

    func newestFirst(_ room: String, limit: Int) -> [[String: Any]] {
        let all = lock.withLock { events[room] ?? [] }
        return Array(all.sorted { Self.key($0) > Self.key($1) }.prefix(limit))
    }

    private static func key(_ event: [String: Any]) -> (Int64, Int64) {
        (event["ts"] as? Int64 ?? 0, event["seq"] as? Int64 ?? 0)
    }

    func handle(_ method: String, _ params: [String: Any]?) -> TestEngineServer.Reply {
        switch method {
        case "hello": return TestEngineServer.helloOK
        case "accounts.list": return .result(["accounts": [[String: Any]]()])
        case "inbox.list": return .result(["rooms": [[String: Any]]()])
        case "room.events":
            guard let room = params?["room_id"] as? String else { return .error(code: -32602, message: "room_id") }
            if lock.withLock({ held.remove(room) != nil }) { return .later }
            if params?["before"] != nil, failOlder { return .error(code: -32603, message: "internal error") }
            if params?["before"] == nil, params?["after"] == nil, params?["around"] == nil, failNewest {
                return .error(code: -32603, message: "internal error")
            }
            let limit = params?["limit"] as? Int ?? 50
            if let around = params?["around"] as? String { return self.around(around, in: room, limit: limit) }
            if let after = params?["after"] as? [String: Any],
               let ts = (after["ts"] as? NSNumber)?.int64Value, let seq = (after["seq"] as? NSNumber)?.int64Value {
                return newer(than: (ts, seq), in: room, limit: limit)
            }
            var all = lock.withLock { events[room] ?? [] }.sorted { Self.key($0) > Self.key($1) }
            if let before = params?["before"] as? [String: Any],
               let ts = (before["ts"] as? NSNumber)?.int64Value, let seq = (before["seq"] as? NSNumber)?.int64Value {
                all = all.filter { Self.key($0) < (ts, seq) }
            }
            let page = Array(all.prefix(limit))
            var next: Any = NSNull()
            if all.count > limit, let last = page.last { next = ["ts": Self.key(last).0, "seq": Self.key(last).1] }
            let gone = lock.withLock { deletedForMe }
            let shown = page.filter { !gone.contains($0["event_id"] as? String ?? "") }
            return .result(["events": shown, "before": next, "after": NSNull()])
        case "message.send":
            // Stored as the engine stores it: mine, a minute after the chat's newest event.
            guard let room = params?["room_id"] as? String else { return .error(code: -32602, message: "room_id") }
            lock.withLock {
                let next = (events[room] ?? []).map { Self.key($0).1 }.max().map { $0 + 1 } ?? 1
                events[room, default: []].append(textEvent(id: "$sent", room: room, at: next,
                                                            body: params?["text"] as? String, mine: true))
            }
            return .result(["event_id": "$sent"])
        case "message.sendFile", "message.react":
            return .result(["event_id": "$sent"])
        default:
            return .result([String: Any]())
        }
    }

    private static func cursor(_ event: [String: Any]) -> [String: Any] {
        ["ts": key(event).0, "seq": key(event).1]
    }

    /// room.events around: the event in the middle, a little more of the rest newer than older, and the other
    /// side filling the page near either end (as the engine's EventsAround does).
    private func around(_ id: String, in room: String, limit: Int) -> TestEngineServer.Reply {
        let all = lock.withLock { events[room] ?? [] }.sorted { Self.key($0) < Self.key($1) }
        guard let index = all.firstIndex(where: { $0["event_id"] as? String == id }) else {
            return .error(code: -32020, message: "no such chat or message")
        }
        let rest = limit - 1
        var older = min(rest / 2, index)
        let newer = min(rest - older, all.count - 1 - index)
        older = min(rest - newer, index)
        let page = Array(all[(index - older) ... (index + newer)])
        let before: Any = index - older > 0 ? Self.cursor(page[0]) : NSNull()
        let after: Any = index + newer < all.count - 1 ? Self.cursor(page[page.count - 1]) : NSNull()
        return .result(["events": Array(page.reversed()), "before": before, "after": after])
    }

    /// room.events after: the `limit` events just newer than the cursor, newest first.
    private func newer(than key: (Int64, Int64), in room: String, limit: Int) -> TestEngineServer.Reply {
        let all = lock.withLock { events[room] ?? [] }.sorted { Self.key($0) < Self.key($1) }.filter { Self.key($0) > key }
        let page = Array(all.prefix(limit))
        let before: Any = page.first.map(Self.cursor) ?? NSNull()
        let after: Any = all.count > limit ? Self.cursor(page[page.count - 1]) : NSNull()
        return .result(["events": Array(page.reversed()), "before": before, "after": after])
    }
}

extension TestEngineServer {
    /// Answers the requests for `method` about this room that the handler held.
    func releaseHeld(method: String, room: String, with result: Any) {
        for request in received where request["method"] as? String == method {
            let params = request["params"] as? [String: Any]
            if params?["room_id"] as? String == room, let id = request["id"] as? Int { reply(to: id, with: result) }
        }
    }
}
