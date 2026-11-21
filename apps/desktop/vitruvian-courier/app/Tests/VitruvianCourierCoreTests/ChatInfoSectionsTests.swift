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

    /// Show All opens the viewer on the tab of the first tile, so a link in Shared is never out of reach.
    func testShowAllOpensTheTabOfTheFirstTile() {
        let photos = [media("$p", ts: 10)]
        let links = [link("$l", "https://maps.app.goo.gl/x", ts: 20)]
        XCTAssertEqual(ChatInfoShared.viewerTab(media: photos, links: links), .links, "the newest thing is a link")
        XCTAssertEqual(ChatInfoShared.viewerTab(media: [media("$p2", ts: 30)] + photos, links: links), .media)
        XCTAssertEqual(ChatInfoShared.viewerTab(media: [], links: links), .links)
        XCTAssertEqual(ChatInfoShared.viewerTab(media: photos, links: []), .media)
        XCTAssertEqual(ChatInfoShared.viewerTab(media: [], links: []), .media)
    }

    /// A count the engine could not finish says "at least"; a whole one is a plain number. The engine's flag
    /// survives the wire, and an engine before it reads as not capped.
    func testASharedCountThatMayBeTooSmallReadsAsAtLeast() throws {
        XCTAssertEqual(ChatInfoShared.countText(50, capped: true), "50+")
        XCTAssertEqual(ChatInfoShared.countText(7, capped: false), "7")
        func roundTrip(_ capped: Bool?) throws -> RoomInfoResult {
            let info = RoomInfoResult(
                roomID: "!r:x", name: "N", remoteName: "N", network: "whatsapp", isDirect: true, sharedCapped: capped,
                features: ChatFeatures(reply: true, edit: false, unsend: false, deleteReachesPhone: true, source: .stored))
            return try JSONDecoder().decode(RoomInfoResult.self, from: JSONEncoder().encode(info))
        }
        XCTAssertEqual(try roundTrip(true).sharedCapped, true)
        XCTAssertEqual(try roundTrip(false).sharedCapped, false)
        XCTAssertNil(try roundTrip(nil).sharedCapped, "an engine before the field")
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

    // MARK: - Link tiles (D2)

    private func richLink(
        _ url: String = "https://www.usatoday.com/story/news/abc", title: String? = "Senate passes the bill",
        image: String? = "/tmp/preview.jpg", sender: String = "@a:x"
    ) -> RoomLink {
        RoomLink(eventID: "$l", sender: sender, ts: 1, url: url, host: URL(string: url)?.host ?? "", title: title,
                 imagePath: image)
    }

    func testALinkTileShowsThePictureTheTitleTheSenderAndTheSite() {
        let members = [Member(userID: "@a:x", name: "Alice Park", avatarPath: "/tmp/alice.png")]
        let card = ChatInfoLinkCard(link: richLink(), members: members)
        XCTAssertEqual(card.imagePath, "/tmp/preview.jpg")
        XCTAssertEqual(card.headline, "Senate passes the bill")
        XCTAssertEqual(card.domain, "www.usatoday.com")
        XCTAssertEqual(card.sender?.name, "Alice Park")
        XCTAssertEqual(card.sender?.avatarPath, "/tmp/alice.png")
        XCTAssertEqual(card.sender?.initials, "A")
        XCTAssertFalse(card.isFallback)
    }

    func testALinkTileKeepsTheSiteOnOneLineAndTheTitleToTwo() {
        XCTAssertEqual(ChatInfoLinkCard.domainLineLimit, 1, "the site is never broken across lines")
        XCTAssertEqual(ChatInfoLinkCard.titleLineLimit, 2)
    }

    func testALinkWithNoPreviewFallsBackToAGlobeAndTheSite() {
        let card = ChatInfoLinkCard(link: richLink(title: nil, image: nil))
        XCTAssertTrue(card.isFallback)
        XCTAssertNil(card.imagePath)
        XCTAssertNil(card.headline, "the site is not said twice")
        XCTAssertEqual(card.symbolName, "globe")
        XCTAssertEqual(card.domain, "www.usatoday.com")
        // A title that is only the site's name says nothing more than the site.
        XCTAssertTrue(ChatInfoLinkCard(link: richLink(title: "www.usatoday.com", image: nil)).isFallback)
        // An empty picture path is no picture.
        XCTAssertNil(ChatInfoLinkCard(link: richLink(image: "")).imagePath)
    }

    func testAPictureWithNoTitleStillShowsThePicture() {
        let card = ChatInfoLinkCard(link: richLink(title: nil))
        XCTAssertFalse(card.isFallback)
        XCTAssertEqual(card.imagePath, "/tmp/preview.jpg")
        XCTAssertNil(card.headline)
    }

    func testAMapLinkWithNoTitleIsCalledMap() {
        let card = ChatInfoLinkCard(link: richLink("https://maps.app.goo.gl/x", title: nil, image: nil))
        XCTAssertEqual(card.headline, "Map")
        XCTAssertEqual(card.symbolName, "mappin.circle.fill")
        XCTAssertTrue(card.isMap)
    }

    func testTheSenderOfALinkIsMeOrAMemberOrJustTheirID() {
        XCTAssertEqual(
            ChatInfoPresentation.linkSender(for: richLink(sender: Timeline.meUserID), members: [], ownAvatarPath: "/tmp/me.png"),
            ChatInfoPresentation.MediaSender(name: "You", initials: "Y", avatarPath: "/tmp/me.png", identity: Timeline.meUserID)
        )
        let unknown = ChatInfoPresentation.linkSender(for: richLink(sender: "@zed:x"), members: [], ownAvatarPath: "")
        XCTAssertEqual(unknown?.name, "@zed:x")
        XCTAssertEqual(unknown?.avatarPath, "")
        XCTAssertNil(ChatInfoPresentation.linkSender(for: richLink(sender: " "), members: [], ownAvatarPath: ""))
    }

    func testCopiesOfALinkKeepThePictureAnotherCopyHas() {
        let url = "https://news.test/a"
        let older = RoomLink(eventID: "$old", sender: "@a:x", ts: 10, url: url, host: "news.test", title: "Story",
                             imagePath: "/tmp/p.jpg")
        let newer = RoomLink(eventID: "$new", sender: "@a:x", ts: 20, url: url, host: "news.test")
        for order in [[older, newer], [newer, older]] {
            let kept = RoomLink.deduplicated(order)
            XCTAssertEqual(kept.count, 1)
            XCTAssertEqual(kept[0].eventID, "$new", "the newest message wins")
            XCTAssertEqual(kept[0].imagePath, "/tmp/p.jpg")
            XCTAssertEqual(kept[0].title, "Story")
        }
    }

    // MARK: - Disappearing messages and Google Chat's history (D3)

    private func info(network: String, disappearingMS: Int64 = 0, historyOff: Bool? = nil) -> RoomInfoResult {
        RoomInfoResult(roomID: "!r:x", name: "Chat", remoteName: "Chat", network: network, isDirect: false,
                       disappearingMS: disappearingMS, historyOff: historyOff, features: .noFeatures)
    }

    func testGoogleChatShowsItsHistorySettingOnOrOffAndSaysWhereToChangeIt() throws {
        let off = try XCTUnwrap(ChatInfoPresentation.disappearingRow(for: info(network: "gchat", historyOff: true)))
        XCTAssertEqual(off.title, "Chat history")
        XCTAssertEqual(off.value, "Off")
        XCTAssertEqual(off.explanation, "History is off: messages disappear after 24 hours. Change this in Google Chat.")
        XCTAssertTrue(off.isHistorySetting, "read only: no picker")

        let on = try XCTUnwrap(ChatInfoPresentation.disappearingRow(for: info(network: "gchat", historyOff: false)))
        XCTAssertEqual(on.title, "Chat history")
        XCTAssertEqual(on.value, "On")
        XCTAssertEqual(on.explanation, "History is on: messages are kept. Change this in Google Chat.")
    }

    func testGoogleChatShowsNoRowWhenItsHistorySettingIsNotKnown() {
        XCTAssertNil(ChatInfoPresentation.disappearingRow(for: info(network: "gchat")),
                     "never claim a setting Google has not told us")
    }

    func testOtherNetworksKeepTheirDisappearingTimerRowAndIgnoreHistory() throws {
        XCTAssertNil(ChatInfoPresentation.disappearingRow(for: info(network: "whatsapp")))
        XCTAssertNil(ChatInfoPresentation.disappearingRow(for: info(network: "whatsapp", historyOff: true)),
                     "only Google Chat has a history setting")
        let timer = try XCTUnwrap(
            ChatInfoPresentation.disappearingRow(for: info(network: "whatsapp", disappearingMS: 604_800_000)))
        XCTAssertEqual(timer.title, "Disappearing Messages")
        XCTAssertEqual(timer.value, MessageActions.duration(604_800_000))
        XCTAssertFalse(timer.isHistorySetting)
    }

    func testHistorySettingRidesTheEnginesHistoryOffField() throws {
        let sent = try JSONEncoder().encode(info(network: "gchat", historyOff: true))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        XCTAssertEqual(object["history_off"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(RoomInfoResult.self, from: sent).historyOff, true)
        // An engine from before the field leaves it out: nothing is claimed.
        object["history_off"] = nil
        let older = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(RoomInfoResult.self, from: older).historyOff)
    }
}
