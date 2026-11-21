// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// Batch 6 D2: the photo viewer shows the photo's reactions. The chips must follow the timeline: a reaction that
/// arrives (or one I add from the viewer's own React button) while the viewer is open has to show without closing it.
@MainActor
final class PhotoViewerReactionsStayInSyncTests: XCTestCase {
    private func photo(_ id: String, ts: Int64) -> Event {
        Event(eventID: id, roomID: "!r", sender: "@ann:courier.local", senderName: "Ann", mine: false,
              type: "m.room.message",
              content: .object(["msgtype": .string("m.image"), "body": .string("\(id).jpg"), "filename": .string("\(id).jpg")]),
              ts: ts, seq: ts, status: .sent)
    }

    private func reaction(_ id: String, to target: String, ts: Int64) -> Event {
        Event(eventID: id, roomID: "!r", sender: "@bob:courier.local", senderName: "Bob", mine: false,
              type: "m.reaction",
              content: .object(["m.relates_to": .object([
                  "rel_type": .string("m.annotation"), "event_id": .string(target), "key": .string("👍"),
              ])]),
              ts: ts, seq: ts, status: .sent)
    }

    private func build(_ events: [Event]) -> [TimelineItem] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return Timeline.build(events: events, me: Timeline.meUserID, now: Date(timeIntervalSince1970: 1_760_700_000),
                              calendar: utc)
    }

    func testAReactionThatArrivesWhileThePhotoViewerIsOpenShowsInIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("courier-d2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine", dataDir: dir, environment: [:],
            launcher: FoundationProcessLauncher()))
        let conversation = ConversationModel(appModel: app)

        let before = build([photo("$p1", ts: 1_760_600_000_000), photo("$p2", ts: 1_760_600_100_000)])
        conversation.setSnapshotStateForTesting(roomID: "!r", items: before)
        conversation.openLightbox("$p1")
        XCTAssertEqual(conversation.carousel.currentItem?.eventID, "$p1")
        XCTAssertTrue(conversation.carousel.currentItem?.reactions.isEmpty == true)

        // Bob reacts to the photo being looked at: the timeline now carries the chip.
        let after = build([
            photo("$p1", ts: 1_760_600_000_000), photo("$p2", ts: 1_760_600_100_000),
            reaction("$r1", to: "$p1", ts: 1_760_600_200_000),
        ])
        conversation.setSnapshotItemsForTesting(after)
        XCTAssertEqual(CarouselItem.reactionsByEventID(from: conversation.items)["$p1"]?.map(\.key), ["👍"],
                       "the timeline has the reaction")
        XCTAssertEqual(conversation.carousel.currentItem?.reactions.map(\.key), ["👍"],
                       "the open viewer shows what the timeline now says")
    }
}
