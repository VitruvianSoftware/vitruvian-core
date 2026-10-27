// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation

/// Made-up chats and messages for the snapshots. No real names, numbers or messages.
enum Fixture {
    /// 2026-10-20 14:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_792_504_800)
    static let room = "!chat:courier.local"
    static let ann = "@ann:courier.local"

    static func millis(_ minutesAgo: Int) -> Int64 {
        Int64(now.timeIntervalSince1970 * 1000) - Int64(minutesAgo) * 60_000
    }

    static func event(_ id: String, type: String = "m.room.message", mine: Bool, ts minutesAgo: Int,
                      content: [String: JSONValue], status: EventStatus = .sent, reason: String = "",
                      bookmarked: Bool = false, poll: PollTally? = nil, thread: ThreadSummary? = nil,
                      expiresAt: Int64 = 0, sender: String? = nil, name: String = "Ann Example",
                      delivered: Bool = false, readBy: [Reader] = []) -> Event {
        Event(eventID: id, roomID: room, sender: sender ?? (mine ? Timeline.meUserID : ann),
              senderName: mine ? "" : name, mine: mine, type: type, content: .object(content),
              ts: millis(minutesAgo), seq: Int64(10000 - minutesAgo), status: status, statusReason: reason,
              bookmarked: bookmarked, poll: poll, thread: thread, expiresAt: expiresAt, delivered: delivered,
              readBy: readBy)
    }

    static func text(_ id: String, _ body: String, mine: Bool, ts minutesAgo: Int, html: String? = nil,
                     status: EventStatus = .sent, reason: String = "", bookmarked: Bool = false,
                     thread: ThreadSummary? = nil, expiresAt: Int64 = 0, sender: String? = nil,
                     name: String = "Ann Example", delivered: Bool = false, readBy: [Reader] = []) -> Event {
        var content: [String: JSONValue] = ["msgtype": .string("m.text"), "body": .string(body)]
        if let html {
            content["format"] = .string("org.matrix.custom.html")
            content["formatted_body"] = .string(html)
        }
        return event(id, mine: mine, ts: minutesAgo, content: content, status: status, reason: reason,
                     bookmarked: bookmarked, thread: thread, expiresAt: expiresAt, sender: sender, name: name,
                     delivered: delivered, readBy: readBy)
    }

    /// An edit of `target`, as the engine stores it.
    static func edit(_ id: String, of target: String, _ body: String, ts minutesAgo: Int,
                     status: EventStatus = .sent) -> Event {
        event(id, mine: true, ts: minutesAgo, content: [
            "msgtype": .string("m.text"), "body": .string("* " + body),
            "m.new_content": .object(["msgtype": .string("m.text"), "body": .string(body)]),
            "m.relates_to": .object(["rel_type": .string("m.replace"), "event_id": .string(target)]),
        ], status: status)
    }

    static func poll(_ id: String, mine: Bool, ts minutesAgo: Int, tally: PollTally) -> Event {
        event(id, type: Timeline.pollStartType, mine: mine, ts: minutesAgo,
              content: ["body": .string(tally.question)], poll: tally)
    }

    static func timerNote(_ id: String, mine: Bool, ts minutesAgo: Int, timerMS: Int64) -> Event {
        event(id, mine: mine, ts: minutesAgo, content: [
            "msgtype": .string("m.notice"), "body": .string("Set the disappearing message timer"),
            "com.beeper.action_message": .object([
                "type": .string("disappearing_timer"), "timer": .int(timerMS), "timer_type": .string("after_send"),
                "implicit": .bool(false),
            ]),
        ])
    }

    /// A bridge's call notice as the engine stores it: the bridge's English body, and Courier's reading beside it.
    static func callNote(_ id: String, mine: Bool, ts minutesAgo: Int, body: String, state: String,
                         media: String) -> Event {
        event(id, mine: mine, ts: minutesAgo, content: [
            "msgtype": .string("m.notice"), "body": .string(body),
            "com.beeper.action_message": .object(["type": .string("call")]),
            "fi.courier.call": .object(["state": .string(state), "media": .string(media)]),
        ])
    }

