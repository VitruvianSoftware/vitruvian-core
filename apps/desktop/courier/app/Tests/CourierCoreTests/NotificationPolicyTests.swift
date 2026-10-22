// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// When a message notifies, what the notification says, and how the Dock badge reads. All plain values.
final class NotificationPolicyTests: XCTestCase {
    private let connectedAt: Int64 = 1_000_000
    private let now: Int64 = 1_030_000

    // MARK: - Fixtures

    private func context(open: String? = nil, key: Bool = false, now: Int64? = nil,
                         requestNotifications: Bool = true) -> NotificationPolicy.Context {
        NotificationPolicy.Context(me: Timeline.meUserID, connectedAt: connectedAt, now: now ?? self.now,
                                   openRoomID: open, isLooking: key, requestNotifications: requestNotifications)
    }

    private func row(_ id: String = "!a", name: String = "Chat A", direct: Bool = true, unread: Int = 0,
                     muted: Bool = false, archived: Bool = false, lowPriority: Bool = false, hidden: Bool = false,
                     markedUnread: Bool = false, request: Bool = false, mutedBy: MutedBy = .none) -> InboxRow {
        InboxRow(roomID: id, network: "whatsapp", name: name, avatarPath: "", isDirect: direct, lastTS: 0, preview: "",
                 previewKind: .text, previewMine: false, unread: unread, muted: muted, archived: archived,
                 lowPriority: lowPriority, hidden: hidden, markedUnread: markedUnread, request: request,
                 mutedBy: mutedBy, mutedByName: mutedBy == .none ? "" : "Somebody")
    }

    private func event(_ id: String = "$1", room: String = "!a", type: String = "m.room.message", mine: Bool = false,
                       ts: Int64? = nil, content: JSONValue? = nil, sender: String = "@other:courier.local",
                       senderName: String = "Sam") -> Event {
        Event(eventID: id, roomID: room, sender: mine ? Timeline.meUserID : sender, senderName: senderName,
              mine: mine, type: type, content: content ?? .object(["msgtype": .string("m.text"), "body": .string("hi")]),
              ts: ts ?? 1_020_000, seq: 1, status: .sent)
    }

    // MARK: - When to notify

