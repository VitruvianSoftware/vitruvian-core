// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The notification coordinator against a stand-in engine and a fake notification centre: live events notify once,
/// backfill and the chat in front do not, and the buttons on a notification reach the engine.
@MainActor
final class NotificationCoordinatorTests: XCTestCase {
    private var servers: [TestEngineServer] = []

    override func tearDown() async throws {
        for server in servers { server.stop() }
        servers = []
        for store in defaultsStores { store.remove() }
        defaultsStores = []
    }

    /// The moment the app connects, in ms.
    private let connectedMillis: Int64 = 2_000_000

    private struct Harness {
        let script: NotificationScript
        let server: TestEngineServer
        let app: AppModel
        let delivery: FakeDelivery
        let coordinator: NotificationCoordinator
        let clock: FakeClock
        let window: WindowState
        let preferences: InboxPreferences
        /// The settings store the coordinator keeps what it told in.
        let defaults: UserDefaults
    }

    /// Mutable things the coordinator asks about, which the app's views own.
    @MainActor
    final class WindowState {
        var isKey = false
        /// The open chat shows older history, away from its newest message.
        var isAway = false
        /// Incognito is on (`ConversationModel.incognitoIsOn`).
        var incognito = false
        var shown = 0
        var drafts: [(room: String, text: String, mayHaveBeenSent: Bool)] = []
        var rows: [String: InboxRow] = ["!a": inboxRow("!a", name: "Chat A")]
    }

    /// A settings store of its own, removed when the test ends.
    private var defaultsStores: [TestDefaults] = []

