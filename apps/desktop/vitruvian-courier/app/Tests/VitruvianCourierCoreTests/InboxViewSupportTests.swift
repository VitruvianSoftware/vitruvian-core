// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// What the inbox's views ask of the models: acting on the chats a context menu names, ⇧J and ⇧K, ⌃1–⌃9,
/// paging near the end, the counting sweeps, and how rows and empty lists read.
@MainActor
final class InboxViewSupportTests: XCTestCase {
    private var harnesses: [InboxHarness] = []

    override func tearDown() async throws {
        for harness in harnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        harnesses = []
    }

    private func start(_ rooms: [[String: Any]]? = nil) async throws -> InboxHarness {
        let h = try await startInbox(rooms: rooms ?? ["!a", "!b", "!c", "!d", "!e"].enumerated().map {
            room($0.element, ts: Int64(500 - $0.offset))
        }, autoRelease: true)
        harnesses.append(h)
        return h
    }

    // MARK: - Acting on the chats a menu names

    func testAContextMenuActsOnItsChatNotTheOpenOne() async throws {
        let h = try await start()
        h.inbox.select("!a")
        await h.inbox.archive(true, ids: ["!c"])
        XCTAssertEqual(dicts(h.server.receivedParams("room.setArchived")),
                       dicts([["room_ids": ["!c"], "archived": true]]), "the chat right-clicked, not the open one")
        XCTAssertEqual(h.inbox.selectedRoomID, "!a", "the open chat stays open: it wasn't archived")

        await h.inbox.togglePin(ids: ["!d"])
        XCTAssertEqual(dicts(h.server.receivedParams("room.setPinned")), dicts([["room_id": "!d", "pinned": true]]))

        await h.inbox.setHidden(true, ids: ["!b"])
        XCTAssertEqual(dicts(h.server.receivedParams("room.setHidden")), dicts([["room_ids": ["!b"], "on": true]]))

        await h.inbox.setLabel(3, on: true, ids: ["!e"])
        XCTAssertEqual(dicts(h.server.receivedParams("room.setLabel")),
                       dicts([["room_ids": ["!e"], "label_id": 3, "on": true]]))
    }

    func testMarkAsReadAndUnreadAreExplicit() async throws {
        let h = try await start([room("!a", ts: 3, unread: 2), room("!b", ts: 2), room("!c", ts: 1, markedUnread: true)])
        await h.inbox.setRead(false, ids: ["!a", "!b"])
        XCTAssertEqual(dicts(h.server.receivedParams("room.setMarkedUnread")),
                       dicts([["room_ids": ["!a", "!b"], "on": true]]), "Mark as Unread marks even an unread chat")
        XCTAssertEqual(h.count("room.markRead"), 0)

        try await waitUntil { h.inbox.rows.first { $0.roomID == "!b" }?.markedUnread == true }
        await h.inbox.setRead(true, ids: ["!b", "!c"])
        XCTAssertEqual(Set(h.server.receivedParams("room.markRead").compactMap { $0["room_id"] as? String }),
                       ["!b", "!c"], "Mark as Read reads each chat that is unread or marked unread")
    }

    func testMuteActsOnEveryTargetAndUnmutesWhenAllAre() async throws {
        let h = try await start([room("!a", ts: 3, muted: true), room("!b", ts: 2), room("!c", ts: 1, muted: true)])
        h.inbox.beginSelecting()
        h.inbox.toggleSelected("!a")
        h.inbox.toggleSelected("!b")
        await h.inbox.toggleMute()
        XCTAssertEqual(dicts(h.server.receivedParams("room.setMuted")), dicts([["room_id": "!b", "muted": true]]),
                       "one is unmuted, so the selection is muted: only the chat that isn't muted yet is asked")
        XCTAssertFalse(h.inbox.isSelecting, "a bulk action ends selecting")

        await h.inbox.toggleMute(ids: ["!a", "!c"])
        XCTAssertEqual(dicts(Array(h.server.receivedParams("room.setMuted").dropFirst())),
                       dicts([["room_id": "!a", "muted": false], ["room_id": "!c", "muted": false]]),
                       "every chat muted: Unmute")
    }