    static func items(_ events: [Event], isDirect: Bool = false) -> [TimelineItem] {
        Timeline.build(events: events, me: Timeline.meUserID, now: now, isDirect: isDirect)
    }

    /// A chat in the inbox, its newest message `minutesAgo`.
    static func row(_ id: String, _ name: String, network: String = "whatsapp", direct: Bool = true,
                    ts minutesAgo: Int, preview: String, mine: Bool = false, unread: Int = 0,
                    status: PreviewStatus = .none, login: String = "", typing: [String] = []) -> InboxRow {
        InboxRow(roomID: id, network: network, name: name, avatarPath: "", isDirect: direct,
                 lastTS: millis(minutesAgo), preview: preview, previewKind: .text, previewMine: mine, unread: unread,
                 muted: false, typing: typing, previewStatus: status, loginName: login)
    }

    static func messages(_ events: [Event]) -> [TimelineMessage] {
        items(events).compactMap { if case let .message(message) = $0 { message } else { nil } }
    }

    /// What WhatsApp's chats can do, with every formatting kind but spoilers.
    static let features = ChatFeatures(
        reply: true, edit: true, editMaxAgeMS: 15 * 60_000, unsend: true, unsendMaxAgeMS: 2 * 86_400_000,
        poll: PollFeatures(maxOptions: 12, optionMaxLength: 100),
        disappearing: DisappearingFeatures(type: .afterSend, timersMS: [86_400_000, 604_800_000, 7_776_000_000]),
        formatting: [.bold, .italic, .strikethrough, .code, .pre, .blockquote, .bulletList, .orderedList, .link,
                     .mention],
        maxTextLength: 65536, source: .stored,
        gifFeatures: FileKindFeatures(supported: true, mimeTypes: ["image/gif", "video/mp4"], caption: true),
        stickerFeatures: FileKindFeatures(supported: true, mimeTypes: ["image/png", "image/webp", "image/gif"]))

    /// Every formatting kind, as another app's HTML would bring it.
    static let formattedHTML = """
    Plain, <strong>bold</strong>, <em>italic</em>, <del>struck</del>, <code>code()</code>, a \
    <a href="https://example.test/page">link</a>, <a href="https://matrix.to/#/@bo:courier.local">Bo</a> and \
    <span data-mx-spoiler>a secret</span>.<blockquote>A quoted line</blockquote><ul><li>First item</li>\
    <li>Second item</li></ul><ol><li>One</li><li>Two</li></ol><pre><code>let answer = 42 // a long line of code \
    that scrolls sideways rather than wrapping</code></pre>Last line.
    """

    // MARK: - Part 4.5a: Chat Info fixtures

    static func mediaEvent(_ id: String, msgtype: String, body: String, size: Int? = nil, ts minutesAgo: Int) -> Event {
        var content: [String: JSONValue] = ["msgtype": .string(msgtype), "body": .string(body)]
        if let size {
            content["info"] = .object(["size": .int(Int64(size))])
        }
        return event(id, mine: false, ts: minutesAgo, content: content)
    }