    private func start(connected: Bool = true, window gather: TimeInterval = 0.02,
                       replyTimeout: TimeInterval? = nil,
                       entitlement: any EntitlementProvider = AlwaysEntitled(),
                       defaults: UserDefaults? = nil,
                       scheduled: [String: [[String: Any]]] = [:]) async throws -> Harness {
        let script = NotificationScript()
        script.scheduled = scheduled
        let server = try TestEngineServer(handler: script.handle)
        servers.append(server)
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:], launcher: launcher,
            credentials: InMemoryCredentialStore(), clientName: "Courier/test", timing: FakeTime().timing())
        let clock = FakeClock(millis: connectedMillis)
        let app = AppModel(supervisor: supervisor, clock: { clock.date })
        let delivery = FakeDelivery()
        let window = WindowState()
        let store = TestDefaults()
        defaultsStores.append(store)
        let preferences = InboxPreferences(defaults: store.defaults)
        let coordinator = NotificationCoordinator(
            appModel: app, delivery: delivery, row: { window.rows[$0] }, isLooking: { window.isKey },
            isAwayFromLatest: { window.isAway }, isIncognito: { window.incognito },
            restoreDraft: { window.drafts.append(($0, $1, $2)) }, showWindow: { window.shown += 1 },
            preferences: preferences, entitlement: entitlement,
            window: gather, replyTimeout: replyTimeout, clock: { clock.date }, defaults: defaults ?? store.defaults)
        if connected {
            app.start()
            try await waitUntil { app.client != nil }
        }
        return Harness(script: script, server: server, app: app, delivery: delivery, coordinator: coordinator,
                       clock: clock, window: window, preferences: preferences, defaults: defaults ?? store.defaults)
    }

    private func finish(_ h: Harness) async { await h.app.stop() }

    /// Lets a fetch that should lead to nothing finish before the test says nothing happened.
    private func settle(_ h: Harness, fetches: Int = 1) async throws {
        try await waitUntil { h.server.receivedMethods().filter { $0 == "room.events" }.count >= fetches }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - Someone starts typing

    /// "Notify when someone starts typing" (Inferred (inventory 02 §1.5)): one notification per burst per chat, read
    /// from the chat's row as the engine has it; the message that follows takes its place in the chat's stack, and a
    /// burst that ends without one takes it down. Never while the setting is off, nor for the chat in front.
    func testOneTypingNotificationPerBurstReplacedByTheMessage() async throws {
        let h = try await start()
        h.preferences.typingNotifications = true
        h.clock.advance(seconds: 5)
        func typing(_ names: [String]) -> [[String: Any]] {
            var row = inboxRowJSON("!a", name: "Chat A")
            row["typing"] = names
            return [row]
        }
        let typingID = NotificationPolicy.typingID(roomID: "!a")
        var changes = 0
        func typingChange(_ names: [String]) async throws {
            h.script.rooms = typing(names)
            changes += 1
            h.server.notify(["kind": "typing", "room_id": "!a"])
            try await waitUntil { h.coordinator.typingChangesHandled == changes }
        }

        try await typingChange(["Sam"])
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["Sam is typing…"])
        XCTAssertEqual(h.delivery.delivered.first?.title, "Chat A")
        XCTAssertEqual(h.delivery.delivered.first?.category, .typing)
        XCTAssertEqual(h.delivery.delivered.first?.eventID, typingID)

        // Someone else starts too: the same burst, no second notification.
        try await typingChange(["Sam", "Ann"])
        XCTAssertEqual(h.delivery.delivered.count, 1)

        // The message comes: the typing notification goes, then the message's own shows, in the same stack.
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 3000, text: "here it is")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await waitUntil { h.delivery.delivered.count == 2 }
        XCTAssertEqual(h.delivery.log, ["deliver \(typingID)", "remove \(typingID)", "deliver $1"])
        XCTAssertEqual(h.delivery.delivered.last?.threadIdentifier, h.delivery.delivered.first?.threadIdentifier)

        // They stop: nothing is left to take down.
        try await typingChange([])
        XCTAssertEqual(h.delivery.removed, [typingID])

        // A new burst is news again; one that ends with no message takes its notification down.
        try await typingChange(["Sam"])
        XCTAssertEqual(h.delivery.delivered.count, 3)
        try await typingChange([])
        XCTAssertEqual(h.delivery.removed, [typingID, typingID])

        // The chat the person is looking at: none.
        h.app.selectedRoomID = "!a"
        h.window.isKey = true
        try await typingChange(["Sam"])
        XCTAssertEqual(h.delivery.delivered.count, 3)
        try await typingChange([])
        h.window.isKey = false

        // The setting off: none, and the chat isn't even read for it.
        h.preferences.typingNotifications = false
        let reads = h.server.receivedMethods().filter { $0 == "inbox.list" }.count
        try await typingChange(["Sam"])
        XCTAssertEqual(h.delivery.delivered.count, 3)
        XCTAssertEqual(h.server.receivedMethods().filter { $0 == "inbox.list" }.count, reads)
        await finish(h)
    }

    /// A typing read that was on its way when their message came is dropped: "is typing…" never shows after the
    /// message it was about. The order is the test's: the read is held until the message has been told.
    func testATypingAnswerOvertakenByTheMessageIsDropped() async throws {
        let h = try await start()
        h.preferences.typingNotifications = true
        h.clock.advance(seconds: 5)
        var row = inboxRowJSON("!a", name: "Chat A")
        row["typing"] = ["Sam"]
        h.script.rooms = [row]
        h.script.hold("inbox.list")
        h.server.notify(["kind": "typing", "room_id": "!a"])
        try await waitUntil { h.server.receivedMethods().contains("inbox.list") }

        h.script.events["!a"] = [message("$1", ts: connectedMillis + 3000, text: "here it is")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await waitUntil { h.delivery.delivered.count == 1 }

        // The typing read answers now, with the list as it was before the message.
        h.server.releaseHeld(method: "inbox.list", with: ["rooms": [row], "next_cursor": NSNull()])
        try await waitUntil { h.coordinator.typingChangesHandled == 1 }
        XCTAssertEqual(h.delivery.delivered.map(\.eventID), ["$1"], "no typing notification after the message")

        // A typing change after the message is a new burst, and tells as usual.
        h.server.notify(["kind": "typing", "room_id": "!a"])
        try await waitUntil { h.coordinator.typingChangesHandled == 2 }
        XCTAssertEqual(h.delivery.delivered.map(\.eventID), ["$1", NotificationPolicy.typingID(roomID: "!a")])
        await finish(h)
    }

    // MARK: - Live events

    func testALiveEventNotifiesOnce() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 3000, text: "hello")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(h.delivery.delivered[0].title, "Chat A")
        XCTAssertEqual(h.delivery.delivered[0].body, "hello")
        XCTAssertEqual(h.delivery.delivered[0].roomID, "!a")

        // The same event again (a status change, a second notification) does not notify again.
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await settle(h, fetches: 2)
        XCTAssertEqual(h.delivery.delivered.count, 1)

        let fetch = h.server.receivedParams("room.events").first
        XCTAssertEqual(fetch?["room_id"] as? String, "!a")
        XCTAssertEqual(fetch?["limit"] as? Int, 10)
        await finish(h)
    }

    func testBackfilledEventsDoNotNotify() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        // The first sync's history: older than the connection, in a burst of changes.
        h.script.events["!a"] = (1 ... 10).map { message("$old\($0)", ts: connectedMillis - Int64($0) * 60_000, text: "old") }
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$old1"])
        try await settle(h)
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        await finish(h)
    }

    func testEachNewEventInAPageNotifiesOldestFirst() async throws {
        let h = try await start()
        h.clock.advance(seconds: 10)
        // room.events is newest first.
        h.script.events["!a"] = [
            message("$3", ts: connectedMillis + 3000, text: "third"),
            message("$2", ts: connectedMillis + 2000, text: "second"),
            message("$1", ts: connectedMillis + 1000, text: "first"),
        ]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { h.delivery.delivered.count == 3 }
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["first", "second", "third"])
        await finish(h)
    }

    func testYourOwnMessagesAndMutedChatsAreSilent() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 1000, text: "mine", mine: true)]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await settle(h)
        XCTAssertTrue(h.delivery.delivered.isEmpty)

        h.window.rows["!a"] = inboxRow("!a", name: "Chat A", muted: true)
        h.script.events["!a"] = [message("$2", ts: connectedMillis + 2000, text: "theirs")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$2"])
        try await settle(h, fetches: 2)
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        await finish(h)
    }

    func testTheChatInFrontIsSilentAndStaysSilentLater() async throws {
        let h = try await start()
        h.window.rows["!b"] = inboxRow("!b", name: "Chat B")
        h.clock.advance(seconds: 5)
        h.app.selectedRoomID = "!a"
        h.window.isKey = true
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 1000, text: "you are looking at me")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await settle(h)
        XCTAssertTrue(h.delivery.delivered.isEmpty)

        // Another chat does notify while the window is key.
        h.script.events["!b"] = [message("$b1", ts: connectedMillis + 2000, text: "elsewhere", room: "!b")]
        h.server.notify(["kind": "event", "room_id": "!b", "event_id": "$b1"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(h.delivery.delivered[0].title, "Chat B")

        // The person looks away; the next event in the first chat brings only itself, not the one already seen.
        h.window.isKey = false
        h.script.events["!a"] = [
            message("$2", ts: connectedMillis + 3000, text: "now"),
            message("$1", ts: connectedMillis + 1000, text: "you are looking at me"),
        ]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$2"])
        try await waitUntil { h.delivery.delivered.count == 2 }
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["elsewhere", "now"])
        await finish(h)
    }

    func testAChatTheInboxHasNotListedYetIsLookedUp() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        h.window.rows = [:]
        h.script.rooms = [inboxRowJSON("!new", name: "New Chat")]
        h.script.events["!new"] = [message("$1", ts: connectedMillis + 1000, text: "first words", room: "!new")]
        h.server.notify(["kind": "event", "room_id": "!new", "event_id": "$1"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(h.delivery.delivered[0].title, "New Chat")
        await finish(h)
    }

    func testALiveMessageInAChatThatCannotNotifyStaysSilent() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        let silent: [InboxRow] = [
            inboxRow("!a", name: "Chat A", mutedBy: .label), inboxRow("!a", name: "Chat A", mutedBy: .account),
            inboxRow("!a", name: "Chat A", lowPriority: true), inboxRow("!a", name: "Chat A", hidden: true),
        ]
        for (number, chat) in silent.enumerated() {
            h.window.rows["!a"] = chat
            h.script.events["!a"] = [message("$s\(number)", ts: connectedMillis + 1000, text: "quiet")]
            h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$s\(number)"])
            try await settle(h, fetches: number + 1)
        }
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        await finish(h)
    }

    func testTheRequestSettingIsReadWhenAMessageIsDecided() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        h.window.rows["!a"] = inboxRow("!a", name: "Chat A", request: true)
        h.preferences.requestNotifications = false
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 1000, text: "hello?")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await settle(h)
        XCTAssertTrue(h.delivery.delivered.isEmpty)

        h.preferences.requestNotifications = true
        h.script.events["!a"] = [message("$2", ts: connectedMillis + 2000, text: "anyone there?")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$2"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(h.delivery.delivered[0].body, "anyone there?")
        XCTAssertEqual(h.delivery.delivered[0].category, .message)
        await finish(h)
    }

    func testNothingNotifiesBeforeTheAppHasConnected() async throws {
        let h = try await start(connected: false)
        // No engine yet, so no client and no connection time: nothing to read from.
        h.coordinator.handle(.event(roomID: "!a", eventID: "$1"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        await finish(h)
    }

    // MARK: - Reading a chat clears its notifications

    func testReadingAChatClearsItsNotifications() async throws {
        let h = try await start()
        h.server.notify(["kind": "read", "room_id": "!a"])
        try await waitUntil { h.delivery.cleared == ["!a"] }
        await finish(h)
    }

    // MARK: - Reminders

    func testReminderNotifiesEvenWhenMuted() async throws {
        let h = try await start()
        // Muted by a label, and low priority and hidden besides: a reminder is something the person asked for.
        h.window.rows["!a"] = inboxRow("!a", name: "Chat A", muted: true, lowPriority: true, hidden: true,
                                       mutedBy: .label)
        h.server.notify(["kind": "reminder", "room_id": "!a"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(h.delivery.delivered[0].title, "Chat A")
        XCTAssertEqual(h.delivery.delivered[0].body, "You asked to be reminded about this chat.")
        XCTAssertEqual(h.delivery.delivered[0].roomID, "!a")
        XCTAssertEqual(h.delivery.delivered[0].category, .reminder)

        // Once per change: the room change that comes with it notifies nothing more.
        h.server.notify(["kind": "room", "room_id": "!a"])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.delivery.delivered.count, 1)
        XCTAssertFalse(h.server.receivedMethods().contains("room.events"), "a reminder reads no messages")
        await finish(h)
    }

    func testReminderForAChatTheInboxHasNotListedIsLookedUpByItsID() async throws {
        let h = try await start()
        h.window.rows = [:]
        h.script.rooms = [inboxRowJSON("!far", name: "Far Down"), inboxRowJSON("!other", name: "Other")]
        h.server.notify(["kind": "reminder", "room_id": "!far"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(h.delivery.delivered[0].title, "Far Down")
        let lookups = h.server.receivedParams("inbox.list")
        XCTAssertEqual(lookups.count, 1)
        XCTAssertEqual(lookups[0]["room_ids"] as? [String], ["!far"])
        XCTAssertEqual(lookups[0].count, 1, "room_ids alone: never a read of the whole inbox")

        // A chat the engine doesn't have says nothing: there is no name to show.
        h.server.notify(["kind": "reminder", "room_id": "!gone"])
        try await waitUntil { h.server.receivedParams("inbox.list").count == 2 }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.delivery.delivered.count, 1)
        await finish(h)
    }

    func testRemindInOneAndEightHours() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        let now = connectedMillis + 5000

        await h.coordinator.remind(roomID: "!a", after: NotificationCoordinator.remindOneHour)
        h.clock.advance(seconds: 90)
        h.preferences.remindDefault = .always
        await h.coordinator.remind(roomID: "!b", after: NotificationCoordinator.remindEightHours)

        XCTAssertEqual(NotificationCoordinator.remindOneHour, 3600)
        XCTAssertEqual(NotificationCoordinator.remindEightHours, 28800)
        let calls = h.server.receivedParams("reminder.set")
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0]["room_ids"] as? [String], ["!a"])
        XCTAssertEqual(calls[0]["due_at"] as? Int64, now + 3_600_000, "exact against the clock, not the call's own time")
        XCTAssertEqual(calls[0]["condition"] as? String, "if_no_reply", "the setting's default when it was pressed")
        XCTAssertEqual(calls[1]["room_ids"] as? [String], ["!b"])
        XCTAssertEqual(calls[1]["due_at"] as? Int64, now + 90_000 + 28_800_000)
        XCTAssertEqual(calls[1]["condition"] as? String, "always")
        XCTAssertNil(calls[0]["archive"], "the notification button sets a reminder and nothing else")
        await finish(h)
    }

    func testRemindingWithoutThePlanCallsNothing() async throws {
        struct NoReminders: EntitlementProvider {
            func isEntitled(_ feature: Feature) -> Bool { feature != .reminders }
        }
        let h = try await start(entitlement: NoReminders())
        await h.coordinator.remind(roomID: "!a", after: NotificationCoordinator.remindOneHour)
        XCTAssertFalse(h.server.receivedMethods().contains("reminder.set"))
        await finish(h)
    }

    /// Ruling 37: a reminder for the chat the person is reading is silent, and the chat is marked read, which ends
    /// the reminder and its unread mark as opening the chat would have.
    func testAReminderForTheChatYouAreReadingIsSilent() async throws {
        let h = try await start()
        h.window.rows["!b"] = inboxRow("!b", name: "Chat B")
        h.app.selectedRoomID = "!a"
        h.window.isKey = true
        h.server.notify(["kind": "reminder", "room_id": "!a"])
        h.server.notify(["kind": "reminder", "room_id": "!b"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(h.delivery.delivered[0].roomID, "!b", "another chat's reminder still comes")
        try await waitUntil { !h.server.receivedParams("room.markRead").isEmpty }
        XCTAssertEqual(h.server.receivedParams("room.markRead").map { $0["room_id"] as? String }, ["!a"],
                       "the chat being read is marked read; the other one isn't")

        // Open but not looked at (the window is not key, the screen is locked): it does come.
        h.window.isKey = false
        h.server.notify(["kind": "reminder", "room_id": "!a"])
        try await waitUntil { h.delivery.delivered.count == 2 }
        XCTAssertEqual(h.delivery.delivered[1].roomID, "!a")
        XCTAssertEqual(h.server.receivedParams("room.markRead").count, 1, "not looked at: notified, not marked read")
        await finish(h)
    }

    /// Ruling 27: a reminder for the chat being read, while it shows an older part of its history (opened at a
    /// search result), ends the reminder and marks nothing read: the newest messages haven't been seen.
    func testAReminderForAChatShownAwayFromItsNewestOnlyEndsTheReminder() async throws {
        let h = try await start()
        h.app.selectedRoomID = "!a"
        h.window.isKey = true
        h.window.isAway = true
        h.server.notify(["kind": "reminder", "room_id": "!a"])
        try await waitUntil { !h.server.receivedParams("reminder.clear").isEmpty }
        XCTAssertEqual(h.server.receivedParams("reminder.clear").first?["room_ids"] as? [String], ["!a"])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(h.server.receivedParams("room.markRead").isEmpty, "the newer messages stay unread")
        XCTAssertTrue(h.delivery.delivered.isEmpty, "the person is in the chat: no notification")
        XCTAssertTrue(h.delivery.cleared.isEmpty, "nothing was read, so nothing shown is taken down")

        // Back at the newest messages: marked read, as before.
        h.window.isAway = false
        h.server.notify(["kind": "reminder", "room_id": "!a"])
        try await waitUntil { h.server.receivedParams("room.markRead").count == 1 }
        XCTAssertEqual(h.server.receivedParams("reminder.clear").count, 1)
        await finish(h)
    }

    /// Incognito's promise: a reminder for the chat being read ends the reminder and reads nothing, as when the chat
    /// shows older history. No receipt goes.
    func testAReminderForTheChatYouAreReadingInIncognitoOnlyEndsTheReminder() async throws {
        let h = try await start()
        h.app.selectedRoomID = "!a"
        h.window.isKey = true
        h.window.incognito = true
        h.server.notify(["kind": "reminder", "room_id": "!a"])
        try await waitUntil { !h.server.receivedParams("reminder.clear").isEmpty }
        XCTAssertEqual(h.server.receivedParams("reminder.clear").first?["room_ids"] as? [String], ["!a"])
        // One branch or the other: reminder.clear came, so room.markRead never will for this reminder.
        XCTAssertTrue(h.server.receivedParams("room.markRead").isEmpty, "Incognito: nothing is marked read")
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        XCTAssertTrue(h.delivery.cleared.isEmpty)
        await finish(h)
    }

    // MARK: - The buttons

    func testClickingOpensTheChatAndTheWindow() async throws {
        let h = try await start()
        h.coordinator.open(roomID: "!a")
        XCTAssertEqual(h.app.selectedRoomID, "!a")
        XCTAssertEqual(h.window.shown, 1)
        await finish(h)
    }

    func testMarkAsReadTellsTheEngineAndClears() async throws {
        let h = try await start()
        await h.coordinator.markRead(roomID: "!a")
        XCTAssertEqual(h.server.receivedParams("room.markRead").first?["room_id"] as? String, "!a")
        XCTAssertEqual(h.delivery.cleared, ["!a"])
        await finish(h)
    }

    func testReplySendsTheTypedText() async throws {
        let h = try await start()
        await h.coordinator.reply(roomID: "!a", text: "  on my way  ")
        let sent = h.server.receivedParams("message.send")
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["room_id"] as? String, "!a")
        XCTAssertEqual(sent.first?["text"] as? String, "on my way")

        await h.coordinator.reply(roomID: "!a", text: "   ")
        XCTAssertEqual(h.server.receivedParams("message.send").count, 1, "an empty reply sends nothing")
        await finish(h)
    }

    func testAReplyWithNoEngineWaitsInTheChat() async throws {
        let h = try await start(connected: false)
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertEqual(h.window.drafts.map(\.room), ["!a"])
        XCTAssertEqual(h.window.drafts.map(\.text), ["on my way"])
        XCTAssertEqual(h.window.drafts.map(\.mayHaveBeenSent), [false])
        XCTAssertEqual(h.delivery.delivered.count, 1)
        XCTAssertEqual(h.delivery.delivered[0].title, "Chat A")
        XCTAssertEqual(h.delivery.delivered[0].body, "Your reply wasn’t sent — it’s waiting in the chat.")
        XCTAssertEqual(h.delivery.delivered[0].roomID, "!a", "a click opens that chat")
        XCTAssertEqual(h.delivery.delivered[0].threadIdentifier, "!a")
    }

    func testAReplyTheEngineRefusesWaitsInTheChat() async throws {
        let h = try await start()
        h.script.failSend = true
        await h.coordinator.reply(roomID: "!a", text: "  on my way ")
        XCTAssertEqual(h.window.drafts.map(\.text), ["on my way"])
        XCTAssertEqual(h.window.drafts.map(\.mayHaveBeenSent), [false])
        XCTAssertEqual(h.delivery.delivered.map(\.roomID), ["!a"])
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["Your reply wasn’t sent — it’s waiting in the chat."])
        await finish(h)
    }

    func testAReplyThatTimedOutSaysItMayHaveGone() async throws {
        let h = try await start(replyTimeout: 0.2)
        h.script.hold("message.send") // the engine never answers
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertEqual(h.window.drafts.map(\.text), ["on my way"])
        XCTAssertEqual(h.window.drafts.map(\.mayHaveBeenSent), [true], "the draft carries the may-have-been-sent notice")
        XCTAssertEqual(h.delivery.delivered.count, 1)
        XCTAssertEqual(h.delivery.delivered[0].title, "Chat A")
        XCTAssertEqual(h.delivery.delivered[0].body,
                       "Your reply may not have been sent — check the chat before sending again.")
        XCTAssertEqual(h.delivery.delivered[0].roomID, "!a", "a click opens that chat")
        XCTAssertEqual(h.delivery.delivered[0].threadIdentifier, "!a")
        await finish(h)
    }

    func testAReplyThatWasSentLeavesNothingBehind() async throws {
        let h = try await start()
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertTrue(h.window.drafts.isEmpty)
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        await finish(h)
    }

    /// A reply from a notification reads the chat, as any reply does (the networks mark it read on a reply anyway),
    /// whether or not it is open, and in Incognito too ("until I reply"); its notifications come down. Only a reply
    /// that went: message.send also answers for one the network refused (failed) and, at once, for one that waits.
    func testAReplyFromANotificationReadsTheChatOnlyOnceItWent() async throws {
        let h = try await start()
        h.window.incognito = true
        func stored(_ status: String) {
            var event = message("$sent", ts: connectedMillis + 1000, text: "on my way", mine: true)
            event["status"] = status
            h.script.events["!a"] = [event]
        }

        stored("failed")
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertEqual(h.server.receivedParams("room.events").last?["around"] as? String, "$sent",
                       "the reply's own event is looked at")
        XCTAssertTrue(h.server.receivedParams("room.markRead").isEmpty, "refused: not read")
        XCTAssertTrue(h.delivery.cleared.isEmpty)

        stored("waiting")
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertTrue(h.server.receivedParams("room.markRead").isEmpty, "waiting to go: not read")
        XCTAssertTrue(h.delivery.cleared.isEmpty)

        stored("sent")
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertEqual(h.server.receivedParams("room.markRead").map { $0["room_id"] as? String }, ["!a"])
        XCTAssertEqual(h.delivery.cleared, ["!a"])

        h.script.failSend = true
        await h.coordinator.reply(roomID: "!a", text: "again")
        XCTAssertEqual(h.server.receivedParams("room.markRead").count, 1, "not sent: not read")
        await finish(h)
    }

    // MARK: - A burst of changes

    func testABurstOfEventsInOneChatReadsItAtMostTwice() async throws {
        let h = try await start(window: 0.3)
        h.clock.advance(seconds: 5)
        h.script.events["!a"] = (1 ... 50).reversed().map {
            message("$\($0)", ts: connectedMillis + Int64($0), text: "m\($0)")
        }
        for number in 1 ... 50 { h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$\(number)"]) }
        // Ten come back for each read; the burst's last ten are announced.
        try await waitUntil { h.delivery.delivered.count >= 10 }
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertLessThanOrEqual(h.server.receivedMethods().filter { $0 == "room.events" }.count, 2)
        await finish(h)
    }

    func testABurstForAChatTheInboxHasNotListedReadsTheInboxAtMostTwice() async throws {
        let h = try await start(window: 0.3)
        h.clock.advance(seconds: 5)
        h.window.rows = [:]
        h.script.rooms = [inboxRowJSON("!new", name: "New Chat")]
        h.script.events["!new"] = [message("$1", ts: connectedMillis + 1000, text: "hi", room: "!new")]
        for number in 1 ... 50 { h.server.notify(["kind": "event", "room_id": "!new", "event_id": "$\(number)"]) }
        try await waitUntil { h.delivery.delivered.count == 1 }
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertLessThanOrEqual(h.server.receivedMethods().filter { $0 == "inbox.list" }.count, 2)
        await finish(h)
    }

    func testEachUnlistedChatIsLookedUpByItsID() async throws {
        let h = try await start(window: 0.1)
        h.clock.advance(seconds: 5)
        h.window.rows = [:]
        let ids = (1 ... 5).map { "!n\($0)" }
        h.script.rooms = ids.map { inboxRowJSON($0, name: "Chat \($0)") }
        for id in ids {
            h.script.events[id] = [message("$\(id)", ts: connectedMillis + 1000, text: "hi", room: id)]
            h.server.notify(["kind": "event", "room_id": id, "event_id": "$\(id)"])
        }
        try await waitUntil { h.delivery.delivered.count == 5 }
        XCTAssertEqual(Set(h.delivery.delivered.map(\.title)), Set(ids.map { "Chat \($0)" }))
        // One lookup per chat, by its id: the inbox pages now, so a whole-inbox read may not hold the chat.
        let lookups = h.server.receivedParams("inbox.list")
        XCTAssertEqual(lookups.count, 5)
        XCTAssertEqual(Set(lookups.compactMap { ($0["room_ids"] as? [String])?.first }), Set(ids))
        XCTAssertTrue(lookups.allSatisfy { $0.count == 1 && ($0["room_ids"] as? [String])?.count == 1 })
        await finish(h)
    }

    func testAChatTheEngineDoesNotHaveIsNotAnnounced() async throws {
        let h = try await start(window: 0.02)
        h.clock.advance(seconds: 5)
        h.window.rows = [:]
        h.script.events["!gone"] = [message("$g", ts: connectedMillis + 1000, text: "hello", room: "!gone")]
        h.server.notify(["kind": "event", "room_id": "!gone", "event_id": "$g"])
        try await waitUntil { h.server.receivedMethods().contains("inbox.list") }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(h.delivery.delivered.isEmpty, "no row, so no name to show: nothing is announced")
        await finish(h)
    }

    func testAChangeWhileTheChatIsBeingReadMakesExactlyOneFollowUpRead() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        h.script.hold("room.events")
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 1000, text: "one")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await waitUntil { h.server.receivedMethods().contains("room.events") }

        // Two more changes while that read is in flight.
        h.script.events["!a"] = [
            message("$3", ts: connectedMillis + 3000, text: "three"), message("$2", ts: connectedMillis + 2000, text: "two"),
            message("$1", ts: connectedMillis + 1000, text: "one"),
        ]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$2"])
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(h.server.receivedMethods().filter { $0 == "room.events" }.count, 1, "nothing new is read while it is in flight")

        // The held read answers with what the engine had when it was asked.
        let held = h.server.received.first { $0["method"] as? String == "room.events" }
        h.server.reply(to: held?["id"] as? Int ?? -1, with: [
            "events": [message("$1", ts: connectedMillis + 1000, text: "one")], "before": NSNull(), "after": NSNull(),
        ])
        try await waitUntil { h.delivery.delivered.count == 3 }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(h.server.receivedMethods().filter { $0 == "room.events" }.count, 2, "exactly one follow-up read")
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["one", "two", "three"], "each announced once")
        await finish(h)
    }

    func testAChangeDuringAReadIsReadOnceMoreAndNotAnnouncedTwice() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 1000, text: "one")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        h.script.events["!a"] = [
            message("$2", ts: connectedMillis + 2000, text: "two"), message("$1", ts: connectedMillis + 1000, text: "one"),
        ]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$2"])
        try await waitUntil { h.delivery.delivered.count == 2 }
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["one", "two"])
        await finish(h)
    }

    // MARK: - Deleted before it was seen

    func testAMessageDeletedBeforeItWasAnnouncedIsSilent() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        let redaction: [String: Any] = [
            "event_id": "$r", "room_id": "!a", "sender": "@other:courier.local", "sender_name": "Sam",
            "sender_avatar_path": "", "mine": false, "type": "m.room.redaction", "content": ["redacts": "$1"],
            "ts": connectedMillis + 2000, "seq": 2, "status": "sent", "status_reason": "", "media_path": "",
            "bookmarked": false, "poll": NSNull(), "thread": NSNull(), "expires_at": 0,
            "delivered": false, "read_by": [[String: Any]](),
        ]
        h.script.events["!a"] = [redaction, message("$1", ts: connectedMillis + 1000, text: "oops")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$r"])
        try await settle(h)
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        await finish(h)
    }

    // MARK: - Send later

    /// Review Focus 3: a scheduled message that was canceled (they wrote first) or missed (Courier was closed) is told
    /// once, however often its chat's list is read again, and not again after Courier restarts. One rescheduled and
    /// then canceled again is a new event, and is told.
    func testCanceledAndMissedScheduledNotifyOnce() async throws {
        let h = try await start()
        // On connect every chat's list is read: nothing to tell.
        try await waitUntil { h.coordinator.scheduledReads == 1 }
        XCTAssertEqual(dicts(h.server.receivedParams("scheduled.list")), dicts([[:]]), "every chat's, at connect")

        h.script.scheduled["!a"] = [scheduledJSON(1, room: "!a", due: 2000)]
        h.server.notify(["kind": "scheduled", "room_id": "!a"])
        try await waitUntil { h.coordinator.scheduledReads == 2 }
        XCTAssertTrue(h.delivery.delivered.isEmpty, "a message still waiting is nothing to tell")
        XCTAssertEqual(h.server.receivedParams("scheduled.list").last?["room_id"] as? String, "!a")

        h.script.scheduled["!a"] = [scheduledJSON(1, room: "!a", due: 2000, state: "canceled")]
        h.server.notify(["kind": "scheduled", "room_id": "!a"])
        h.server.notify(["kind": "scheduled", "room_id": "!a"])
        h.server.notify(["kind": "scheduled", "room_id": "!a"])
        try await waitUntil { h.coordinator.scheduledReads == 5 }
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["A scheduled message to Chat A wasn’t sent: they wrote first."])
        XCTAssertEqual(h.delivery.delivered.first?.roomID, "!a")
        XCTAssertEqual(h.delivery.delivered.first?.category, .scheduled, "no Mark as Read: there's nothing to read")

        h.script.scheduled["!a"] = [scheduledJSON(1, room: "!a", due: 2000, state: "canceled"),
                                    scheduledJSON(2, room: "!a", due: 2500, state: "missed")]
        h.server.notify(["kind": "scheduled", "room_id": "!a"])
        h.server.notify(["kind": "scheduled", "room_id": "!a"])
        try await waitUntil { h.coordinator.scheduledReads == 7 }
        XCTAssertEqual(h.delivery.delivered.map(\.body), [
            "A scheduled message to Chat A wasn’t sent: they wrote first.",
            "A scheduled message to Chat A missed its time while Courier was closed.",
        ])

        // Courier restarts: a new engine, a new coordinator, the same settings. Neither is told again, at connect or
        // after.
        let lists = h.script.scheduled
        await finish(h)
        let again = try await start(defaults: h.defaults, scheduled: lists)
        try await waitUntil { again.coordinator.scheduledReads == 1 }
        XCTAssertTrue(again.delivery.delivered.isEmpty, "the read at connect finds both, already told")
        again.server.notify(["kind": "scheduled", "room_id": "!a"])
        try await waitUntil { again.coordinator.scheduledReads == 2 }
        XCTAssertTrue(again.delivery.delivered.isEmpty)

        // Rescheduled (a new set_at), then canceled again: that is news.
        again.script.scheduled["!a"] = [scheduledJSON(1, room: "!a", due: 9000, state: "canceled", setAt: 5000),
                                        scheduledJSON(2, room: "!a", due: 2500, state: "missed")]
        again.server.notify(["kind": "scheduled", "room_id": "!a"])
        try await waitUntil { again.coordinator.scheduledReads == 3 }
        XCTAssertEqual(again.delivery.delivered.map(\.body),
                       ["A scheduled message to Chat A wasn’t sent: they wrote first."])
        await finish(again)
    }

    /// Looking at the chat, the strip above its composer says so: no banner, and it isn't told later either.
    func testScheduledNewsInTheChatInFrontIsNotABanner() async throws {
        let h = try await start()
        try await waitUntil { h.coordinator.scheduledReads == 1 }
        h.app.selectedRoomID = "!a"
        h.window.isKey = true
        h.script.scheduled["!a"] = [scheduledJSON(1, room: "!a", due: 2000, state: "missed")]
        h.server.notify(["kind": "scheduled", "room_id": "!a"])
        try await waitUntil { h.coordinator.scheduledReads == 2 }
        XCTAssertTrue(h.delivery.delivered.isEmpty)

        // Looking away, the same message is old news.
        h.window.isKey = false
        h.server.notify(["kind": "scheduled", "room_id": "!a"])
        try await waitUntil { h.coordinator.scheduledReads == 3 }
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        // Another chat's, while looking at this one, is a banner.
        h.window.isKey = true
        h.window.rows["!b"] = inboxRow("!b", name: "Chat B")
        h.script.scheduled["!b"] = [scheduledJSON(2, room: "!b", due: 2000, state: "canceled")]
        h.server.notify(["kind": "scheduled", "room_id": "!b"])
        try await waitUntil { h.coordinator.scheduledReads == 4 }
        XCTAssertEqual(h.delivery.delivered.map(\.roomID), ["!b"])
        await finish(h)
    }

    func testTheConnectionTimeIsWhenTheEngineWasGreeted() async throws {
        let h = try await start()
        XCTAssertEqual(h.app.connectedAt, h.clock.date)
        await finish(h)
    }
}