    func testALiveMessageFromSomeoneElseNotifies() {
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: event(), room: row(), context: context()))
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: event(type: "m.sticker"), room: row(), context: context()))
    }

    func testBackfilledMessagesDoNotNotify() {
        // Before the app connected: the first sync's history.
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: event(ts: connectedAt - 1), room: row(), context: context()))
        // After it connected, but long enough ago that it is not live: a slow bridge catching up.
        let late = context(now: 1_020_000 + 121_000)
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: event(ts: 1_020_000), room: row(), context: late))
        // The edges: exactly when it connected, and exactly 120 seconds old, are live.
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: event(ts: connectedAt), room: row(), context: context()))
        let edge = context(now: 1_020_000 + 120_000)
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: event(ts: 1_020_000), room: row(), context: edge))
    }

    func testOwnMessagesDoNotNotify() {
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: event(mine: true), room: row(), context: context()))
        // A message of mine from another device may not be flagged; its sender is me.
        var sent = event()
        sent.sender = Timeline.meUserID
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: sent, room: row(), context: context()))
    }

    func testMutedDoesNotNotify() {
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: event(), room: row(muted: true), context: context()))
    }

    func testMutedByLabelDoesNotNotify() {
        let live = event()
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: live, room: row(mutedBy: .label), context: context()))
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: live, room: row(mutedBy: .account), context: context()))
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: live, room: row(), context: context()), "control")
    }

    func testLowPriorityAndHiddenDoNotNotify() {
        let live = event()
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: live, room: row(lowPriority: true), context: context()))
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: live, room: row(hidden: true), context: context()))
        // An archived chat is not one of them: its message brings it back, and it notifies as before.
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: live, room: row(archived: true), context: context()))
    }

    func testRequestsNotifyOnlyWhenTheSettingIsOn() {
        let live = event()
        let request = row(request: true)
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: live, room: request, context: context(requestNotifications: true)))
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: live, room: request, context: context(requestNotifications: false)))
        // The setting is about requests only.
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: live, room: row(), context: context(requestNotifications: false)))
    }

    func testOpenAndFocusedChatDoesNotNotify() {
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: event(), room: row(), context: context(open: "!a", key: true)))
        // The chat is open, but the person is not looking at it: the window is not the one being used, or the
        // screen is locked or asleep, or they are away (Attention decides; the policy is told).
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: event(), room: row(), context: context(open: "!a", key: false)))
    }

    func testOtherChatNotifiesWhileFocused() {
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: event(room: "!b"), room: row("!b"),
                                                      context: context(open: "!a", key: true)))
    }

    func testReactionsAndEditsDoNotNotify() {
        let reaction = event(type: "m.reaction", content: .object([
            "m.relates_to": .object(["rel_type": .string("m.annotation"), "event_id": .string("$0"), "key": .string("👍")]),
        ]))
        let edit = event(content: .object([
            "msgtype": .string("m.text"), "body": .string("* hi"),
            "m.relates_to": .object(["rel_type": .string("m.replace"), "event_id": .string("$0")]),
            "m.new_content": .object(["msgtype": .string("m.text"), "body": .string("hi")]),
        ]))
        let redaction = event(type: "m.room.redaction", content: .object(["redacts": .string("$0")]))
        let undecryptable = event(type: "m.room.encrypted", content: .object([:]))
        for other in [reaction, edit, redaction, undecryptable] {
            XCTAssertFalse(NotificationPolicy.shouldNotify(event: other, room: row(), context: context()), other.type)
        }
        // A reply is a message, not an edit.
        let reply = event(content: .object([
            "msgtype": .string("m.text"), "body": .string("yes"),
            "m.relates_to": .object(["m.in_reply_to": .object(["event_id": .string("$0")])]),
        ]))
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: reply, room: row(), context: context()))
    }

    /// Ruling 17: someone starting a poll is a message, so it notifies (and counts as unread, TimelineTests); a vote
    /// or the poll ending doesn't.
    func testAnIncomingPollNotifies() {
        var poll = event(type: Timeline.pollStartType, content: .object([
            "org.matrix.msc1767.text": .string("Lunch?\n1. Noon\n2. One"),
        ]))
        poll.poll = PollTally(question: "Lunch?", options: [], maxSelections: 1, voters: 0, mine: [], ended: false)
        XCTAssertTrue(NotificationPolicy.shouldNotify(event: poll, room: row(), context: context()))
        XCTAssertEqual(NotificationPolicy.content(for: poll, room: row()).body, "Poll Lunch?")
        for type in ["org.matrix.msc3381.poll.response", "org.matrix.msc3381.poll.end"] {
            XCTAssertFalse(NotificationPolicy.shouldNotify(event: event(type: type, content: .object([:])), room: row(),
                                                           context: context()), type)
        }
        XCTAssertFalse(NotificationPolicy.shouldNotify(event: event(type: Timeline.pollStartType, mine: true), room: row(),
                                                       context: context()), "my own poll")
    }

    // MARK: - Reminders and the buttons

    func testAReminderSaysWhatItIsFor() {
        let content = NotificationPolicy.reminderContent(room: row(name: "Chat A", muted: true))
        XCTAssertEqual(content.title, "Chat A")
        XCTAssertEqual(content.body, "You asked to be reminded about this chat.")
        XCTAssertNil(content.subtitle)
        XCTAssertEqual(content.roomID, "!a")
        XCTAssertEqual(content.category, .reminder)
        XCTAssertEqual(content.userInfo, ["room_id": "!a"], "no text, no names")
        XCTAssertEqual(NotificationPolicy.reminderContent(room: row(name: "")).title, "Courier")
        // A message is a message.
        XCTAssertEqual(NotificationPolicy.content(for: event(), room: row()).category, .message)
    }

    func testEachReminderMakesItsOwnNotification() {
        let first = NotificationPolicy.reminderContent(room: row())
        let second = NotificationPolicy.reminderContent(room: row())
        XCTAssertNotEqual(first.eventID, second.eventID, "an id is the system's key: one reminder must not replace another")
    }

    func testRemindActionsHiddenWhenNotEntitled() {
        struct NoReminders: EntitlementProvider {
            func isEntitled(_ feature: Feature) -> Bool { feature != .reminders }
        }
        let plan = AlwaysEntitled()
        XCTAssertEqual(NotificationCategory.message.actions(entitlement: plan),
                       [.markRead, .reply, .remindOneHour, .remindEightHours])
        XCTAssertEqual(NotificationCategory.scheduled.actions(entitlement: plan), [],
                       "a scheduled message that didn't go has nothing to mark read or remind about")
        XCTAssertEqual(NotificationCategory.reminder.actions(entitlement: plan),
                       [.markRead, .remindOneHour, .remindEightHours])
        XCTAssertEqual(NotificationCategory.message.actions(entitlement: NoReminders()), [.markRead, .reply])
        XCTAssertEqual(NotificationCategory.reminder.actions(entitlement: NoReminders()), [.markRead])
    }

    // MARK: - The Dock badge

    func testBadgeIsEmptyAtZero() {
        XCTAssertNil(NotificationPolicy.badgeLabel(count: 0))
        XCTAssertEqual(NotificationPolicy.badgeLabel(count: 3), "3")
        XCTAssertEqual(NotificationPolicy.badgeLabel(count: 1200), "1200")
    }

    // MARK: - What the notification says

    func testDirectChatShowsTheChatNameAndTheText() {
        let content = NotificationPolicy.content(for: event(), room: row(name: "Chat A"))
        XCTAssertEqual(content.title, "Chat A")
        XCTAssertNil(content.subtitle)
        XCTAssertEqual(content.body, "hi")
        XCTAssertEqual(content.threadIdentifier, "!a")
        XCTAssertEqual(content.userInfo, ["room_id": "!a"])
        XCTAssertEqual(content.eventID, "$1")
    }

    func testGroupShowsTheSenderAsSubtitle() {
        let content = NotificationPolicy.content(for: event(senderName: "Sam"), room: row(name: "Group", direct: false))
        XCTAssertEqual(content.title, "Group")
        XCTAssertEqual(content.subtitle, "Sam")
        // No sender name known: no subtitle rather than an empty one.
        XCTAssertNil(NotificationPolicy.content(for: event(senderName: ""), room: row(direct: false)).subtitle)
    }

    func testMediaShowsItsTypeLabel() {
        func body(_ msgtype: String, extra: [String: JSONValue] = [:]) -> String {
            var content: [String: JSONValue] = ["msgtype": .string(msgtype), "body": .string("IMG_0001.jpg")]
            for (key, value) in extra { content[key] = value }
            return NotificationPolicy.content(for: event(content: .object(content)), room: row()).body
        }
        XCTAssertEqual(body("m.image"), "Image")
        XCTAssertEqual(body("m.video"), "Video")
        XCTAssertEqual(body("m.file"), "File")
        XCTAssertEqual(body("m.audio", extra: ["org.matrix.msc3245.voice": .object([:])]), "Voice note")
        let sticker = event(type: "m.sticker", content: .object(["body": .string("wave")]))
        XCTAssertEqual(NotificationPolicy.content(for: sticker, room: row()).body, "Sticker")
        // A caption follows the label.
        XCTAssertEqual(body("m.image", extra: ["filename": .string("IMG_0001.jpg"), "body": .string("look")]), "Image look")
    }

    func testLongTextIsCutShort() {
        let long = String(repeating: "word ", count: 200)
        let content = NotificationPolicy.content(
            for: event(content: .object(["msgtype": .string("m.text"), "body": .string(long)])), room: row())
        XCTAssertLessThanOrEqual(content.body.count, NotificationPolicy.maxBodyLength + 1)
        XCTAssertTrue(content.body.hasSuffix("…"))
        // Short text is untouched.
        let short = NotificationPolicy.content(for: event(), room: row())
        XCTAssertEqual(short.body, "hi")
    }

    func testNoNamesAtAllStillGivesATitle() {
        let content = NotificationPolicy.content(for: event(senderName: ""), room: row(name: ""))
        XCTAssertEqual(content.title, "Courier")
    }

    func testRedactedMessagesInAPageAreFound() {
        let gone = event("$gone")
        let redaction = event("$r", type: "m.room.redaction", content: .object(["redacts": .string("$gone")]))
        var failed = event("$r2", type: "m.room.redaction", content: .object(["redacts": .string("$other")]))
        failed.status = .failed
        XCTAssertEqual(NotificationPolicy.redactedEventIDs(in: [gone, redaction, failed, event("$keep")]), ["$gone"])
    }

    func testAReplyShowsOnlyItsOwnText() {
        let reply = event(content: .object([
            "msgtype": .string("m.text"), "body": .string("> <@x:y> quoted\n\nmy answer"),
            "m.relates_to": .object(["m.in_reply_to": .object(["event_id": .string("$0")])]),
        ]))
        XCTAssertEqual(NotificationPolicy.content(for: reply, room: row()).body, "my answer")
    }

    // MARK: - Telling each only once

    func testSeenEventsAreRememberedOnceAndForgottenOldestFirst() {
        var seen = SeenEvents(capacity: 3)
        XCTAssertTrue(seen.insert("$1"))
        XCTAssertFalse(seen.insert("$1"))
        XCTAssertTrue(seen.insert("$2"))
        XCTAssertTrue(seen.insert("$3"))
        XCTAssertTrue(seen.insert("$4"), "$1 is forgotten to make room")
        XCTAssertEqual(seen.count, 3)
        XCTAssertFalse(seen.insert("$4"))
        XCTAssertTrue(seen.insert("$1"), "the oldest was forgotten")
    }
}