    /// 1:1 DM with override name ("Alice (Work)") and network name ("Alice Example") per Ruling 1,
    /// phone number `+1 555-010-0101`, timezone `America/Los_Angeles`, Shared Media, Links, Bookmarks, and Encryption.
    static func directChatInfo() -> RoomInfoResult {
        RoomInfoResult(
            roomID: "!dm-alice:courier.local",
            name: "Alice (Work)",
            remoteName: "Alice Example",
            localName: "Alice (Work)",
            topic: "",
            avatarPath: "",
            localAvatarURI: "",
            network: "whatsapp",
            accountID: "whatsapp-1",
            isDirect: true,
            encrypted: true,
            disappearingMS: 0,
            pinnedEventIDs: ["$pin1"],
            members: [
                Member(
                    userID: "@wa_alice:courier.local",
                    name: "Alice Example",
                    avatarPath: "",
                    powerLevel: 0,
                    isAdmin: false,
                    identifiers: ["+1 555-010-0101"],
                    tz: "America/Los_Angeles",
                    isBot: false
                ),
            ],
            sharedMedia: [
                mediaEvent("$m1", msgtype: "m.image", body: "Trail map.jpg", ts: 10),
                mediaEvent("$m2", msgtype: "m.image", body: "Summit view.jpg", ts: 11),
                mediaEvent("$m3", msgtype: "m.video", body: "Campfire.mp4", ts: 12),
            ],
            sharedFiles: [
                mediaEvent("$f1", msgtype: "m.file", body: "Itinerary.pdf", size: 248_000, ts: 14),
            ],
            sharedLinks: [
                RoomLink(
                    eventID: "$l1",
                    sender: "@wa_alice:courier.local",
                    ts: millis(15),
                    url: "https://example.com/trail-guide",
                    host: "example.com"
                ),
            ],
            features: features
        )
    }

    /// Bookmarked messages in the direct chat, for the Bookmarks section of Chat Info.
    static func chatInfoBookmarks() -> [MessageHit] {
        [
            MessageHit(
                eventID: "$b1",
                roomID: "!dm-alice:courier.local",
                roomName: "Alice (Work)",
                network: "whatsapp",
                isDirect: true,
                place: .inbox,
                sender: "@wa_alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: millis(16),
                seq: 16,
                kind: .text,
                snippet: "Don’t forget the trail pass and headlamp",
                ranges: [],
                mediaPath: ""
            ),
        ]
    }

    /// Group chat with 3 members (including Admin and Bot badges), Add Participants button (`canInvite: true`),
    /// and Disappearing Messages active (7 days).
    static func groupChatInfoWithAdmins() -> RoomInfoResult {
        var groupFeatures = features
        groupFeatures.canSetName = true
        groupFeatures.canSetTopic = true
        groupFeatures.canSetAvatar = true
        groupFeatures.canInvite = true
        groupFeatures.canKick = true
        groupFeatures.canSetAdmin = true
        groupFeatures.canLeave = true
        groupFeatures.currentTimer = DisappearingTimer(type: .afterSend, timerMS: 604_800_000)

        return RoomInfoResult(
            roomID: "!grp-hike:courier.local",
            name: "Weekend Trail Crew",
            remoteName: "Saturday Hike",
            localName: "Weekend Trail Crew",
            topic: "Saturday 8 AM at the trailhead",
            avatarPath: "",
            localAvatarURI: "",
            network: "whatsapp",
            accountID: "whatsapp-1",
            isDirect: false,
            encrypted: true,
            disappearingMS: 604_800_000,
            pinnedEventIDs: ["$pin-group-1"],
            members: [
                Member(
                    userID: "@wa_alice:courier.local",
                    name: "Alice Example",
                    avatarPath: "",
                    powerLevel: 100,
                    isAdmin: true,
                    identifiers: ["+1 555-010-0101"],
                    tz: "America/Los_Angeles",
                    isBot: false
                ),
                Member(
                    userID: "@wa_bob:courier.local",
                    name: "Bob Example",
                    avatarPath: "",
                    powerLevel: 0,
                    isAdmin: false,
                    identifiers: ["+1 555-010-0102"],
                    tz: "America/New_York",
                    isBot: false
                ),
                Member(
                    userID: "@wa_trailbot:courier.local",
                    name: "Trail Weather Bot",
                    avatarPath: "",
                    powerLevel: 0,
                    isAdmin: false,
                    identifiers: [],
                    tz: "",
                    isBot: true
                ),
            ],
            sharedMedia: [],
            sharedFiles: [],
            sharedLinks: [],
            features: groupFeatures
        )
    }