    func testTargetRowsFollowTheIdsGiven() async throws {
        let h = try await start()
        h.inbox.select("!b")
        XCTAssertEqual(h.inbox.targetRows().map(\.roomID), ["!b"])
        XCTAssertEqual(h.inbox.targetRows(["!d", "!zz", "!a"]).map(\.roomID), ["!d", "!a"],
                       "the loaded ones, in the order given")
    }

    func testEntitlementIsAskedOfTheProvider() async throws {
        let h = try await startInbox(rooms: [room("!a", ts: 1)], autoRelease: true, entitlement: OnlyReminders())
        harnesses.append(h)
        XCTAssertTrue(h.inbox.isEntitled(.reminders))
        XCTAssertFalse(h.inbox.isEntitled(.lowPriority))
    }

    // MARK: - Keys

    func testShiftJAndShiftKExtendTheSelectionFromTheOpenChat() async throws {
        let h = try await start()
        h.inbox.select("!b")
        h.inbox.extendSelection(by: 1)
        XCTAssertTrue(h.inbox.isSelecting)
        XCTAssertEqual(h.inbox.selection, ["!b", "!c"], "the open chat, then the one below")
        h.inbox.extendSelection(by: 1)
        XCTAssertEqual(h.inbox.selection, ["!b", "!c", "!d"])
        h.inbox.extendSelection(by: -1)
        h.inbox.extendSelection(by: -1)
        h.inbox.extendSelection(by: -1)
        XCTAssertEqual(h.inbox.selection, ["!a", "!b", "!c", "!d"], "back up past where it started")
        h.inbox.extendSelection(by: -1)
        XCTAssertEqual(h.inbox.selection, ["!a", "!b", "!c", "!d"], "the top stops it")

        h.inbox.endSelecting()
        h.inbox.select(nil)
        h.inbox.extendSelection(by: -1)
        XCTAssertEqual(h.inbox.selection, ["!e"], "nothing open: ⇧K takes the last chat")
    }

    func testPlainEActsOnThePointedChatOnlyWithNothingOpen() async throws {
        let h = try await start()
        XCTAssertEqual(h.inbox.plainKeyTargets(pointedAt: "!c"), ["!c"], "no chat open: the chat pointed at")
        XCTAssertEqual(h.inbox.plainKeyTargets(pointedAt: nil), [], "nothing pointed at: nothing")
        h.inbox.select("!a")
        XCTAssertEqual(h.inbox.plainKeyTargets(pointedAt: "!c"), [], "a chat is open: E is a letter")
        h.inbox.beginSelecting()
        h.inbox.toggleSelected("!d")
        XCTAssertEqual(h.inbox.plainKeyTargets(pointedAt: "!e"), ["!a", "!d"], "selecting: the selection")
    }

    func testControlNumberOpensTheNthChat() async throws {
        let h = try await start()
        h.inbox.selectChat(number: 3)
        XCTAssertEqual(h.inbox.selectedRoomID, "!c")
        h.inbox.selectChat(number: 9)
        XCTAssertEqual(h.inbox.selectedRoomID, "!c", "past the last chat, nothing happens")
        h.inbox.selectChat(number: 0)
        XCTAssertEqual(h.inbox.selectedRoomID, "!c")
    }

