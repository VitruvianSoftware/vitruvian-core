// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// A conversation on an app model on a stand-in engine (a `ConversationScript`), with the composer's settings and
/// quick replies in a UserDefaults suite of the test's own. For the message actions, the thread pane and the
/// message commands. All data here is made up.
@MainActor
struct ConversationHarness {
    let script: ConversationScript
    let server: TestEngineServer
    let app: AppModel
    let conversation: ConversationModel
    let preferences: ComposerPreferences
    let quickReplies: QuickReplies
    let store: TestDefaults
    /// The chats' rows, as the inbox would have them.
    let rows: RowBox

    func count(_ method: String) -> Int { server.receivedMethods().filter { $0 == method }.count }

    /// The thread pane's pages asked for (room.events with thread). Each is applied when its answer comes: with
    /// `ThreadModel.pagesApplied` it says every change so far has been read.
    func threadReads() -> Int {
        server.receivedParams("room.events").filter { $0["thread"] != nil && $0["before"] == nil }.count
    }

    /// The chat's newest pages asked for (room.events with no cursor, no around and no thread). Each is applied
    /// when its answer comes: with `ConversationModel.pagesApplied` it says every change so far has been read.
    func newestRequests() -> Int {
        server.receivedParams("room.events").filter {
            $0["before"] == nil && $0["after"] == nil && $0["around"] == nil && $0["thread"] == nil
        }.count
    }

    func messageIDs(_ items: [TimelineItem]) -> [String] {
        items.compactMap { if case let .message(m) = $0 { m.id } else { nil } }
    }

    func message(_ id: String) -> TimelineMessage? {
        for case let .message(m) in conversation.items where m.id == id { return m }
        return nil
    }

    /// Opens `room` and waits for its newest page and its features.
    func open(_ room: String) async throws {
        app.selectedRoomID = room
        try await waitUntil { conversation.isLoaded && conversation.roomID == room }
        if script.features[room] != nil {
            try await waitUntil { conversation.features.source != .none }
        }
    }

    func stop() async {
        await app.stop()
        server.stop()
        store.remove()
    }
}

/// The rows the inbox has, by chat.
@MainActor
final class RowBox {
    var rows: [String: InboxRow] = [:]
}

@MainActor
func startConversation(_ events: [String: [[String: Any]]],
                       features: [String: [String: Any]] = [:],
                       rows: [String: InboxRow] = [:],
                       now: @escaping @MainActor () -> Date = { Date(timeIntervalSince1970: 1_760_600_600) })
    async throws -> ConversationHarness {
    let script = ConversationScript(events: events)
    script.features = features
    let server = try TestEngineServer(handler: script.handle)
    let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
    let supervisor = EngineSupervisor(
        enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
        dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:], launcher: launcher,
        credentials: InMemoryCredentialStore(), clientName: "Courier/test", timing: FakeTime().timing())
    let app = AppModel(supervisor: supervisor)
    let store = TestDefaults()
    let preferences = ComposerPreferences(defaults: store.defaults)
    let quickReplies = QuickReplies(defaults: store.defaults)
    let box = RowBox()
    box.rows = rows
    let conversation = ConversationModel(appModel: app, attention: Attention(source: StaticPresence(), pollInterval: nil),
                                         chat: { box.rows[$0] }, preferences: preferences, now: now)
    conversation.composer.quickReplies = quickReplies
    conversation.setWindowKey(true)
    app.start()
    try await waitUntil { app.client != nil }
    return ConversationHarness(script: script, server: server, app: app, conversation: conversation,
                               preferences: preferences, quickReplies: quickReplies, store: store, rows: box)
}

/// A clipboard that keeps what was copied.
final class FakePasteboard: TextPasteboard {
    private(set) var strings: [String] = []

    func setString(_ text: String) { strings.append(text) }
}

