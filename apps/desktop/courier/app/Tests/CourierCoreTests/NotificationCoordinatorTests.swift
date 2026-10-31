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
        AppLockGate.shared.resetForTesting()
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
        /// App Lock is active (`SystemLifecycleModel.isLocked`).
        var isLocked = false
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
                       scheduled: [String: [[String: Any]]] = [:],
                       scheduler: (any NotificationTimerScheduling)? = nil,
                       clipboard: (any ClipboardSink)? = nil,
                       soundEffects: (any SoundEffectPlaying)? = nil) async throws -> Harness {
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
        let effectiveDefaults = defaults ?? store.defaults
        let preferences = InboxPreferences(defaults: effectiveDefaults)
        let coordinator = NotificationCoordinator(
            appModel: app, delivery: delivery, row: { window.rows[$0] }, isLooking: { window.isKey },
            isAwayFromLatest: { window.isAway }, isIncognito: { window.incognito },
            isAppLocked: { window.isLocked },
            restoreDraft: { window.drafts.append(($0, $1, $2)) }, showWindow: { window.shown += 1 },
            preferences: preferences, entitlement: entitlement,
            window: gather, replyTimeout: replyTimeout, clock: { clock.date }, defaults: effectiveDefaults,
            scheduler: scheduler, clipboard: clipboard, soundEffects: soundEffects)
        if connected {
            app.start()
            try await waitUntil { app.client != nil }
        }
        return Harness(script: script, server: server, app: app, delivery: delivery, coordinator: coordinator,
                       clock: clock, window: window, preferences: preferences, defaults: effectiveDefaults)
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

    /// B9: a reply message.send answered for but stored failed, or waiting for its network, is not silent. Failed is
    /// the same "wasn't sent" notification a thrown error gives (the message is in the chat, with Retry, so no draft
    /// is put back); waiting says it goes when the network is back. Neither reads the chat.
    func testAReplyStoredFailedOrWaitingSaysSo() async throws {
        let h = try await start()
        func stored(_ status: String) {
            var event = message("$sent", ts: connectedMillis + 1000, text: "on my way", mine: true)
            event["status"] = status
            h.script.events["!a"] = [event]
        }

        stored("failed")
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["Your reply wasn’t sent — it’s waiting in the chat."])
        XCTAssertEqual(h.delivery.delivered.map(\.roomID), ["!a"], "a click opens that chat")
        XCTAssertTrue(h.window.drafts.isEmpty, "the failed message is in the chat already")

        stored("waiting")
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertEqual(h.delivery.delivered.last?.body, "Your reply will be sent when the network is back.")
        XCTAssertEqual(h.delivery.delivered.last?.title, "Chat A")
        XCTAssertEqual(h.delivery.delivered.count, 2)
        XCTAssertTrue(h.window.drafts.isEmpty)
        XCTAssertTrue(h.server.receivedParams("room.markRead").isEmpty)

        stored("sent")
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertEqual(h.delivery.delivered.count, 2, "one that went says nothing")
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

    func testMergedChatOpenInFrontSuppressesMemberBannersMarksReminderReadAndNotifiesOtherRoom() async throws {
        let h = try await start()
        h.window.rows["!wa"] = InboxRow(
            roomID: "!wa", network: "whatsapp", name: "Alice Example", avatarPath: "",
            isDirect: true, lastTS: 1, preview: "", previewKind: .text, previewMine: false, unread: 0, muted: false,
            mergeID: "merge:alice"
        )
        h.window.rows["!sig"] = InboxRow(
            roomID: "!sig", network: "signal", name: "Alice Example", avatarPath: "",
            isDirect: true, lastTS: 2, preview: "", previewKind: .text, previewMine: false, unread: 0, muted: false,
            mergeID: "merge:alice"
        )
        h.window.rows["!other"] = inboxRow("!other", name: "Bob")
        h.app.mergedChats["merge:alice"] = MergedChat(
            mergeID: "merge:alice", name: "Alice Example", avatarPath: "",
            lastRoomID: "!sig", roomIDs: ["!wa", "!sig"], networks: ["whatsapp", "signal"], createdTS: 1
        )
        h.app.selectedRoomID = "merge:alice"
        h.window.isKey = true
        h.clock.advance(seconds: 5)

        // Messages on either member of the open merged chat give no banner.
        h.script.events["!wa"] = [message("$w1", ts: connectedMillis + 1000, text: "from wa", room: "!wa")]
        h.server.notify(["kind": "event", "room_id": "!wa", "event_id": "$w1"])
        try await settle(h, fetches: 1)
        XCTAssertTrue(h.delivery.delivered.isEmpty, "open merged chat must not raise a banner for WA member")

        h.script.events["!sig"] = [message("$s1", ts: connectedMillis + 2000, text: "from sig", room: "!sig")]
        h.server.notify(["kind": "event", "room_id": "!sig", "event_id": "$s1"])
        try await settle(h, fetches: 2)
        XCTAssertTrue(h.delivery.delivered.isEmpty, "open merged chat must not raise a banner for Signal member")

        // A reminder in the open merged chat marks that member room read and gives no banner.
        h.server.notify(["kind": "reminder", "room_id": "!wa"])
        try await waitUntil { !h.server.receivedParams("room.markRead").isEmpty || !h.delivery.delivered.isEmpty }
        XCTAssertTrue(h.delivery.delivered.isEmpty, "reminder in open merged chat must not raise a banner")
        XCTAssertEqual(h.server.receivedParams("room.markRead").map { $0["room_id"] as? String }, ["!wa"],
                       "reminder in open merged chat must mark the member room read")

        // A non-member room still notifies while the merged chat is open.
        h.script.events["!other"] = [message("$o1", ts: connectedMillis + 3000, text: "from bob", room: "!other")]
        h.server.notify(["kind": "event", "room_id": "!other", "event_id": "$o1"])
        try await waitUntil { h.delivery.delivered.contains { $0.roomID == "!other" } }
        XCTAssertEqual(h.delivery.delivered.map(\.roomID), ["!other"])
        await finish(h)
    }

    func testMediaNotificationIncludesAttachmentPathExceptViewOnce() async throws {
        let h = try await start()
        h.window.isKey = false
        h.clock.advance(seconds: 5)
        let dmRow = inboxRow("!a", name: "Alice Example")
        h.window.rows["!a"] = dmRow

        let normalPhoto = Event(
            eventID: "$photo1", roomID: "!a", sender: "@wa_alice", senderName: "Alice Example",
            mine: false, type: "m.room.message",
            content: .object(["msgtype": .string("m.image"), "body": .string("sunset.jpg")]),
            ts: connectedMillis + 1000, seq: 10, status: .sent,
            mediaPath: "/tmp/sunset-full.jpg", thumbnailPath: "/tmp/sunset-thumb.jpg", viewOnce: false
        )
        let viewOncePhoto = Event(
            eventID: "$photo2", roomID: "!a", sender: "@wa_alice", senderName: "Alice Example",
            mine: false, type: "m.room.message",
            content: .object(["msgtype": .string("m.image"), "body": .string("secret.jpg")]),
            ts: connectedMillis + 2000, seq: 11, status: .sent,
            mediaPath: "/tmp/secret-full.jpg", thumbnailPath: "/tmp/secret-thumb.jpg", viewOnce: true
        )

        let normalPlan = NotificationPolicy.content(for: normalPhoto, room: dmRow)
        XCTAssertEqual(normalPlan.attachmentPath, "/tmp/sunset-thumb.jpg")

        let viewOncePlan = NotificationPolicy.content(for: viewOncePhoto, room: dmRow)
        XCTAssertNil(viewOncePlan.attachmentPath, "view-once media must never attach thumbnail/file to OS notifications")

        var photo1JSON = message("$photo1", ts: connectedMillis + 1000, text: "sunset.jpg", room: "!a")
        photo1JSON["content"] = ["msgtype": "m.image", "body": "sunset.jpg"]
        photo1JSON["media_path"] = "/tmp/sunset-full.jpg"
        photo1JSON["thumbnail_path"] = "/tmp/sunset-thumb.jpg"
        photo1JSON["view_once"] = false

        var photo2JSON = message("$photo2", ts: connectedMillis + 2000, text: "secret.jpg", room: "!a")
        photo2JSON["content"] = ["msgtype": "m.image", "body": "secret.jpg"]
        photo2JSON["media_path"] = "/tmp/secret-full.jpg"
        photo2JSON["thumbnail_path"] = "/tmp/secret-thumb.jpg"
        photo2JSON["view_once"] = true

        h.script.events["!a"] = [photo2JSON, photo1JSON]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$photo1"])
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$photo2"])
        try await waitUntil { h.delivery.delivered.count == 2 }
        XCTAssertEqual(h.delivery.delivered.first { $0.eventID == "$photo1" }?.attachmentPath, "/tmp/sunset-thumb.jpg")
        XCTAssertNil(h.delivery.delivered.first { $0.eventID == "$photo2" }?.attachmentPath)
        await finish(h)
    }

    // MARK: - Task 5: Delay batching, OTP bypass & auto-copy, repeat unread, overrides & sound effects

    func testDelayBatchingHoldsNormalMessageCancelsOnReadAndDeliversWhenUnread() async throws {
        let scheduler = ManualNotificationScheduler()
        let clipboard = FakeClipboardSink()
        let h = try await start(scheduler: scheduler, clipboard: clipboard)
        h.preferences.notifications.delaySeconds = 30
        h.clock.advance(seconds: 5)

        // 1. Normal message held for 30s, canceled when chat is read at t = 10s
        h.script.events["!a"] = [message("$d1", ts: connectedMillis + 5000, text: "Dinner at 7?")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$d1"])
        try await settle(h, fetches: 1)
        XCTAssertTrue(h.delivery.delivered.isEmpty, "normal message must be held during delaySeconds window")

        h.clock.advance(seconds: 10)
        await scheduler.advance(by: 10)
        XCTAssertTrue(h.delivery.delivered.isEmpty)

        h.server.notify(["kind": "read", "room_id": "!a"])
        try await waitUntil { h.delivery.cleared.contains("!a") }

        h.clock.advance(seconds: 20)
        await scheduler.advance(by: 20)
        XCTAssertTrue(h.delivery.delivered.isEmpty, "reading chat at t=10s must cancel delayed notification before t=30s")

        // 2. Normal message held for 30s, delivered at t = 30s when still unread
        let now2 = Int64(h.clock.date.timeIntervalSince1970 * 1000)
        h.script.events["!a"] = [message("$d2", ts: now2, text: "Are you still coming?")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$d2"])
        try await settle(h, fetches: 2)
        XCTAssertTrue(h.delivery.delivered.isEmpty)

        h.clock.advance(seconds: 29)
        await scheduler.advance(by: 29)
        XCTAssertTrue(h.delivery.delivered.isEmpty)

        h.clock.advance(seconds: 1)
        await scheduler.advance(by: 1)
        XCTAssertEqual(h.delivery.delivered.map(\.eventID), ["$d2"])
        XCTAssertEqual(h.delivery.delivered.first?.body, "Are you still coming?")
        await finish(h)
    }

    func testOTPMessageBypassesDelayAndAutoCopiesOnlyWhenEnabledEvenInMutedChat() async throws {
        let scheduler = ManualNotificationScheduler()
        let clipboard = FakeClipboardSink()
        let h = try await start(scheduler: scheduler, clipboard: clipboard)
        h.preferences.notifications.delaySeconds = 30
        h.preferences.notifications.autoCopyOTP = false
        h.clock.advance(seconds: 5)

        // 1. autoCopyOTP == false: OTP message in unmuted chat bypasses 30s delay at t = 0s, but does NOT copy to clipboard
        let ts1 = Int64(h.clock.date.timeIntervalSince1970 * 1000)
        h.script.events["!a"] = [message("$otp1", ts: ts1, text: "Your verification code is 123456")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$otp1"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(h.delivery.delivered.first?.eventID, "$otp1", "OTP message must bypass delaySeconds and deliver at t=0s")
        XCTAssertEqual(h.delivery.delivered.first?.category, .message)
        XCTAssertTrue(clipboard.copiedCodes.isEmpty, "autoCopyOTP is false: nothing may be written to clipboard")

        // When autoCopyOTP == false, a muted chat remains silent even for an OTP message
        h.window.rows["!a"] = inboxRow("!a", name: "Chat A", muted: true)
        let ts2 = ts1 + 1000
        h.script.events["!a"] = [message("$otp2", ts: ts2, text: "123456 is your login code")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$otp2"])
        try await settle(h, fetches: 2)
        XCTAssertEqual(h.delivery.delivered.count, 1)
        XCTAssertTrue(clipboard.copiedCodes.isEmpty)

        // 2. autoCopyOTP == true: OTP message in a muted chat (and disabled account override) still notifies at t = 0s and copies 123456
        h.preferences.notifications.autoCopyOTP = true
        h.preferences.notifications.accountOverrides["whatsapp"] = AccountNotificationOverride(enabled: false, showPreviews: true)
        let ts3 = ts2 + 1000
        h.script.events["!a"] = [message("$otp3", ts: ts3, text: "Your verification code is 123456")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$otp3"])
        try await waitUntil { h.delivery.delivered.count == 2 }
        let deliveredOTP = try XCTUnwrap(h.delivery.delivered.last)
        XCTAssertEqual(deliveredOTP.eventID, "$otp3")
        XCTAssertEqual(deliveredOTP.body, "Your verification code is 123456")
        XCTAssertEqual(deliveredOTP.category, .messageOTP)
        XCTAssertEqual(deliveredOTP.userInfo, ["room_id": "!a"], "never store OTP code in userInfo")
        XCTAssertEqual(clipboard.copiedCodes, ["123456"])
        await finish(h)
    }

    func testRepeatUnreadRePostsAtIntervalWhenUnreadAndCancelsWhenRead() async throws {
        let scheduler = ManualNotificationScheduler()
        let h = try await start(scheduler: scheduler)
        h.preferences.notifications.repeatUnreadMinutes = 2
        h.clock.advance(seconds: 5)

        // 1. Unread chat re-posts once at t = 120s
        var unreadRow = inboxRow("!a", name: "Chat A")
        unreadRow.unread = 1
        h.window.rows["!a"] = unreadRow
        let ts1 = Int64(h.clock.date.timeIntervalSince1970 * 1000)
        h.script.events["!a"] = [message("$r1", ts: ts1, text: "Please review")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$r1"])
        try await waitUntil { h.delivery.delivered.count == 1 }

        h.clock.advance(seconds: 60)
        await scheduler.advance(by: 60)
        XCTAssertEqual(h.delivery.delivered.count, 1)

        h.clock.advance(seconds: 60)
        await scheduler.advance(by: 60)
        XCTAssertEqual(h.delivery.delivered.count, 2, "must re-post notification once at t=120s when still unread")
        XCTAssertEqual(h.delivery.delivered.last?.eventID, "$r1")

        // Does not repeat a second time at t = 240s
        h.clock.advance(seconds: 120)
        await scheduler.advance(by: 120)
        XCTAssertEqual(h.delivery.delivered.count, 2)

        // 2. Marked read at t = 60s cancels repeat timer before t = 120s
        let ts2 = Int64(h.clock.date.timeIntervalSince1970 * 1000)
        h.script.events["!a"] = [message("$r2", ts: ts2, text: "Second unread message")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$r2"])
        try await waitUntil { h.delivery.delivered.count == 3 }

        h.clock.advance(seconds: 60)
        await scheduler.advance(by: 60)
        h.server.notify(["kind": "read", "room_id": "!a"])
        try await waitUntil { h.delivery.cleared.contains("!a") }

        h.clock.advance(seconds: 60)
        await scheduler.advance(by: 60)
        XCTAssertEqual(h.delivery.delivered.count, 3, "reading chat at t=60s must prevent repeat notification at t=120s")
        await finish(h)
    }

    func testPerAccountOverridesAndSoundEffectsInCoordinator() async throws {
        let soundPlayer = FakeSoundEffectPlayer()
        let h = try await start(soundEffects: soundPlayer)
        h.preferences.notifications.soundEffectsMode = .always
        h.preferences.notifications.soundEffectsVolume = 0.45
        h.preferences.notifications.accountOverrides["whatsapp"] = AccountNotificationOverride(
            enabled: true,
            showPreviews: false,
            sound: .harp
        )
        h.clock.advance(seconds: 5)

        let ts1 = Int64(h.clock.date.timeIntervalSince1970 * 1000)
        var incomingPhoto = message("$m1", ts: ts1, text: "photo.jpg")
        incomingPhoto["content"] = ["msgtype": "m.image", "body": "photo.jpg"]
        incomingPhoto["media_path"] = "/tmp/photo.jpg"
        incomingPhoto["thumbnail_path"] = "/tmp/thumb.jpg"
        h.script.events["!a"] = [incomingPhoto]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$m1"])
        try await waitUntil { h.delivery.delivered.count == 1 }

        let note = try XCTUnwrap(h.delivery.delivered.first)
        XCTAssertEqual(note.body, "New message")
        XCTAssertNil(note.attachmentPath)
        XCTAssertEqual(note.sound, .harp)
        XCTAssertEqual(soundPlayer.played.map(\.effect), [.messageReceived])
        XCTAssertEqual(soundPlayer.played.first?.volume ?? 0, 0.45, accuracy: 0.001)

        // Outgoing message triggers .messageSent sound effect without notification
        let ts2 = ts1 + 1000
        h.script.events["!a"] = [message("$m2", ts: ts2, text: "my reply", mine: true), incomingPhoto]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$m2"])
        try await settle(h, fetches: 2)
        XCTAssertEqual(h.delivery.delivered.count, 1)
        XCTAssertEqual(soundPlayer.played.map(\.effect), [.messageReceived, .messageSent])
        await finish(h)
    }

    func testRestartNotificationCenterAndOpenSystemNotificationSettings() async throws {
        let h = try await start()
        h.coordinator.openSystemNotificationSettings()
        XCTAssertEqual(h.delivery.openedSettingsCount, 1)

        h.coordinator.restartNotificationCenter()
        XCTAssertEqual(h.delivery.restartedCenterCount, 1)
        await finish(h)
    }

    func testLockedAppRedactsImmediateDelayedRepeatTypingAndReminderNotifications() async throws {
        let scheduler = ManualNotificationScheduler()
        let h = try await start(scheduler: scheduler)
        h.preferences.typingNotifications = true
        h.clock.advance(seconds: 5)

        var unreadRow = inboxRow("!a", name: "Alice Example", direct: false)
        unreadRow.unread = 1
        h.window.rows["!a"] = unreadRow

        // 1. Immediate notification while locked
        h.window.isLocked = true
        let ts1 = Int64(h.clock.date.timeIntervalSince1970 * 1000)
        var msg1 = message("$lock-imm", ts: ts1, text: "Confidential immediate")
        msg1["thumbnail_path"] = "/tmp/secret-imm.jpg"
        msg1["content"] = ["msgtype": "m.image", "body": "Confidential immediate"]
        h.script.events["!a"] = [msg1]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$lock-imm"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        let immNote = try XCTUnwrap(h.delivery.delivered.last)
        XCTAssertEqual(immNote.title, "Courier")
        XCTAssertNil(immNote.subtitle)
        XCTAssertEqual(immNote.body, "New message")
        XCTAssertNil(immNote.attachmentPath)
        XCTAssertEqual(immNote.category, .scheduled)

        // 2. Delayed/batched notification queued while unlocked at t=0, then app locks before timer fires at t=30s
        h.window.isLocked = false
        h.preferences.notifications.delaySeconds = 30
        h.preferences.notifications.repeatUnreadMinutes = 2
        let ts2 = ts1 + 1000
        var msg2 = message("$lock-del", ts: ts2, text: "Confidential delayed")
        msg2["thumbnail_path"] = "/tmp/secret-del.jpg"
        msg2["content"] = ["msgtype": "m.image", "body": "Confidential delayed"]
        h.script.events["!a"] = [msg2, msg1]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$lock-del"])
        try await settle(h, fetches: 2)
        XCTAssertEqual(h.delivery.delivered.count, 1)

        // Lock app at t=10s, then advance to t=30s
        h.window.isLocked = true
        h.clock.advance(seconds: 30)
        await scheduler.advance(by: 30)
        XCTAssertEqual(h.delivery.delivered.count, 2, "delayed notification must deliver at t=30s")
        let delNote = try XCTUnwrap(h.delivery.delivered.last)
        XCTAssertEqual(delNote.title, "Courier", "delayed notification firing while locked must redact title")
        XCTAssertNil(delNote.subtitle, "delayed notification firing while locked must redact sender subtitle")
        XCTAssertEqual(delNote.body, "New message", "delayed notification firing while locked must redact body")
        XCTAssertNil(delNote.attachmentPath, "delayed notification firing while locked must redact media attachment")
        XCTAssertEqual(delNote.category, .scheduled, "delayed notification firing while locked must not offer inline Reply")

        // 3. Repeat-unread reminder firing at t=150s (120s after delivery) while locked must also be redacted
        h.clock.advance(seconds: 120)
        await scheduler.advance(by: 120)
        XCTAssertEqual(h.delivery.delivered.count, 3, "repeat-unread must fire 120s after delayed delivery")
        let repNote = try XCTUnwrap(h.delivery.delivered.last)
        XCTAssertEqual(repNote.title, "Courier")
        XCTAssertNil(repNote.subtitle)
        XCTAssertEqual(repNote.body, "New message")
        XCTAssertNil(repNote.attachmentPath)
        XCTAssertEqual(repNote.category, .scheduled)

        // 4. Typing notification while locked must redact chat title and who is typing
        var typingRoomJSON = inboxRowJSON("!a", name: "Alice Example")
        typingRoomJSON["typing"] = ["Alice Example"]
        h.script.rooms = [typingRoomJSON]
        h.server.notify(["kind": "typing", "room_id": "!a"])
        try await waitUntil { h.delivery.delivered.count == 4 }
        let typNote = try XCTUnwrap(h.delivery.delivered.last)
        XCTAssertEqual(typNote.title, "Courier", "typing notification while locked must hide chat name")
        XCTAssertNil(typNote.subtitle)
        XCTAssertEqual(typNote.body, "Someone is typing…", "typing notification while locked must hide sender name")
        XCTAssertEqual(typNote.category, .scheduled)

        // 5. Reminder due notification while locked must redact chat title
        h.server.notify(["kind": "reminder", "room_id": "!a"])
        try await waitUntil { h.delivery.delivered.count == 5 }
        let remNote = try XCTUnwrap(h.delivery.delivered.last)
        XCTAssertEqual(remNote.title, "Courier", "reminder notification while locked must hide chat name")
        XCTAssertNil(remNote.subtitle)
        XCTAssertEqual(remNote.body, "Reminder due")
        XCTAssertEqual(remNote.category, .scheduled)
        await finish(h)
    }

    func testSoundEffectsRespectNotificationSettingsAndFailedStatus() async throws {
        let soundPlayer = FakeSoundEffectPlayer()
        let h = try await start(soundEffects: soundPlayer)
        h.preferences.notifications.soundEffectsMode = .always
        h.clock.advance(seconds: 5)

        var unreadRow = inboxRow("!a", name: "Chat A", direct: true)
        unreadRow.unread = 1
        h.window.rows["!a"] = unreadRow

        // 1. Failed incoming event must not play a sound effect
        let ts1 = Int64(h.clock.date.timeIntervalSince1970 * 1000)
        var failedMsg = message("$s-fail", ts: ts1, text: "Failed incoming")
        failedMsg["status"] = "failed"
        h.script.events["!a"] = [failedMsg]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$s-fail"])
        try await settle(h, fetches: 1)
        XCTAssertTrue(soundPlayer.played.isEmpty, "failed event must not play sound effect")

        // 2. When messageNotificationsEnabled == false, direct message must not play .messageReceived sound
        h.preferences.notifications.messageNotificationsEnabled = false
        let ts2 = ts1 + 1000
        let dmMsg = message("$s-dm-off", ts: ts2, text: "Quiet DM")
        h.script.events["!a"] = [dmMsg]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$s-dm-off"])
        try await settle(h, fetches: 2)
        XCTAssertTrue(soundPlayer.played.isEmpty, "disabled DM notifications must suppress received sound effect")

        // 3. Per-account override enabled == false must suppress received sound effect
        h.preferences.notifications.messageNotificationsEnabled = true
        h.preferences.notifications.accountOverrides["whatsapp"] = AccountNotificationOverride(enabled: false, showPreviews: true)
        let ts3 = ts2 + 1000
        let acctOffMsg = message("$s-acct-off", ts: ts3, text: "Quiet Account")
        h.script.events["!a"] = [acctOffMsg]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$s-acct-off"])
        try await settle(h, fetches: 3)
        XCTAssertTrue(soundPlayer.played.isEmpty, "disabled account override must suppress received sound effect")

        // 4. Request chat when requestNotificationsEnabled == false must suppress received sound effect
        h.preferences.notifications.accountOverrides.removeAll()
        h.preferences.notifications.requestNotificationsEnabled = false
        var reqRow = inboxRow("!a", name: "Chat A", direct: true, request: true)
        reqRow.unread = 1
        h.window.rows["!a"] = reqRow
        let ts4 = ts3 + 1000
        let reqMsg = message("$s-req-off", ts: ts4, text: "New request")
        h.script.events["!a"] = [reqMsg]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$s-req-off"])
        try await settle(h, fetches: 4)
        XCTAssertTrue(soundPlayer.played.isEmpty, "disabled request notifications must suppress received sound effect")
        await finish(h)
    }

    func testNotificationBannerActionsAndAutoCopyOTPDoNothingWhileLocked() async throws {
        let clipboard = FakeClipboardSink()
        let h = try await start(clipboard: clipboard)
        h.preferences.notifications.autoCopyOTP = true
        h.clock.advance(seconds: 5)

        // Deliver an OTP message while unlocked so a code is cached for !a.
        let ts1 = Int64(h.clock.date.timeIntervalSince1970 * 1000)
        let otpUnlocked = message("$otp-1", ts: ts1, text: "Your security code is 482910")
        h.script.events["!a"] = [otpUnlocked]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$otp-1"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(clipboard.copiedCodes, ["482910"])

        // Lock the app.
        h.window.isLocked = true
        let initialShown = h.window.shown
        let initialSentCalls = h.server.receivedMethods().filter { $0 == "message.send" }.count
        let initialMarkReadCalls = h.server.receivedMethods().filter { $0 == "room.markRead" }.count
        let initialReminderCalls = h.server.receivedMethods().filter { $0 == "reminder.set" }.count

        // 1. Inline Reply while locked must not send or restore draft; brings Courier forward to lock screen instead.
        await h.coordinator.reply(roomID: "!a", text: "locked reply")
        XCTAssertEqual(
            h.server.receivedMethods().filter { $0 == "message.send" }.count,
            initialSentCalls,
            "Notification inline reply while locked must not call message.send"
        )
        XCTAssertTrue(h.window.drafts.isEmpty, "Notification inline reply while locked must not mutate drafts")
        XCTAssertEqual(h.window.shown, initialShown + 1, "Notification inline reply while locked must bring Courier forward to lock screen")

        // 2. Mark as Read while locked must not call room.markRead; brings Courier forward instead.
        await h.coordinator.markRead(roomID: "!a")
        XCTAssertEqual(
            h.server.receivedMethods().filter { $0 == "room.markRead" }.count,
            initialMarkReadCalls,
            "Notification Mark as Read while locked must not call room.markRead"
        )
        XCTAssertEqual(h.window.shown, initialShown + 2, "Notification Mark as Read while locked must bring Courier forward to lock screen")

        // 3. Remind while locked must not call reminder.set; brings Courier forward instead.
        await h.coordinator.remind(roomID: "!a", after: NotificationCoordinator.remindOneHour)
        XCTAssertEqual(
            h.server.receivedMethods().filter { $0 == "reminder.set" }.count,
            initialReminderCalls,
            "Notification Remind while locked must not call reminder.set"
        )
        XCTAssertEqual(h.window.shown, initialShown + 3, "Notification Remind while locked must bring Courier forward to lock screen")

        // 4. Copy Code while locked must not copy to clipboard; brings Courier forward instead.
        h.coordinator.copyOTPCode(forRoomID: "!a")
        XCTAssertEqual(clipboard.copiedCodes, ["482910"], "Notification Copy Code while locked must not copy OTP to clipboard")
        XCTAssertEqual(h.window.shown, initialShown + 4, "Notification Copy Code while locked must bring Courier forward to lock screen")

        // 5. Click-to-open while locked must not change selectedRoomID; brings Courier forward instead.
        XCTAssertNil(h.app.selectedRoomID)
        h.coordinator.open(roomID: "!a")
        XCTAssertNil(h.app.selectedRoomID, "Notification click-to-open while locked must not open chat")
        XCTAssertEqual(h.window.shown, initialShown + 5, "Notification click-to-open while locked must bring Courier forward to lock screen")

        // 6. Incoming OTP message while locked keeps banner content redacted AND skips automatic OTP clipboard copy.
        let ts2 = ts1 + 1000
        let otpLocked = message("$otp-2", ts: ts2, text: "Your verification code is 918273")
        h.script.events["!a"] = [otpLocked, otpUnlocked]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$otp-2"])
        try await waitUntil { h.delivery.delivered.count == 2 }
        let lockedBanner = try XCTUnwrap(h.delivery.delivered.last)
        XCTAssertEqual(lockedBanner.title, "Courier")
        XCTAssertEqual(lockedBanner.body, "New message")
        XCTAssertEqual(lockedBanner.category, .scheduled)
        XCTAssertEqual(clipboard.copiedCodes, ["482910"], "Automatic OTP clipboard copy must be skipped while locked")

        await finish(h)
    }

    func testLockedOpenChatDoesNotMarkReadDoesNotClearReminderAndPostsRedactedNotification() async throws {
        let h = try await start()
        let lifecycle = SystemLifecycleModel(
            defaults: h.defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: FakeBiometricAuthService(available: true, result: .success(true))
        )
        let presence = StaticPresence()
        let attention = Attention(source: presence, pollInterval: nil)
        attention.setWindowKey(true)
        XCTAssertTrue(attention.isLooking, "Attention.isLooking must be true when window is key and app is unlocked")

        let conversation = ConversationModel(
            appModel: h.app,
            unreadCount: { h.window.rows[$0]?.unread ?? 0 },
            attention: attention
        )
        conversation.setWindowKey(true)

        // Open !a while unlocked with an initial message so the chat is loaded in front.
        h.window.isKey = true
        let initialMsg = message("$init-1", ts: connectedMillis - 1000, text: "Initial message")
        h.script.events["!a"] = [initialMsg]
        h.app.selectedRoomID = "!a"
        try await waitUntil { !conversation.items.isEmpty }
        h.clock.advance(seconds: 5)

        // Lock the app with !a still open and key.
        lifecycle.lockNow()
        h.window.isLocked = true
        XCTAssertFalse(
            attention.isLooking,
            "Attention.isLooking must be false while the app is locked even when the window is key"
        )

        let markReadBefore = h.server.receivedMethods().filter { $0 == "room.markRead" }.count
        let reminderClearBefore = h.server.receivedMethods().filter { $0 == "reminder.clear" }.count
        let fetchesBefore = h.server.receivedMethods().filter { $0 == "room.events" }.count

        // Deliver a new message into the open chat !a while locked.
        var unreadRow = inboxRow("!a", name: "Chat A")
        unreadRow.unread = 1
        h.window.rows["!a"] = unreadRow
        let tsLocked = Int64(h.clock.date.timeIntervalSince1970 * 1000)
        let lockedMsg = message("$locked-open-1", ts: tsLocked, text: "Secret while chat open and locked")
        h.script.events["!a"] = [lockedMsg, initialMsg]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$locked-open-1"])

        try await settle(h, fetches: fetchesBefore + 1)

        XCTAssertEqual(
            h.window.rows["!a"]?.unread,
            1,
            "New message in open chat while locked must stay unread"
        )
        XCTAssertEqual(
            h.server.receivedMethods().filter { $0 == "room.markRead" }.count,
            markReadBefore,
            "No room.markRead request may reach the engine while the app is locked"
        )
        XCTAssertEqual(
            h.delivery.delivered.count,
            1,
            "Locked open chat must still post a content-hidden notification when a new message arrives"
        )
        if let msgNote = h.delivery.delivered.first {
            XCTAssertEqual(msgNote.title, "Courier", "Locked open chat must still post a content-hidden notification")
            XCTAssertNil(msgNote.subtitle)
            XCTAssertEqual(msgNote.body, "New message")
            XCTAssertEqual(msgNote.category, .scheduled)
        }

        // Deliver a due reminder in the open chat !a while locked: must NOT call room.markRead or reminder.clear, and must post a redacted banner.
        let markReadBeforeReminder = h.server.receivedMethods().filter { $0 == "room.markRead" }.count
        h.server.notify(["kind": "reminder", "room_id": "!a"])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(
            h.server.receivedMethods().filter { $0 == "room.markRead" }.count,
            markReadBeforeReminder,
            "Due reminder in open chat while locked must not call room.markRead"
        )
        XCTAssertEqual(
            h.server.receivedMethods().filter { $0 == "reminder.clear" }.count,
            reminderClearBefore,
            "Due reminder in open chat while locked must not call reminder.clear"
        )
        XCTAssertEqual(
            h.delivery.delivered.count,
            2,
            "Due reminder in open chat while locked must post a content-hidden reminder notification"
        )
        if h.delivery.delivered.count >= 2, let remNote = h.delivery.delivered.last {
            XCTAssertEqual(remNote.title, "Courier")
            XCTAssertEqual(remNote.body, "Reminder due")
            XCTAssertEqual(remNote.category, .scheduled)
        }

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
    private(set) var openedSettingsCount = 0
    private(set) var restartedCenterCount = 0

    func requestPermission() { permissionRequests += 1 }
    func openSystemNotificationSettings() { openedSettingsCount += 1 }
    func restartNotificationCenter() { restartedCenterCount += 1 }
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

@MainActor
final class FakeClipboardSink: ClipboardSink {
    private(set) var copiedCodes: [String] = []
    func copyOTP(_ code: String) {
        copiedCodes.append(code)
    }
}

@MainActor
final class FakeSoundEffectPlayer: SoundEffectPlaying {
    struct Entry: Equatable {
        let effect: SoundEffectEvent
        let volume: Double
    }
    private(set) var played: [Entry] = []
    func play(_ effect: SoundEffectEvent, volume: Double) {
        played.append(Entry(effect: effect, volume: volume))
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