    func testTheLastTwentyRowsReadTheNextPage() async throws {
        let h = try await start(manyRooms(250))
        XCTAssertEqual(h.inbox.rows.count, 200)
        XCTAssertTrue(h.inbox.hasMore)
        h.inbox.rowAppeared(at: 179)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("inbox.list"), 1, "row 180 of 200 is not yet within the last 20")
        h.inbox.rowAppeared(at: 180)
        try await waitUntil { h.inbox.rows.count == 250 }
        XCTAssertFalse(h.inbox.hasMore)
        let reads = h.count("inbox.list")
        h.inbox.rowAppeared(at: 249)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("inbox.list"), reads, "the last page reads nothing more")
    }

    // MARK: - Sweeps

    func testArchiveAllCountIsADryRunOfTheSameSweep() async throws {
        let h = try await start([room("!a", ts: 2), room("!b", ts: 1, unread: 1)])
        let count = await h.inbox.archiveAllCount(readOnly: true)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(dicts(h.server.receivedParams("inbox.archiveMatching")),
                       dicts([["read_only": true, "older_than_ms": 0, "dry_run": true]]))
        XCTAssertEqual(h.count("room.setArchived"), 0)

        let none = await h.inbox.archiveAllCount(readOnly: false, space: "reminders")
        XCTAssertNil(none, "a built-in space other than the inbox can't be swept")

        h.script.fail("inbox.archiveMatching", code: -32000)
        let failed = await h.inbox.archiveAllCount(readOnly: false, olderThanDays: 7, space: "label:2")
        XCTAssertNil(failed, "couldn't check, not 0")
    }

    func testArchiveAllCanNameItsSpace() async throws {
        let h = try await start([room("!a", ts: 2), room("!b", ts: 1)])
        h.inbox.query.space = "reminders"
        try await waitUntil { h.inbox.isLoaded && h.count("inbox.list") >= 2 }
        let archived = await h.inbox.archiveAll(readOnly: false, olderThanDays: 28, space: "account:whatsapp")
        XCTAssertEqual(archived, 2)
        XCTAssertEqual(dicts(h.server.receivedParams("inbox.archiveMatching")),
                       dicts([["space": "account:whatsapp", "read_only": false, "older_than_ms": 28 * 86_400_000,
                               "dry_run": false]]), "the space named, though the space shown can't be swept")
    }

    // MARK: - How rows read

    private func row(typing: [String] = [], mutedBy: String = "", mutedByName: String = "",
                     reminder: Any = NSNull(), unread: Int = 0, markedUnread: Bool = false) throws -> InboxRow {
        var json = room("!a", ts: 1, unread: unread, markedUnread: markedUnread)
        json["typing"] = typing
        json["muted_by"] = mutedBy
        json["muted_by_name"] = mutedByName
        json["reminder"] = reminder
        return try JSONDecoder().decode(InboxRow.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testTypingLine() throws {
        XCTAssertNil(try row().typingLine)
        XCTAssertEqual(try row(typing: ["Sam"]).typingLine, "Sam is typing…")
        XCTAssertEqual(try row(typing: ["Sam", "Alex", "Jo"]).typingLine, "3 people are typing…")
    }

    /// The row's tick is only for my newest message that went, and follows preview_status; the account tag only
    /// when the engine names the chat's account.
    func testTheRowsTickAndAccountTag() throws {
        func row(mine: Bool, status: String, login: String = "") throws -> InboxRow {
            var json = room("!a", ts: 1)
            json["preview_mine"] = mine
            json["preview_status"] = status
            json["login_name"] = login
            return try JSONDecoder().decode(InboxRow.self, from: JSONSerialization.data(withJSONObject: json))
        }
        XCTAssertEqual(try row(mine: true, status: "sent").previewTick, .sent)
        XCTAssertEqual(try row(mine: true, status: "delivered").previewTick, .delivered)
        XCTAssertEqual(try row(mine: true, status: "seen").previewTick, .seen)
        XCTAssertNil(try row(mine: true, status: "").previewTick, "mine, not gone yet (or a note)")
        XCTAssertNil(try row(mine: false, status: "seen").previewTick, "someone else's message has no tick")
        XCTAssertNil(try row(mine: true, status: "read_twice").previewTick, "a value this app doesn't know")
        XCTAssertEqual([PreviewTick.sent, .delivered, .seen].map(\.marks), [1, 2, 2])
        XCTAssertEqual([PreviewTick.sent, .delivered, .seen].map(\.label), ["Sent", "Delivered", "Seen"])

        XCTAssertNil(try row(mine: false, status: "").accountTag)
        XCTAssertEqual(try row(mine: false, status: "", login: "+1 555 0101").accountTag, "+1 555 0101")
    }

    /// The status strip says "Starting…" before "Reconnecting…", nothing for a connected account, and names the
    /// account in its tooltip only when the network has more than one.
    func testStatusItemLabelsAndTooltips() {
        let starting = AccountStatusItem(network: "signal", displayName: "Signal", isReconnecting: true, isStarting: true)
        XCTAssertEqual(starting.statusLabel, "Starting…")
        XCTAssertEqual(starting.tooltip, "Signal: Starting…")
        let reconnecting = AccountStatusItem(network: "whatsapp", displayName: "WhatsApp", isReconnecting: true,
                                             accountID: "a2", accountName: "+1 555 0102")
        XCTAssertEqual(reconnecting.statusLabel, "Reconnecting…")
        XCTAssertEqual(reconnecting.tooltip, "WhatsApp (+1 555 0102): Reconnecting…")
        let connected = AccountStatusItem(network: "telegram", displayName: "Telegram", isReconnecting: false)
        XCTAssertNil(connected.statusLabel)
        XCTAssertEqual(connected.tooltip, "Telegram")
    }

    func testMutedLineNamesWhatMutesIt() throws {
        XCTAssertNil(try row().mutedLine)
        XCTAssertEqual(try row(mutedBy: "label", mutedByName: "Work").mutedLine, "Muted by Work")
        XCTAssertEqual(try row(mutedBy: "account", mutedByName: "WhatsApp").mutedLine, "Muted by WhatsApp")
    }

    func testReminderBadgeAndUnreadDot() throws {
        XCTAssertFalse(try row().reminderFired)
        XCTAssertFalse(try row(reminder: ["due_at": 5, "condition": "always", "fired": false]).reminderFired)
        XCTAssertTrue(try row(reminder: ["due_at": 5, "condition": "always", "fired": true]).reminderFired)
        XCTAssertTrue(try row(markedUnread: true).showsUnreadDot)
        XCTAssertFalse(try row(unread: 2, markedUnread: true).showsUnreadDot, "a count says it already")
    }

    // MARK: - Empty lists

    func testEveryBuiltInSpaceAndFilterHasItsEmptyState() {
        func state(_ space: String = "inbox", _ filters: Set<InboxFilter> = []) -> EmptyState {
            EmptyState.of(InboxQuery(space: space, filters: filters))
        }
        XCTAssertEqual(state(), EmptyState(title: "You’re all caught up", line: "New messages show up here."))
        XCTAssertEqual(state("account:whatsapp").title, "You’re all caught up")
        XCTAssertEqual(state("archive"), EmptyState(
            title: "Nothing archived",
            line: "Archive a chat to clear it from your inbox. It comes back when someone writes."))
        XCTAssertEqual(state("low_priority").title, "Nothing in Low Priority")
        XCTAssertEqual(state("requests").title, "No message requests")
        XCTAssertEqual(state("reminders").line,
                       "Right-click a chat and choose Remind Me. It comes back to your inbox at that time.")
        XCTAssertEqual(state("send_later"), EmptyState(title: "No scheduled messages",
                                                       line: "Messages you schedule show up here."))
        XCTAssertEqual(state("label:4"), EmptyState(title: "No chats with this label",
                                                    line: "Right-click a chat and choose Label."))

        XCTAssertEqual(state("inbox", [.unread]), EmptyState(title: "No unread chats"))
        XCTAssertEqual(state("inbox", [.drafts]).line,
                       "A chat shows up here when you start a message and don’t send it.")
        XCTAssertEqual(state("inbox", [.unanswered]).title, "Nothing waiting for your answer")
        XCTAssertEqual(state("inbox", [.noReply]).title, "No one owes you a reply")
        XCTAssertEqual(state("inbox", [.dms]).title, "No one-to-one chats")
        XCTAssertEqual(state("inbox", [.groups]).title, "No group chats")
        XCTAssertEqual(state("inbox", [.unknown]).title, "No chats from unknown numbers")
        XCTAssertEqual(state("inbox", [.muted]).title, "No muted chats")
        XCTAssertEqual(state("inbox", [.hidden]).line, "Hide a chat to take it out of your inbox without leaving it.")
        XCTAssertEqual(state("inbox", [.lowPriority]).line,
                       "Chats here stay out of your inbox, even when new messages arrive.")
        XCTAssertEqual(state("inbox", [.requests]).line,
                       "Messages from people you haven’t chatted with before show up here.")

        // A filter says more than the space; a place filter more than the others.
        XCTAssertEqual(state("label:4", [.unread]).title, "No unread chats")
        XCTAssertEqual(state("inbox", [.unread, .archived]).title, "Nothing archived")
        // Every filter has one of its own.
        let titles = Set(InboxFilter.allCases.map { state("inbox", [$0]).title })
        XCTAssertEqual(titles.count, InboxFilter.allCases.count)
    }

    // MARK: - What reaches the phone

    func testSyncHelpSaysWhatReachesThePhone() {
        let accounts = [
            Account(network: "whatsapp", displayName: "WhatsApp", flows: [], state: .connected, syncs: [.pin, .mute]),
            Account(network: "signal", displayName: "Signal", flows: [], state: .connected, syncs: [.acceptRequest]),
        ]
        XCTAssertEqual(SyncReach.of(.pin, networks: ["whatsapp"], accounts: accounts), .all)
        XCTAssertEqual(SyncReach.of(.pin, networks: ["signal"], accounts: accounts), .none)
        XCTAssertEqual(SyncReach.of(.pin, networks: ["signal", "whatsapp"], accounts: accounts), .some)
        XCTAssertEqual(SyncReach.of(.mute, networks: ["slack"], accounts: accounts), .none, "an unlisted network")
        XCTAssertEqual(SyncReach.of(.mute, networks: [], accounts: accounts), .none)

        XCTAssertEqual(SyncHelp.pin(true, reach: .all), "Also pinned on your phone when it’s connected")
        XCTAssertEqual(SyncHelp.pin(true, reach: .none), "Pinned on this Mac only")
        XCTAssertEqual(SyncHelp.mute(true, reach: .all), "Also muted on your phone when it’s connected")
        XCTAssertEqual(SyncHelp.pin(false, reach: .some),
                       "Also unpinned on your phone where its network takes pins, when it’s connected",
                       "an offline account isn't sent the change later, so the help says when it goes")
        XCTAssertEqual(SyncHelp.mute(false, reach: .none), "Unmuted on this Mac only")
        XCTAssertEqual(SyncHelp.markUnread, "On this Mac only", "no network is ever sent an unread mark")
    }
}

/// The Edit Spaces list and the rules the settings and auto-archive sections set.
@MainActor
final class SpacesAndRulesViewSupportTests: XCTestCase {
    private var harnesses: [InboxHarness] = []

    override func tearDown() async throws {
        for harness in harnesses {
            await harness.app.stop()
            harness.cleanUp()
        }
        harnesses = []
    }

    private func spaces(_ ids: [String], hidden: Set<String> = []) -> [Space] {
        ids.map { Space(spaceID: $0, kind: $0.hasPrefix("label:") ? .label : .builtin, hidden: hidden.contains($0)) }
    }

    func testDraggingBelowTheDividerHidesAndTheInboxStaysFirst() {
        var draft = SpacesLayoutDraft(spaces: spaces(["inbox", "reminders", "archive", "label:1"], hidden: ["archive"]))
        XCTAssertEqual(draft.entries, [.space("inbox"), .space("reminders"), .space("label:1"), .divider, .space("archive")],
                       "the shown spaces, the divider, then the hidden ones")
        XCTAssertEqual(draft.order, ["inbox", "reminders", "label:1", "archive"])
        XCTAssertEqual(draft.hidden, ["archive"])

        // reminders dragged to the very end: below the divider, so hidden.
        draft.move(fromOffsets: [1], toOffset: 5)
        XCTAssertEqual(draft.hidden, ["archive", "reminders"])
        XCTAssertEqual(draft.order, ["inbox", "label:1", "archive", "reminders"])

        // archive dragged above the inbox: shown again, and the inbox is still first.
        draft.move(fromOffsets: [3], toOffset: 0)
        XCTAssertEqual(draft.order.first, "inbox")
        XCTAssertEqual(draft.hidden, ["reminders"])
        XCTAssertEqual(draft.order, ["inbox", "archive", "label:1", "reminders"])

        // The inbox can't be dragged below the divider.
        draft.move(fromOffsets: [0], toOffset: 5)
        XCTAssertEqual(draft.order.first, "inbox")
        XCTAssertFalse(draft.isHidden("inbox"))
    }

    func testTheEyeButtonHidesAndShows() {
        var draft = SpacesLayoutDraft(spaces: spaces(["inbox", "reminders", "archive"]))
        XCTAssertEqual(draft.hidden, [], "no hidden spaces")
        draft.setHidden("reminders", true)
        XCTAssertEqual(draft.hidden, ["reminders"])
        XCTAssertEqual(draft.entries, [.space("inbox"), .space("archive"), .divider, .space("reminders")])
        draft.setHidden("reminders", false)
        XCTAssertEqual(draft.entries, [.space("inbox"), .space("archive"), .space("reminders"), .divider],
                       "shown again at the end of the bar")
        draft.setHidden("inbox", true)
        XCTAssertEqual(draft.hidden, [], "the inbox is never hidden")
    }

    private func labels(rules: [[String: Any]] = []) async throws -> (InboxHarness, LabelsModel) {
        let h = try await startInbox(rooms: [room("!a", ts: 1)], autoRelease: true)
        harnesses.append(h)
        h.script.rules = rules
        let labels = LabelsModel(appModel: h.app)
        try await waitUntil { h.count("autoArchive.list") >= 1 }
        try await waitUntil { labels.autoArchiveRules.count == rules.count }
        return (h, labels)
    }

    func testTheGeneralSettingIsOneRuleScopedAll() async throws {
        let (h, labels) = try await labels(rules: [
            ["rule_id": 4, "scope": "label:2", "trigger": "older_than", "chat_type": "all", "duration_ms": 259_200_000,
             "enabled": true],
        ])
        XCTAssertNil(labels.generalRule, "a space's rule is not the General setting")

        try await labels.setGeneral(.afterRead, minutes: 10)
        XCTAssertEqual(dicts(h.server.receivedParams("autoArchive.set")), dicts([[
            "rule_id": 0, "scope": "all", "trigger": "after_read", "chat_type": "read", "duration_ms": 600_000,
            "enabled": true,
        ]]), "after I read archives only chats left read")
        let made = try XCTUnwrap(labels.generalRule)

        try await labels.setGeneral(.afterReply, minutes: 0)
        XCTAssertEqual(h.server.receivedParams("autoArchive.set").last as NSDictionary?, [
            "rule_id": made.ruleID, "scope": "all", "trigger": "after_reply", "chat_type": "all", "duration_ms": 0,
            "enabled": true,
        ] as NSDictionary, "the same rule, changed: there is only ever one")

        try await labels.setGeneral(nil, minutes: 0)
        XCTAssertEqual(dicts(h.server.receivedParams("autoArchive.delete")), dicts([["rule_id": made.ruleID]]))
        XCTAssertNil(labels.generalRule, "Never")
        try await labels.setGeneral(nil, minutes: 0)
        XCTAssertEqual(h.count("autoArchive.delete"), 1, "Never again asks nothing")
    }

    func testASpacesSweepRuleIsKeptAndChanged() async throws {
        let (h, labels) = try await labels(rules: [
            ["rule_id": 4, "scope": "label:2", "trigger": "older_than", "chat_type": "all", "duration_ms": 259_200_000,
             "enabled": true],
        ])
        try await labels.setSweep(for: "label:2", chatType: .read, days: 90, enabled: false)
        XCTAssertEqual(dicts(h.server.receivedParams("autoArchive.set")), dicts([[
            "rule_id": 4, "scope": "label:2", "trigger": "older_than", "chat_type": "read",
            "duration_ms": 90 * 86_400_000, "enabled": false,
        ]]), "turned off, its choices kept")

        try await labels.setSweep(for: "account:whatsapp", chatType: .all, days: 3, enabled: true)
        XCTAssertEqual(h.server.receivedParams("autoArchive.set").last?["rule_id"] as? Int, 0, "a new rule")
        XCTAssertEqual(LabelsModel.sweepAges, [3, 7, 14, 28, 90, 365])
        XCTAssertEqual(LabelsModel.nearestSweepAge(30), 28)
        XCTAssertEqual(LabelsModel.nearestSweepAge(5), 3, "a tie takes the shorter")
        XCTAssertEqual(LabelsModel.nearestSweepAge(1000), 365)
        XCTAssertEqual(LabelsModel.nearestSweepAge(90), 90)
        XCTAssertEqual(LabelsModel.generalDelays, [0, 1, 5, 10, 30, 60, 240, 1440, 10080])
    }
}

/// A plan with reminders and nothing else.
private struct OnlyReminders: EntitlementProvider {
    func isEntitled(_ feature: Feature) -> Bool { feature == .reminders }
}