// MARK: - Fixtures

@MainActor
final class FakeDelivery: NotificationDelivering {
    private(set) var delivered: [NotificationContent] = []
    private(set) var cleared: [String] = []
    /// The notifications taken down one by one, by id.
    private(set) var removed: [String] = []
    /// Everything done, in order: "deliver <id>", "remove <id>", "clear <room>".
    private(set) var log: [String] = []
    private(set) var permissionRequests = 0

    func requestPermission() { permissionRequests += 1 }
    func deliver(_ content: NotificationContent) {
        delivered.append(content)
        log.append("deliver " + content.eventID)
    }

    func clear(roomID: String) {
        cleared.append(roomID)
        log.append("clear " + roomID)
    }

    func remove(notificationID: String) {
        removed.append(notificationID)
        log.append("remove " + notificationID)
    }
}

final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var millis: Int64

    init(millis: Int64) { self.millis = millis }

    var date: Date { lock.withLock { Date(timeIntervalSince1970: Double(millis) / 1000) } }

    func advance(seconds: Double) { lock.withLock { millis += Int64(seconds * 1000) } }
}

/// What the stand-in engine answers for the notification tests.
final class NotificationScript: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String: [[String: Any]]] = [:]
    private var _rooms: [[String: Any]] = []
    private var _failSend = false
    private var _held: Set<String> = []
    private var _scheduled: [String: [[String: Any]]] = [:]

    /// scheduled.list's answer, by chat; with no room_id, every chat's.
    var scheduled: [String: [[String: Any]]] {
        get { lock.withLock { _scheduled } }
        set { lock.withLock { _scheduled = newValue } }
    }

    var events: [String: [[String: Any]]] {
        get { lock.withLock { _events } }
        set { lock.withLock { _events = newValue } }
    }

    var rooms: [[String: Any]] {
        get { lock.withLock { _rooms } }
        set { lock.withLock { _rooms = newValue } }
    }

    /// The next call of `method` is not answered until the test answers it (or never).
    func hold(_ method: String) { lock.withLock { _ = _held.insert(method) } }

    private func takeHold(_ method: String) -> Bool { lock.withLock { _held.remove(method) != nil } }

    /// message.send is refused.
    var failSend: Bool {
        get { lock.withLock { _failSend } }
        set { lock.withLock { _failSend = newValue } }
    }

    func handle(_ method: String, _ params: [String: Any]?) -> TestEngineServer.Reply {
        if method != "hello", takeHold(method) { return .later }
        switch method {
        case "hello": return TestEngineServer.helloOK
        case "accounts.list": return .result(["accounts": [account("whatsapp", "CONNECTED")]])
        case "inbox.list":
            // Only lookups by id: a room_id the engine doesn't have is left out.
            let ids = params?["room_ids"] as? [String] ?? []
            return .result(["rooms": rooms.filter { ids.contains($0["room_id"] as? String ?? "") },
                            "next_cursor": NSNull()])
        case "room.events":
            let room = params?["room_id"] as? String ?? ""
            return .result(["events": events[room] ?? [], "before": NSNull(), "after": NSNull()])
        case "message.send":
            return failSend ? .error(code: -32000, message: "example failure") : .result(["event_id": "$sent"])
        case "scheduled.list":
            let room = params?["room_id"] as? String
            let all = room.map { scheduled[$0] ?? [] } ?? scheduled.values.flatMap { $0 }
            return .result(["scheduled": all])
        default: return .result([String: Any]())
        }
    }
}