/// ChatFeatures as the engine writes them: by default a chat that can do everything a message action needs.
func featuresJSON(reply: Bool = true, thread: Bool = true, replyIsThread: Bool = false, edit: Bool = true,
                  editMaxAgeMS: Int64 = 0, unsend: Bool = true, unsendMaxAgeMS: Int64 = 0,
                  deleteReachesPhone: Bool = false, hideDeletedPlaceholder: Bool = false,
                  poll: [String: Any]? = ["max_options": 12, "option_max_length": 100],
                  source: String = "stored") -> [String: Any] {
    [
        "reply": reply, "thread": thread, "reply_is_thread": replyIsThread, "edit": edit,
        "edit_max_age_ms": editMaxAgeMS, "edit_max_count": 0, "unsend": unsend, "unsend_max_age_ms": unsendMaxAgeMS,
        "delete_reaches_phone": deleteReachesPhone, "hide_deleted_placeholder": hideDeletedPlaceholder,
        "poll": poll as Any? ?? NSNull(), "disappearing": NSNull(), "current_timer": NSNull(),
        "formatting": ["bold", "italic"], "mention_room": false, "max_text_length": 65536, "source": source,
    ]
}

/// A reply that stays in its thread, as the engine stores it.
func threadReply(id: String, root: String, room: String, at n: Int64, body: String? = nil,
                 mine: Bool = false) -> [String: Any] {
    var event = textEvent(id: id, room: room, at: n, body: body, mine: mine)
    event["content"] = [
        "msgtype": "m.text", "body": body ?? "Reply \(n)",
        "m.relates_to": ["rel_type": "m.thread", "event_id": root, "is_falling_back": true,
                         "m.in_reply_to": ["event_id": root]],
    ]
    return event
}

/// A thread's root: a text message with a summary of its replies.
func threadRoot(id: String, room: String, at n: Int64, replies: Int) -> [String: Any] {
    var event = textEvent(id: id, room: room, at: n, body: "Root \(n)")
    event["thread"] = ["replies": replies, "last_ts": ConversationScript.timestamp(n + Int64(replies)),
                       "last_senders": ["Ann"]]
    return event
}

/// A redaction of `target`, as the engine stores my unsend: `status` follows what the network said.
func redactionEvent(id: String, of target: String, room: String, at n: Int64, status: String) -> [String: Any] {
    [
        "event_id": id, "room_id": room, "sender": Timeline.meUserID, "sender_name": "me",
        "sender_avatar_path": "", "mine": true, "type": "m.room.redaction", "content": ["redacts": target],
        "ts": ConversationScript.timestamp(n), "seq": n, "status": status, "status_reason": "", "media_path": "",
        "bookmarked": false, "poll": NSNull(), "thread": NSNull(), "expires_at": 0,
    ]
}

/// An edit of my message `target`, as the engine stores it.
func editEvent(id: String, of target: String, room: String, at n: Int64, text: String, status: String) -> [String: Any] {
    [
        "event_id": id, "room_id": room, "sender": Timeline.meUserID, "sender_name": "me",
        "sender_avatar_path": "", "mine": true, "type": "m.room.message",
        "content": [
            "msgtype": "m.text", "body": "* " + text, "m.new_content": ["msgtype": "m.text", "body": text],
            "m.relates_to": ["rel_type": "m.replace", "event_id": target],
        ],
        "ts": ConversationScript.timestamp(n), "seq": n, "status": status, "status_reason": "", "media_path": "",
        "bookmarked": false, "poll": NSNull(), "thread": NSNull(), "expires_at": 0,
    ]
}

/// An inbox row for a chat, as the inbox would have it.
func chatRow(_ id: String, name: String, network: String = "whatsapp", direct: Bool = true) -> InboxRow {
    InboxRow(roomID: id, network: network, name: name, avatarPath: "", isDirect: direct, lastTS: 0, preview: "",
             previewKind: .text, previewMine: false, unread: 0, muted: false)
}