    /// Group chat where the bridge does not support remote name/topic/avatar edits (e.g. Google Messages group or
    /// non-admin member), so `EditGroupSheet` locks to **Just for Me** with `"Changes apply only on this Mac."`
    static func groupChatInfoJustForMeOnly() -> RoomInfoResult {
        var lockedFeatures = features
        lockedFeatures.canSetName = false
        lockedFeatures.canSetTopic = false
        lockedFeatures.canSetAvatar = false
        lockedFeatures.canInvite = false
        lockedFeatures.canKick = false
        lockedFeatures.canSetAdmin = false
        lockedFeatures.canLeave = false
        lockedFeatures.canDelete = true

        var info = groupChatInfoWithAdmins()
        info.network = "gmessages"
        info.features = lockedFeatures
        return info
    }

    /// Candidate contacts for `AddParticipantsSheet` snapshots.
    static func inviteCandidates() -> [ContactCandidate] {
        [
            ContactCandidate(
                userID: "@wa_carol:courier.local",
                name: "Carol Example",
                avatarPath: "",
                network: "whatsapp",
                accountID: "whatsapp-1",
                identifiers: ["+1 555-010-0103"],
                roomID: "!dm-carol:courier.local"
            ),
            ContactCandidate(
                userID: "@wa_dan:courier.local",
                name: "Dan Example",
                avatarPath: "",
                network: "whatsapp",
                accountID: "whatsapp-1",
                identifiers: ["+1 555-010-0104"]
            ),
            ContactCandidate(
                userID: "@wa_erin:courier.local",
                name: "Erin Example",
                avatarPath: "",
                network: "whatsapp",
                accountID: "whatsapp-1",
                identifiers: ["+1 555-010-0105"]
            ),
        ]
    }

    // MARK: - Part 4.5a Task 11: Start New Chat, Blast, and Merged Chats fixtures

    static func startNewChatAccounts() -> [Account] {
        [
            Account(
                network: "whatsapp",
                displayName: "WhatsApp",
                flows: ["qr", "phone"],
                state: .connected,
                logins: [
                    Login(accountID: "whatsapp-1", remoteName: "+1 555-010-0101", state: .connected, canCreateGroup: true),
                ],
                canCreateGroup: true
            ),
            Account(
                network: "signal",
                displayName: "Signal",
                flows: ["qr"],
                state: .connected,
                logins: [
                    Login(accountID: "signal-1", remoteName: "+1 555-010-0102", state: .connected, canCreateGroup: true),
                ],
                canCreateGroup: true
            ),
            Account(
                network: "telegram",
                displayName: "Telegram",
                flows: ["qr", "phone"],
                state: .connected,
                logins: [
                    Login(accountID: "telegram-1", remoteName: "@me_example", state: .connected, canCreateGroup: true),
                ],
                canCreateGroup: true
            ),
            Account(
                network: "slack",
                displayName: "Slack",
                flows: ["token"],
                state: .connected,
                logins: [
                    Login(accountID: "slack-1", remoteName: "Example Co", state: .connected, canCreateGroup: true),
                ],
                canCreateGroup: true
            ),
        ]
    }

    static func startNewChatCandidates() -> [ContactCandidate] {
        [
            ContactCandidate(
                userID: "@wa_alice:courier.local",
                name: "Alice Example",
                avatarPath: "",
                network: "whatsapp",
                accountID: "whatsapp-1",
                identifiers: ["+1 555-010-0111"],
                roomID: "!dm-alice-wa:courier.local"
            ),
            ContactCandidate(
                userID: "@wa_bob:courier.local",
                name: "Bob Example",
                avatarPath: "",
                network: "whatsapp",
                accountID: "whatsapp-1",
                identifiers: ["+1 555-010-0112"],
                roomID: "!dm-bob-wa:courier.local"
            ),
            ContactCandidate(
                userID: "@sig_carol:courier.local",
                name: "Carol Example",
                avatarPath: "",
                network: "signal",
                accountID: "signal-1",
                identifiers: ["+1 555-010-0113"],
                roomID: "!dm-carol-sig:courier.local"
            ),
            ContactCandidate(
                userID: "@tg_dan:courier.local",
                name: "Dan Example",
                avatarPath: "",
                network: "telegram",
                accountID: "telegram-1",
                identifiers: ["@dan_example"],
                roomID: "!dm-dan-tg:courier.local"
            ),
            ContactCandidate(
                userID: "@tg_erin:courier.local",
                name: "Erin Example",
                avatarPath: "",
                network: "telegram",
                accountID: "telegram-1",
                identifiers: ["@erin_example"],
                roomID: "!dm-erin-tg:courier.local"
            ),
        ]
    }