/// An event as the engine writes it.
func message(_ id: String, ts: Int64, text: String, mine: Bool = false, room: String = "!a") -> [String: Any] {
    [
        "event_id": id, "room_id": room, "sender": mine ? Timeline.meUserID : "@other:courier.local",
        "sender_name": "Sam", "sender_avatar_path": "", "mine": mine, "type": "m.room.message",
        "content": ["msgtype": "m.text", "body": text], "ts": ts, "seq": 1, "status": "sent", "status_reason": "",
        "media_path": "", "bookmarked": false, "poll": NSNull(), "thread": NSNull(), "expires_at": 0,
        "delivered": false, "read_by": [[String: Any]](),
    ]
}

func inboxRow(_ id: String, name: String, direct: Bool = true, muted: Bool = false, lowPriority: Bool = false,
              hidden: Bool = false, request: Bool = false, mutedBy: MutedBy = .none) -> InboxRow {
    InboxRow(roomID: id, network: "whatsapp", name: name, avatarPath: "", isDirect: direct, lastTS: 0, preview: "",
             previewKind: .text, previewMine: false, unread: 0, muted: muted, lowPriority: lowPriority, hidden: hidden,
             request: request, mutedBy: mutedBy)
}

func inboxRowJSON(_ id: String, name: String) -> [String: Any] {
    room(id, ts: 1, name: name)
}
