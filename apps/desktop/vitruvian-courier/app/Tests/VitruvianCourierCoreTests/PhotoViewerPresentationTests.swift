// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import VitruvianCourierCore
import XCTest

final class PhotoViewerPresentationTests: XCTestCase {
    func testHeaderTextFormatsSenderAndDateWithoutFilename() {
        let locale = Locale(identifier: "en_US_POSIX")
        let utc = TimeZone(secondsFromGMT: 0)!
        let ts: Int64 = 1_760_600_000_000
        let expectedDate = PhotoViewerPresentation.formattedDate(forMillis: ts, locale: locale, timeZone: utc)
        XCTAssertNotNil(expectedDate)

        // Incoming sender strips network suffix and formats "Sender · Date".
        let incomingHeader = PhotoViewerPresentation.headerText(
            sender: "@ann:example.test",
            senderName: "Ann (WhatsApp)",
            mine: false,
            ts: ts,
            locale: locale,
            timeZone: utc,
            redacted: false
        )
        XCTAssertEqual(incomingHeader, "Ann · \(expectedDate!)")
        XCTAssertFalse(incomingHeader.contains("(WhatsApp)"))
        XCTAssertFalse(incomingHeader.contains("1000068615.jpeg"))

        // Outgoing sender labels "You".
        let mineHeader = PhotoViewerPresentation.headerText(
            sender: "@me:courier.local",
            senderName: "James",
            mine: true,
            ts: ts,
            locale: locale,
            timeZone: utc,
            redacted: false
        )
        XCTAssertEqual(mineHeader, "You · \(expectedDate!)")

        // Missing display name falls back to raw sender identifier; zero timestamp omits delimiter.
        let fallbackNoDate = PhotoViewerPresentation.headerText(
            sender: "@ann:example.test",
            senderName: "  ",
            mine: false,
            ts: 0,
            locale: locale,
            timeZone: utc,
            redacted: false
        )
        XCTAssertEqual(fallbackNoDate, "@ann:example.test")

        // Redaction hides non-me display names while keeping "You".
        let redactedHeader = PhotoViewerPresentation.headerText(
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            mine: false,
            ts: ts,
            locale: locale,
            timeZone: utc,
            redacted: true
        )
        XCTAssertFalse(redactedHeader.contains("Alice Example"))
        XCTAssertTrue(redactedHeader.contains(" · \(expectedDate!)"))
        XCTAssertTrue(
            PhotoViewerPresentation.headerText(
                sender: "@me:courier.local",
                senderName: "James",
                mine: true,
                ts: ts,
                locale: locale,
                timeZone: utc,
                redacted: true
            ).hasPrefix("You · ")
        )

        // CarouselItem & MediaHit overloads never leak the raw fileName into the header, keeping fileName for download.
        let item = CarouselItem(
            eventID: "$p1",
            roomID: "!r",
            kind: .image,
            mediaPath: "/tmp/1000068615.jpeg",
            fileName: "1000068615.jpeg",
            sender: "@alice:courier.local",
            senderName: "Alice Example (Signal)",
            mine: false,
            ts: ts
        )
        let itemHeader = PhotoViewerPresentation.headerText(for: item, redacted: false)
        XCTAssertTrue(itemHeader.hasPrefix("Alice Example · "))
        XCTAssertFalse(itemHeader.contains("1000068615.jpeg"))
        XCTAssertEqual(item.fileName, "1000068615.jpeg")

        let hit = MediaHit(
            eventID: "$p2",
            roomID: "!r",
            sender: "@me:courier.local",
            senderName: "You",
            mine: true,
            ts: ts,
            seq: 1,
            kind: .image,
            snippet: "1000068615.jpeg",
            mediaPath: "/tmp/1000068615.jpeg"
        )
        let hitHeader = PhotoViewerPresentation.headerText(for: hit, redacted: false)
        XCTAssertTrue(hitHeader.hasPrefix("You · "))
        XCTAssertFalse(hitHeader.contains("1000068615.jpeg"))
        XCTAssertEqual(hit.fileName, "1000068615.jpeg")
    }

