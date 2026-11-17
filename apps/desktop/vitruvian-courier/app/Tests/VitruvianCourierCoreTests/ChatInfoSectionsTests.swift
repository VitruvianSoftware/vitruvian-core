// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class ChatInfoSectionsTests: XCTestCase {
    private func media(_ id: String, ts: Int64, msgtype: String = "m.image") -> Event {
        Event(
            eventID: id, roomID: "!r:x", sender: "@a:x", senderName: "Alice", senderAvatarPath: "", mine: false,
            type: "m.room.message", content: .object(["msgtype": .string(msgtype), "body": .string(id)]),
            ts: ts, seq: ts, status: .sent
        )
    }

    private func link(_ id: String, _ url: String, ts: Int64, title: String? = nil) -> RoomLink {
        RoomLink(eventID: id, sender: "@a:x", ts: ts, url: url, host: URL(string: url)?.host ?? "", title: title)
    }

    // MARK: - Shared

    func testSharedShowsTheNewestFourPhotosVideosAndLinksNewestFirst() {
        let events = [media("$p1", ts: 10), media("$v1", ts: 40, msgtype: "m.video"), media("$p2", ts: 20)]
        let links = [
            link("$l1", "https://example.com/a", ts: 30),
            link("$l2", "https://maps.app.goo.gl/x", ts: 50),
            link("$l3", "https://example.com/b", ts: 5),
        ]
        let tiles = ChatInfoShared.tiles(media: events, links: links)
        XCTAssertEqual(tiles.map(\.eventID), ["$l2", "$v1", "$l1", "$p2"], "four tiles, newest first, mixed")
        XCTAssertEqual(ChatInfoShared.count(media: events, links: links), 6, "Show All has two more")
        XCTAssertEqual(ChatInfoShared.tiles(media: events, links: links, limit: 2).map(\.eventID), ["$l2", "$v1"])
    }

    func testSharedCountsALinkOnceHoweverOftenItWasSentAndNeverCountsFilesAsPhotos() {
        let links = [link("$l1", "https://x.test/a", ts: 10), link("$l2", "https://x.test/a", ts: 20)]
        let file = media("$f", ts: 30, msgtype: "m.file")
        XCTAssertEqual(ChatInfoShared.tiles(media: [file], links: links).map(\.eventID), ["$l2"])
        XCTAssertEqual(ChatInfoShared.count(media: [file], links: links), 1)
        XCTAssertTrue(ChatInfoShared.tiles(media: [], links: []).isEmpty)
    }

    func testSharedPutsAPhotoBeforeALinkSentAtTheSameMoment() {
        let tiles = ChatInfoShared.tiles(media: [media("$p", ts: 10)], links: [link("$l", "https://x.test/a", ts: 10)])
        XCTAssertEqual(tiles.map(\.eventID), ["$p", "$l"])
    }

    func testMapsLinksAreRecognisedInEveryForm() {
        for url in [
            "https://maps.app.goo.gl/kX9abc", "https://goo.gl/maps/AbCd", "https://www.google.com/maps/place/Foo",
            "https://google.com/maps?q=1,2", "https://maps.google.com/?q=1,2", "https://maps.apple.com/?ll=1,2",
        ] {
            XCTAssertTrue(link("$l", url, ts: 1).isMapsLink, url)
            XCTAssertEqual(link("$l", url, ts: 1).cardSymbolName, "mappin.circle.fill", url)
        }
        for url in ["https://www.google.com/search?q=maps", "https://goo.gl/abc", "https://example.com/maps", "https://photos.app.goo.gl/x"] {
            XCTAssertFalse(link("$l", url, ts: 1).isMapsLink, url)
            XCTAssertEqual(link("$l", url, ts: 1).cardSymbolName, "globe", url)
        }
        XCTAssertEqual(link("$l", "https://maps.app.goo.gl/x", ts: 1).cardTitle, "Map")
        XCTAssertEqual(link("$l", "https://maps.app.goo.gl/x", ts: 1, title: "Ferry Building").cardTitle, "Ferry Building")
        XCTAssertEqual(link("$l", "https://example.com/a", ts: 1).cardTitle, "example.com")
    }

    // MARK: - Bookmarks

    private func hit(_ id: String, ts: Int64, seq: Int64 = 0, snippet: String, mine: Bool = false,
                     name: String = "Alice", kind: MessageHitKind = .text) -> MessageHit {
        MessageHit(eventID: id, roomID: "!r:x", roomName: "Chat", network: "whatsapp", isDirect: true, sender: "@a:x",
                   senderName: name, mine: mine, ts: ts, seq: seq, kind: kind, snippet: snippet)
    }

    func testBookmarksAreNewestFirstNamingWhoSentThemAndWhatMediaIs() {
        let rows = ChatInfoPresentation.bookmarkRows([
            hit("$old", ts: 100, snippet: "Trail pass"),
            hit("$mine", ts: 300, snippet: "  Remember the map  ", mine: true),
            hit("$photo", ts: 200, snippet: "", kind: .image),
            hit("$noname", ts: 150, snippet: "hi", name: " "),
        ])
        XCTAssertEqual(rows.map(\.eventID), ["$mine", "$photo", "$noname", "$old"])
        XCTAssertEqual(rows[0].sender, "You")
        XCTAssertEqual(rows[0].snippet, "Remember the map")
        XCTAssertEqual(rows[1].snippet, "Photo")
        XCTAssertEqual(rows[2].sender, "@a:x", "the sender's ID when there is no name")
        XCTAssertTrue(ChatInfoPresentation.bookmarkRows([]).isEmpty)
    }

    func testBookmarkDateIsTheTimeTodayYesterdayThenTheDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "en_US")
        func ms(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) throws -> Int64 {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)))
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        let now = Date(timeIntervalSince1970: TimeInterval(try ms(2026, 11, 17, 12, 0)) / 1000)
        func text(_ ts: Int64) -> String {
            ChatInfoPresentation.bookmarkDateText(ts: ts, now: now, calendar: calendar, locale: locale)
        }
        XCTAssertEqual(text(try ms(2026, 11, 17, 9, 5)).replacingOccurrences(of: "\u{202f}", with: " "), "9:05 AM")
        XCTAssertEqual(text(try ms(2026, 11, 16, 23, 0)), "Yesterday")
        XCTAssertEqual(text(try ms(2026, 3, 2, 8, 0)), "Mar 2")
        XCTAssertEqual(text(try ms(2025, 12, 30, 8, 0)), "Dec 30, 2025")
    }

    // MARK: - Contact

    func testContactListsPhoneEmailAndUsernameAndLeavesOutOpaqueIDs() {
        let member = Member(
            userID: "@wa_alice:courier.local", name: "Alice",
            identifiers: ["tel:+15550100101", "mailto:Alice@Example.com", "telegram:alice", "slack-internal:U08XYZ", "+1 555-010-0101"]
        )
        let rows = ChatInfoPresentation.contactRows(for: member)
        XCTAssertEqual(rows.map(\.kind), [.phone, .email, .handle])
        XCTAssertEqual(rows.map(\.label), ["Phone", "Email", "Username"])
        XCTAssertEqual(rows.map(\.value), ["+1 555-010-0101", "Alice@Example.com", "@alice"], "a number written two ways shows once")
        XCTAssertTrue(ChatInfoPresentation.contactRows(for: nil).isEmpty)
        XCTAssertTrue(ChatInfoPresentation.contactRows(for: Member(userID: "@x:y", name: "X", identifiers: [])).isEmpty)
    }

    // MARK: - Settings and what they mean

    func testTheDefaultSoundIsTheAccountsThenTheDirectOrGroupSound() throws {
        let suiteName = "courier.test.defaultsound.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ScratchDefaults.suite(named: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prefs = NotificationPreferences(defaults: defaults)
        prefs.messageSound = .rain
        prefs.groupSound = .harp
        XCTAssertEqual(prefs.defaultSound(isDirect: true, network: "whatsapp", accountID: "wa-1"), .rain)
        XCTAssertEqual(prefs.defaultSound(isDirect: false, network: "whatsapp", accountID: "wa-1"), .harp)
        prefs.accountOverrides["whatsapp:wa-1"] = AccountNotificationOverride(sound: .marimba)
        XCTAssertEqual(prefs.defaultSound(isDirect: true, network: "whatsapp", accountID: "wa-1"), .marimba)
        XCTAssertEqual(prefs.defaultSound(isDirect: true, network: "whatsapp", accountID: "wa-2"), .rain, "another account")
    }

    func testThePickerNamesTheSoundDefaultStandsFor() {
        func name(_ c: NotificationSoundChoice) -> String { c == .sounds ? "Pop" : c.rawValue.capitalized }
        func title(_ c: NotificationSoundChoice, _ resolved: NotificationSoundChoice) -> String {
            ChatInfoPresentation.soundPickerTitle(c, resolvedDefault: resolved, name: name)
        }
        XCTAssertEqual(title(.default, .sounds), "Default (Pop)")
        XCTAssertEqual(title(.default, .default), "Default", "nothing to add for the system's own sound")
        XCTAssertEqual(title(.harp, .sounds), "Harp")
    }

    func testEachSettingSaysWhatItDoes() {
        XCTAssertEqual(ChatInfoPresentation.soundExplanation(chosen: .default),
                       "Uses your sound from Settings ▸ Notifications. Muted chats stay silent.")
        XCTAssertEqual(ChatInfoPresentation.soundExplanation(chosen: .harp),
                       "Plays this sound for this chat only. Muted chats stay silent.")
        XCTAssertEqual(ChatInfoPresentation.disappearingExplanation, "New messages disappear after the set time")
        XCTAssertEqual(ChatReadAloud.default.explanation,
                       "Follows Vitruvian Speaker’s settings. Muted chats are never read aloud.")
        XCTAssertEqual(ChatReadAloud.always.explanation,
                       "Every new message is read aloud. Muted chats are never read aloud.")
        XCTAssertEqual(ChatReadAloud.never.explanation, "This chat is never read aloud.")
    }
}