    static func mergedAlice() -> MergedChat {
        MergedChat(
            mergeID: "merge:alice",
            name: "Alice Example",
            avatarPath: "",
            lastRoomID: "!dm-alice-wa:courier.local",
            roomIDs: [
                "!dm-alice-wa:courier.local",
                "!dm-alice-sig:courier.local",
                "!dm-alice-tg:courier.local",
            ],
            networks: ["whatsapp", "signal", "telegram"],
            createdTS: millis(180)
        )
    }

    static func mergeSuggestions() -> [MergeSuggestion] {
        [
            MergeSuggestion(
                name: "Alice Example",
                reason: "Same phone (+15550100101)",
                roomIDs: ["!dm-alice-wa:courier.local", "!dm-alice-sig:courier.local"],
                networks: ["whatsapp", "signal"]
            ),
        ]
    }

    static func mergeableDirectRows() -> [InboxRow] {
        [
            InboxRow(
                roomID: "!dm-alice-wa:courier.local",
                network: "whatsapp",
                name: "Alice Example",
                avatarPath: "",
                isDirect: true,
                lastTS: millis(5),
                preview: "See you at the trailhead!",
                previewKind: .text,
                previewMine: false,
                unread: 3,
                muted: false,
                loginName: "+1 555-010-0101",
                mergeID: "merge:alice"
            ),
            InboxRow(
                roomID: "!dm-alice-sig:courier.local",
                network: "signal",
                name: "Alice Example",
                avatarPath: "",
                isDirect: true,
                lastTS: millis(25),
                preview: "Sent you the GPX track",
                previewKind: .text,
                previewMine: false,
                unread: 3,
                muted: false,
                mergeID: "merge:alice"
            ),
            InboxRow(
                roomID: "!dm-alice-tg:courier.local",
                network: "telegram",
                name: "Alice Example",
                avatarPath: "",
                isDirect: true,
                lastTS: millis(60),
                preview: "Photos from last hike",
                previewKind: .text,
                previewMine: true,
                unread: 0,
                muted: false
            ),
            InboxRow(
                roomID: "!dm-bob-wa:courier.local",
                network: "whatsapp",
                name: "Bob Example",
                avatarPath: "",
                isDirect: true,
                lastTS: millis(90),
                preview: "Bringing coffee",
                previewKind: .text,
                previewMine: false,
                unread: 0,
                muted: false
            ),
        ]
    }

    // MARK: - Part 4.5a Task 12: User Hover Card & Contacts

    static func hoverCardMember() -> Member {
        Member(
            userID: "@alice:courier.local",
            name: "Alice Example",
            avatarPath: "",
            powerLevel: 50,
            isAdmin: false,
            identifiers: ["tel:+15550100101", "mailto:alice@example.com", "@alice"],
            tz: "America/Los_Angeles",
            isBot: false
        )
    }

    static func hoverCardSharedGroups() -> [PersonHit] {
        [
            PersonHit(
                userID: "@alice:courier.local",
                name: "Alice Example",
                network: "signal",
                avatarPath: "",
                roomID: "!grp-trail:courier.local",
                roomName: "Saturday Trail Runners",
                groups: 2
            ),
            PersonHit(
                userID: "@alice:courier.local",
                name: "Alice Example",
                network: "whatsapp",
                avatarPath: "",
                roomID: "!grp-design:courier.local",
                roomName: "Design Guild",
                groups: 2
            ),
        ]
    }