    func testDisplayCaptionShowsDistinctCaptionAndHidesFilenamePlaceholder() {
        XCTAssertEqual(
            PhotoViewerPresentation.displayCaption(caption: "Sunset over the ridge", fileName: "1000068615.jpeg"),
            "Sunset over the ridge"
        )
        XCTAssertEqual(
            PhotoViewerPresentation.displayCaption(caption: "  Photo note  \n", fileName: "1000068615.jpeg"),
            "Photo note"
        )
        XCTAssertNil(
            PhotoViewerPresentation.displayCaption(caption: "1000068615.jpeg", fileName: "1000068615.jpeg")
        )
        XCTAssertNil(
            PhotoViewerPresentation.displayCaption(caption: "  \n ", fileName: "1000068615.jpeg")
        )
    }

    func testCarouselItemAndViewerItemsPreserveReactionsAndCaption() {
        let events: [Event] = [
            Event(
                eventID: "$single",
                roomID: "!r",
                sender: "@ann:courier.local",
                senderName: "Ann Example",
                mine: false,
                type: "m.room.message",
                content: .object([
                    "msgtype": .string("m.image"),
                    "body": .string("Sunset over the ridge"),
                    "filename": .string("1000068615.jpeg"),
                    "url": .string("mxc://server/single"),
                ]),
                ts: 1_760_600_000_000,
                seq: 1,
                status: .sent,
                mediaPath: "/tmp/single.jpg"
            ),
            Event(
                eventID: "$single-react",
                roomID: "!r",
                sender: Timeline.meUserID,
                senderName: "You",
                mine: true,
                type: "m.reaction",
                content: .object([
                    "m.relates_to": .object([
                        "rel_type": .string("m.annotation"),
                        "event_id": .string("$single"),
                        "key": .string("❤️"),
                    ]),
                ]),
                ts: 1_760_600_001_000,
                seq: 2,
                status: .sent
            ),
            Event(
                eventID: "$g1",
                roomID: "!r",
                sender: "@bob:courier.local",
                senderName: "Bob",
                mine: false,
                type: "m.room.message",
                content: .object([
                    "msgtype": .string("m.image"),
                    "body": .string("g1.jpg"),
                    "filename": .string("g1.jpg"),
                    "url": .string("mxc://server/g1"),
                ]),
                ts: 1_760_600_010_000,
                seq: 3,
                status: .sent,
                mediaPath: "/tmp/g1.jpg"
            ),
            Event(
                eventID: "$g2",
                roomID: "!r",
                sender: "@bob:courier.local",
                senderName: "Bob",
                mine: false,
                type: "m.room.message",
                content: .object([
                    "msgtype": .string("m.image"),
                    "body": .string("g2.jpg"),
                    "filename": .string("g2.jpg"),
                    "url": .string("mxc://server/g2"),
                ]),
                ts: 1_760_600_012_000,
                seq: 4,
                status: .sent,
                mediaPath: "/tmp/g2.jpg"
            ),
            Event(
                eventID: "$g2-react",
                roomID: "!r",
                sender: "@ann:courier.local",
                senderName: "Ann Example",
                mine: false,
                type: "m.reaction",
                content: .object([
                    "m.relates_to": .object([
                        "rel_type": .string("m.annotation"),
                        "event_id": .string("$g2"),
                        "key": .string("🔥"),
                    ]),
                ]),
                ts: 1_760_600_013_000,
                seq: 5,
                status: .sent
            ),
        ]

        let timeline = Timeline.build(events: events, me: Timeline.meUserID)
        let carouselItems = CarouselItem.items(from: timeline)
        XCTAssertEqual(carouselItems.map(\.eventID), ["$single", "$g1", "$g2"])

        XCTAssertEqual(carouselItems[0].fileName, "1000068615.jpeg")
        XCTAssertEqual(carouselItems[0].caption, "Sunset over the ridge")
        XCTAssertEqual(carouselItems[0].reactions.map(\.key), ["❤️"])
        XCTAssertTrue(carouselItems[1].caption.isEmpty, "Matching body/filename must not become a visible caption")
        XCTAssertEqual(carouselItems[2].reactions.map(\.key), ["🔥"])

        // Merging a search MediaHit onto an existing timeline item must keep timeline reactions.
        let hit = MediaHit(
            eventID: "$single",
            roomID: "!r",
            sender: "@ann:courier.local",
            senderName: "Ann Example",
            mine: false,
            ts: 1_760_600_000_000,
            seq: 1,
            kind: .image,
            snippet: "Sunset over the ridge",
            mediaPath: "/tmp/single.jpg"
        )
        let merged = CarouselItem.viewerItems(timelineItems: timeline, mediaHits: [hit])
        XCTAssertEqual((merged.first(where: { $0.eventID == "$single" })?.reactions ?? []).map(\.key), ["❤️"])

        // The media grid looks reactions up by event, including each tile of a collapsed gallery.
        let byEvent = CarouselItem.reactionsByEventID(from: timeline)
        XCTAssertEqual(byEvent["$single"]?.map(\.key), ["❤️"])
        XCTAssertEqual(byEvent["$g1"]?.isEmpty, true)
        XCTAssertEqual(byEvent["$g2"]?.map(\.key), ["🔥"])
    }

    func testMediaPagedInAsAHitTakesItsReactionsFromTheTimeline() throws {
        let hit = MediaHit(
            eventID: "$p1",
            roomID: "!r",
            sender: "@ann:courier.local",
            senderName: "Ann Example",
            mine: false,
            ts: 1_760_600_000_000,
            seq: 1,
            kind: .image,
            snippet: "p1.jpg",
            mediaPath: "/tmp/p1.jpg"
        )
        let paged = try XCTUnwrap(CarouselItem(hit: hit))
        XCTAssertTrue(paged.reactions.isEmpty, "a hit carries no reactions of its own")

        func photo() -> Event {
            Event(
                eventID: "$p1", roomID: "!r", sender: "@ann:courier.local", senderName: "Ann Example", mine: false,
                type: "m.room.message",
                content: .object(["msgtype": .string("m.image"), "body": .string("p1.jpg"), "filename": .string("p1.jpg"),
                                  "url": .string("mxc://server/p1")]),
                ts: 1_760_600_000_000, seq: 1, status: .sent, mediaPath: "/tmp/p1.jpg"
            )
        }
        let heartEvent = Event(
            eventID: "$r1", roomID: "!r", sender: "@bob:courier.local", senderName: "Bob", mine: false,
            type: "m.reaction",
            content: .object(["m.relates_to": .object([
                "rel_type": .string("m.annotation"), "event_id": .string("$p1"), "key": .string("❤️"),
            ])]),
            ts: 1_760_600_001_000, seq: 2, status: .sent
        )
        let withReaction = Timeline.build(events: [photo(), heartEvent], me: Timeline.meUserID)
        let withoutReaction = Timeline.build(events: [photo()], me: Timeline.meUserID)

        // Looked up by event ID when the timeline has the event; left alone when it doesn't.
        let found = CarouselItem.applyingReactions(from: withReaction, to: [paged]).first?.reactions
        XCTAssertEqual(found?.map(\.key), ["❤️"])
        XCTAssertEqual(found?.map(\.count), [1])
        XCTAssertTrue(CarouselItem.applyingReactions(from: [], to: [paged]).first?.reactions.isEmpty == true)

        // A reaction taken back empties the chips.
        let shown = paged.withReactions(found ?? [])
        XCTAssertTrue(CarouselItem.applyingReactions(from: withoutReaction, to: [shown]).first?.reactions.isEmpty == true)
    }
}