    static func matchedAliceContact() -> MatchedContact {
        MatchedContact(
            contactIdentifier: "cn-alice-1",
            fullName: "Alice Example",
            organization: "Example Studio",
            phones: ["+1 (555) 010-0101"],
            emails: ["alice@example.com"]
        )
    }

    // MARK: - Part 4.5a Task 13: Calendar Pane & Detected Dates

    static func calendarEvents() -> [CalendarEventItem] {
        [
            CalendarEventItem(
                id: "cal-ev-1",
                title: "Design Critique & Trail Review",
                startDate: now.addingTimeInterval(3600),
                endDate: now.addingTimeInterval(7200),
                isAllDay: false,
                calendarColorHex: "#0A84FF",
                location: "https://meet.google.com/abc-defg-hij",
                meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
            ),
            CalendarEventItem(
                id: "cal-ev-2",
                title: "Gear Check at Basecamp",
                startDate: now.addingTimeInterval(10800),
                endDate: now.addingTimeInterval(14400),
                isAllDay: false,
                calendarColorHex: "#30D158",
                location: "Studio 2B",
                meetingURL: nil
            ),
        ]
    }

    // MARK: - Part 4.5c Task 10: Stickers & GIFs timeline fixtures (real Go engine wire shape)

    static func sticker(
        _ id: String,
        name: String = "Party Parrot",
        emoji: String? = "🦜",
        mine: Bool,
        ts minutesAgo: Int,
        mediaURL: String = "mxc://courier.local/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        mediaPath: String = "",
        mimeType: String = "image/webp",
        width: Int = 160,
        height: Int = 160,
        replyTo: String? = nil,
        senderName: String = "Ann Example"
    ) -> Event {
        var info: [String: JSONValue] = [
            "mimetype": .string(mimeType),
            "size": .int(4096),
            "w": .int(Int64(width)),
            "h": .int(Int64(height)),
        ]
        if let emoji, !emoji.isEmpty {
            info["fi.mau.bridged_sticker"] = .object([
                "network": .string(""),
                "id": .string(""),
                "emoji": .string(emoji),
                "pack_url": .string(""),
            ])
        }
        var content: [String: JSONValue] = [
            "msgtype": .string("m.image"),
            "body": .string(name),
            "url": .string(mediaURL),
            "info": .object(info),
        ]
        if let replyTo {
            content["m.relates_to"] = .object([
                "m.in_reply_to": .object(["event_id": .string(replyTo)]),
            ])
        }
        var evt = event(
            id,
            type: "m.sticker",
            mine: mine,
            ts: minutesAgo,
            content: content,
            name: senderName
        )
        evt.mediaPath = mediaPath
        return evt
    }

    static func gif(
        _ id: String,
        msgtype: String = "m.image",
        fileName: String = "animation.gif",
        caption: String? = nil,
        mine: Bool,
        ts minutesAgo: Int,
        mediaURL: String = "mxc://courier.local/fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
        mediaPath: String = "",
        mimeType: String = "image/gif",
        width: Int = 280,
        height: Int = 180,
        senderName: String = "Ann Example"
    ) -> Event {
        let info: [String: JSONValue] = [
            "mimetype": .string(mimeType),
            "size": .int(12345),
            "w": .int(Int64(width)),
            "h": .int(Int64(height)),
            "is_animated": .bool(true),
            "fi.mau.gif": .bool(true),
        ]
        let content: [String: JSONValue] = [
            "msgtype": .string(msgtype),
            "body": .string(caption ?? fileName),
            "filename": .string(fileName),
            "url": .string(mediaURL),
            "info": .object(info),
        ]
        var evt = event(
            id,
            type: "m.room.message",
            mine: mine,
            ts: minutesAgo,
            content: content,
            name: senderName
        )
        evt.mediaPath = mediaPath
        evt.isGIF = true
        evt.isAnimated = true
        return evt
    }
}
