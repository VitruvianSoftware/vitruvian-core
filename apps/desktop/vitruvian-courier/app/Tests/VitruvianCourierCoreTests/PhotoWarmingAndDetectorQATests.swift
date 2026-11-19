// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import VitruvianCourierCore

/// QA coverage for off-main-thread image header pre-warming across every ConversationModel and ThreadModel
/// timeline entry path, FileStamp failure invalidation, small EXIF orientation pixel transforms, and
/// SharedLinkDetector thread safety.
@MainActor
final class PhotoWarmingAndDetectorQATests: XCTestCase {
    private var directory: URL!
    private var harnesses: [ConversationHarness] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-qa-warming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for harness in harnesses { await harness.stop() }
        harnesses = []
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeImage(
        named name: String,
        type: UTType = .png,
        width: Int,
        height: Int,
        orientation: Int? = nil
    ) throws -> String {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = try XCTUnwrap(context.makeImage())
        let url = directory.appendingPathComponent(name)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url.path
    }

    /// Bridged image event with no stored `w`/`h` in `info`.
    private func bridgedImageEvent(
        id: String,
        room: String,
        at n: Int64,
        mediaPath: String,
        mine: Bool = false,
        status: String = "sent",
        mime: String = "image/png",
        threadSummary: [String: Any]? = nil,
        threadRootID: String? = nil
    ) -> [String: Any] {
        var content: [String: Any] = [
            "msgtype": "m.image",
            "body": "\(id).png",
            "info": ["mimetype": mime],
        ]
        if let threadRootID {
            content["m.relates_to"] = [
                "rel_type": "m.thread",
                "event_id": threadRootID,
                "is_falling_back": true,
                "m.in_reply_to": ["event_id": threadRootID],
            ]
        }
        return [
            "event_id": id,
            "room_id": room,
            "sender": mine ? Timeline.meUserID : "@ann:example.test",
            "sender_name": mine ? "me" : "Ann",
            "sender_avatar_path": "",
            "mine": mine,
            "type": "m.room.message",
            "content": content,
            "ts": ConversationScript.timestamp(n),
            "seq": n,
            "status": status,
            "status_reason": "",
            "media_path": mediaPath,
            "bookmarked": false,
            "poll": NSNull(),
            "thread": threadSummary ?? (NSNull() as Any),
            "expires_at": 0,
            "delivered": false,
            "read_by": [[String: Any]](),
        ]
    }

    private func mediaEditEvent(
        id: String,
        replacing target: String,
        room: String,
        at n: Int64,
        mediaPath: String,
        mine: Bool = false
    ) -> [String: Any] {
        [
            "event_id": id,
            "room_id": room,
            "sender": mine ? Timeline.meUserID : "@ann:example.test",
            "sender_name": mine ? "me" : "Ann",
            "sender_avatar_path": "",
            "mine": mine,
            "type": "m.room.message",
            "content": [
                "msgtype": "m.image",
                "body": "* Shared photo",
                "m.new_content": [
                    "msgtype": "m.image",
                    "body": "Shared photo",
                    "filename": "edited.png",
                    "url": "mxc://example.test/\(id)",
                    "info": ["mimetype": "image/png"],
                ],
                "m.relates_to": ["rel_type": "m.replace", "event_id": target],
            ] as [String: Any],
            "ts": ConversationScript.timestamp(n),
            "seq": n,
            "status": "sent",
            "status_reason": "",
            "media_path": mediaPath,
            "bookmarked": false,
            "poll": NSNull(),
            "thread": NSNull(),
            "expires_at": 0,
            "delivered": false,
            "read_by": [[String: Any]](),
        ]
    }

    func testEveryConversationTimelinePathWarmsHeaderSizesBeforeItemsPublish() async throws {
        let earlierNetworkPath = try writeImage(named: "earlier-net.png", width: 900, height: 450)
        let olderLocalPath = try writeImage(named: "older-local.png", width: 800, height: 600)
        let aroundPath = try writeImage(named: "around-exif6.jpg", type: .jpeg, width: 1000, height: 500, orientation: 6)
        let newerPagePath = try writeImage(named: "newer-page.png", width: 700, height: 350)
        let initialLoadPath = try writeImage(named: "initial-load.png", width: 1200, height: 600)
        let liveIncomingPath = try writeImage(named: "live-incoming.png", width: 640, height: 480)
        let outgoingSendPath = try writeImage(named: "outgoing-send.png", width: 720, height: 360)
        let outgoingEchoPath = try writeImage(named: "outgoing-echo.png", width: 760, height: 380)
        let editedImagePath = try writeImage(named: "edited-image.png", width: 840, height: 420)

        var roomAEvents: [[String: Any]] = []
        for index in 1 ... 120 {
            let n = Int64(index)
            switch index {
            case 1:
                roomAEvents.append(bridgedImageEvent(id: "$1", room: "!a", at: n, mediaPath: olderLocalPath))
            case 30:
                roomAEvents.append(bridgedImageEvent(id: "$30", room: "!a", at: n, mediaPath: aroundPath, mime: "image/jpeg"))
            case 66:
                roomAEvents.append(bridgedImageEvent(id: "$66", room: "!a", at: n, mediaPath: newerPagePath))
            default:
                roomAEvents.append(textEvent(id: "$\(index)", room: "!a", at: n, body: "Row \(index)"))
            }
        }

        let roomBEvents: [[String: Any]] = [
            textEvent(id: "$b1", room: "!b", at: 1, body: "First"),
            textEvent(id: "$b2", room: "!b", at: 2, body: "Will become an image"),
            bridgedImageEvent(id: "$b3", room: "!b", at: 3, mediaPath: initialLoadPath),
        ]

        let h = try await startConversation(
            ["!a": roomAEvents, "!b": roomBEvents],
            features: ["!a": featuresJSON(), "!b": featuresJSON()],
            rows: [
                "!a": chatRow("!a", name: "Ann", network: "signal"),
                "!b": chatRow("!b", name: "Bob", network: "whatsapp"),
            ]
        )
        harnesses.append(h)

        // Synchronously inspect every publication of `conversation.items`: any un-warmed local image without stored
        // dimensions would render at the 300x225 fallback on frame 1 and jump once `loadImage()` completes.
        var unwarmedOnPublish: [String] = []
        let sub = h.conversation.$items.sink { items in
            for case let .message(msg) in items where msg.kind == .image && (msg.width ?? 0) <= 0 {
                if ImagePixelSizeReader.cachedSize(ofFirstReadable: [msg.mediaPath, msg.thumbnailPath]) == nil {
                    unwarmedOnPublish.append("\(msg.id):\(msg.mediaPath)")
                }
            }
        }
        defer { sub.cancel() }

        // 1. Opening around an anchor message (`fetchAround`).
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [aroundPath]))
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isLoaded && h.conversation.isAwayFromLatest && h.message("$30") != nil }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [aroundPath]), CGSize(width: 500, height: 1000))
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [olderLocalPath]))
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [newerPagePath]))

        // 2. Paging older local history (`loadOlder`).
        h.conversation.loadOlder()
        try await waitUntil { h.message("$1") != nil && !h.conversation.isLoadingOlder }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [olderLocalPath]), CGSize(width: 800, height: 600))
        XCTAssertFalse(h.conversation.hasOlder)

        // 3. Backfilling older network history (`loadEarlier` -> `readEarlier`).
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [earlierNetworkPath]))
        h.script.add("!a", bridgedImageEvent(id: "$0", room: "!a", at: 0, mediaPath: earlierNetworkPath))
        h.script.overrides["room.loadOlder"] = .result(["added": 1, "has_more": false, "loading": false])
        h.conversation.loadEarlier()
        try await waitUntil { h.message("$0") != nil && !h.conversation.isLoadingEarlier }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [earlierNetworkPath]), CGSize(width: 900, height: 450))

        // 4. Paging newer history while away (`loadNewer`).
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [newerPagePath]))
        h.conversation.loadNewer()
        try await waitUntil { h.message("$66") != nil && !h.conversation.isLoadingNewer }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [newerPagePath]), CGSize(width: 700, height: 350))

        // 5. Initial room open (`fetchNewest`).
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [initialLoadPath]))
        try await h.open("!b")
        XCTAssertNotNil(h.message("$b3"))
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [initialLoadPath]), CGSize(width: 1200, height: 600))

        // 6. Live incoming bridged image (`Change.event` -> `fetchNewest`).
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [liveIncomingPath]))
        h.script.add("!b", bridgedImageEvent(id: "$b4", room: "!b", at: 4, mediaPath: liveIncomingPath))
        h.server.notify(["kind": "event", "room_id": "!b", "event_id": "$b4"])
        try await waitUntil { h.message("$b4") != nil }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [liveIncomingPath]), CGSize(width: 640, height: 480))

        // 7. Outgoing send (`composer.onSettled` -> `fetchNewest`) and bridge echo (`Change.status` -> `fetchNewest`).
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [outgoingSendPath]))
        h.script.add("!b", bridgedImageEvent(id: "$b5", room: "!b", at: 5, mediaPath: outgoingSendPath, mine: true, status: "sending"))
        h.conversation.composer.onSettled()
        try await waitUntil { h.message("$b5") != nil }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [outgoingSendPath]), CGSize(width: 720, height: 360))

        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [outgoingEchoPath]))
        h.script.replace("!b", bridgedImageEvent(id: "$b5", room: "!b", at: 5, mediaPath: outgoingEchoPath, mine: true, status: "sent"))
        h.server.notify(["kind": "status", "room_id": "!b", "event_id": "$b5"])
        try await waitUntil { h.message("$b5")?.mediaPath == outgoingEchoPath }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [outgoingEchoPath]), CGSize(width: 760, height: 380))

        // 8. Live edit turning a text message into a bridged image (`m.replace` -> `fetchNewest`).
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [editedImagePath]))
        h.script.add("!b", mediaEditEvent(id: "$b2-edit", replacing: "$b2", room: "!b", at: 6, mediaPath: editedImagePath))
        h.server.notify(["kind": "event", "room_id": "!b", "event_id": "$b2-edit"])
        try await waitUntil { h.message("$b2")?.kind == .image }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [editedImagePath]), CGSize(width: 840, height: 420))

        XCTAssertEqual(unwarmedOnPublish, [], "every ConversationModel path must warm header sizes before Timeline.build publishes items")
    }

    func testEveryThreadTimelinePathWarmsHeaderSizesBeforeItemsPublish() async throws {
        let threadRootPath = try writeImage(named: "thread-root.png", width: 960, height: 480)
        let threadOlderPath = try writeImage(named: "thread-older.png", width: 880, height: 440)
        let threadInitialPath = try writeImage(named: "thread-initial.png", width: 1000, height: 500)
        let threadLiveReplyPath = try writeImage(named: "thread-live.png", width: 600, height: 900)
        let threadEditPath = try writeImage(named: "thread-edit.png", width: 740, height: 370)

        var events: [[String: Any]] = [
            bridgedImageEvent(
                id: "$r",
                room: "!t",
                at: 1,
                mediaPath: threadRootPath,
                threadSummary: [
                    "replies": 55,
                    "last_ts": ConversationScript.timestamp(56),
                    "last_senders": ["Ann"],
                    "unread": 0,
                    "unread_mentions_me": false,
                ]
            ),
        ]
        // 55 thread-only replies so the newest page (50) omits both `$r` (forcing `ThreadModel.fetchRoot`) and `$t1`
        // (forcing `ThreadModel.loadOlder`).
        for replyIndex in 1 ... 55 {
            let n = Int64(replyIndex + 1)
            let id = "$t\(replyIndex)"
            if replyIndex == 1 {
                events.append(bridgedImageEvent(id: id, room: "!t", at: n, mediaPath: threadOlderPath, threadRootID: "$r"))
            } else if replyIndex == 55 {
                events.append(bridgedImageEvent(id: id, room: "!t", at: n, mediaPath: threadInitialPath, threadRootID: "$r"))
            } else {
                events.append(threadReply(id: id, root: "$r", room: "!t", at: n))
            }
        }
        // Keep `$r` off the main chat's newest page (50) so `ConversationModel.fetchNewest` does not warm `threadRootPath`
        // ahead of `ThreadModel.fetchRoot`.
        for mainIndex in 1 ... 55 {
            let n = Int64(100 + mainIndex)
            events.append(textEvent(id: "$main\(mainIndex)", room: "!t", at: n, body: "Main \(mainIndex)"))
        }

        let h = try await startConversation(
            ["!t": events],
            features: ["!t": featuresJSON(replyIsThread: true)],
            rows: ["!t": chatRow("!t", name: "Engineering", network: "slack", direct: false)]
        )
        harnesses.append(h)
        try await h.open("!t")
        XCTAssertNil(h.message("$r"), "root is older than the chat's newest 50 main-timeline events")
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [threadRootPath]))
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [threadInitialPath]))
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [threadOlderPath]))

        let thread = h.conversation.thread
        var unwarmedOnPublish: [String] = []
        let sub = thread.$items.sink { items in
            for case let .message(msg) in items where msg.kind == .image && (msg.width ?? 0) <= 0 {
                if ImagePixelSizeReader.cachedSize(ofFirstReadable: [msg.mediaPath, msg.thumbnailPath]) == nil {
                    unwarmedOnPublish.append("\(msg.id):\(msg.mediaPath)")
                }
            }
        }
        defer { sub.cancel() }

        // 1 & 2. Thread initial newest page (`ThreadModel.fetchNewest`) + standalone root (`ThreadModel.fetchRoot`).
        h.conversation.openThread("$r")
        try await waitUntil {
            thread.isLoaded && h.messageIDs(thread.items).contains("$r") && h.messageIDs(thread.items).contains("$t55")
        }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [threadInitialPath]), CGSize(width: 1000, height: 500))
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [threadRootPath]), CGSize(width: 960, height: 480))
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [threadOlderPath]))

        // 3. Thread older page (`ThreadModel.loadOlder`).
        XCTAssertTrue(thread.hasOlder)
        thread.loadOlder()
        try await waitUntil { h.messageIDs(thread.items).contains("$t1") && !thread.isLoadingOlder }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [threadOlderPath]), CGSize(width: 880, height: 440))

        // 4. Live incoming thread image reply (`Change.event` -> `ThreadModel.fetchNewest`).
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [threadLiveReplyPath]))
        h.script.add("!t", bridgedImageEvent(id: "$t56", room: "!t", at: 57, mediaPath: threadLiveReplyPath, threadRootID: "$r"))
        h.server.notify(["kind": "event", "room_id": "!t", "event_id": "$t56"])
        try await waitUntil { h.messageIDs(thread.items).contains("$t56") }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [threadLiveReplyPath]), CGSize(width: 600, height: 900))

        // 5. Live media edit of a thread reply (`m.replace` -> `ThreadModel.fetchNewest`).
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [threadEditPath]))
        h.script.add("!t", mediaEditEvent(id: "$t54-edit", replacing: "$t54", room: "!t", at: 58, mediaPath: threadEditPath))
        h.server.notify(["kind": "event", "room_id": "!t", "event_id": "$t54-edit"])
        try await waitUntil { thread.message("$t54")?.kind == .image }
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [threadEditPath]), CGSize(width: 740, height: 370))

        XCTAssertEqual(unwarmedOnPublish, [], "every ThreadModel path must warm header sizes before Timeline.build publishes items")
    }

    func testImagePixelSizeReaderRecoversAfterEmptyAndCorruptFilesAreReplaced() throws {
        // 0-byte empty file stays uncached and resolves once populated.
        let emptyURL = directory.appendingPathComponent("empty-then-valid.png")
        try Data().write(to: emptyURL)
        XCTAssertNil(ImagePixelSizeReader.sizeNow(ofFirstReadable: [emptyURL.path]))
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [emptyURL.path]))
        _ = try writeImage(named: "empty-then-valid.png", width: 640, height: 320)
        XCTAssertEqual(ImagePixelSizeReader.sizeNow(ofFirstReadable: [emptyURL.path]), CGSize(width: 640, height: 320))
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [emptyURL.path]), CGSize(width: 640, height: 320))

        // Non-empty corrupt file records a failure for that FileStamp, then re-reads when replaced with a valid image.
        let corruptURL = directory.appendingPathComponent("partial-then-exif6.jpg")
        try Data("not-a-valid-jpeg-yet".utf8).write(to: corruptURL)
        XCTAssertNil(ImagePixelSizeReader.sizeNow(ofFirstReadable: [corruptURL.path]))
        XCTAssertNil(ImagePixelSizeReader.cachedSize(ofFirstReadable: [corruptURL.path]))
        _ = try writeImage(named: "partial-then-exif6.jpg", type: .jpeg, width: 1000, height: 600, orientation: 6)
        XCTAssertEqual(ImagePixelSizeReader.sizeNow(ofFirstReadable: [corruptURL.path]), CGSize(width: 600, height: 1000))
        XCTAssertEqual(ImagePixelSizeReader.cachedSize(ofFirstReadable: [corruptURL.path]), CGSize(width: 600, height: 1000))
    }

    func testSmallEXIFOrientation3RotatesPixels180Degrees() async throws {
        // Orientation 3 keeps width/height (200x100 <= 640) unchanged, so only pixel inspection proves the transform ran.
        let width = 200
        let height = 100
        let space = CGColorSpaceCreateDeviceRGB()
        let srcCtx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // CoreGraphics origin is bottom-left: fill bottom half pure blue, top half pure red.
        srcCtx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        srcCtx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        srcCtx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        srcCtx.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        let rawImage = try XCTUnwrap(srcCtx.makeImage())

        let url = directory.appendingPathComponent("exif3-small.jpg")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, rawImage, [kCGImagePropertyOrientation: 3] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let loader = ThumbnailLoader()
        let thumb = await loader.thumbnail(atPath: url.path)
        let decoded = try XCTUnwrap(thumb?.image)
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let readCtx = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        readCtx.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Row 10 in buffer is near the top of the rendered image; after 180° rotation the stored bottom-half blue is now at the top.
        let topSampleOffset = (10 * width + width / 2) * 4
        let bottomSampleOffset = ((height - 10) * width + width / 2) * 4
        XCTAssertGreaterThan(pixels[topSampleOffset + 2], 180, "top of rotated image should be blue")
        XCTAssertLessThan(pixels[topSampleOffset], 80, "top of rotated image should not be red")
        XCTAssertGreaterThan(pixels[bottomSampleOffset], 180, "bottom of rotated image should be red")
        XCTAssertLessThan(pixels[bottomSampleOffset + 2], 80, "bottom of rotated image should not be blue")
    }

    nonisolated func testSharedLinkDetectorSerializesConcurrentAccessAcrossCallers() async {
        let reference = Date(timeIntervalSince1970: 1_760_600_000)
        await withTaskGroup(of: Bool.self) { group in
            for i in 0 ..< 24 {
                group.addTask {
                    let text = "Join https://meet.google.com/abc-defg-hij tomorrow at 3pm or mailto:qa\(i)@example.com"
                    let nsRange = NSRange(text.startIndex..., in: text)
                    let matches = SharedLinkDetector.matches(in: text, range: nsRange)
                    let first = MessageActions.firstLink(in: RichText(text: text))
                    let meeting = CalendarBridge.extractMeetingURL(from: text)
                    let dates = CalendarBridge.detectDates(in: text, referenceDate: reference)
                    return matches.count == 2
                        && first?.absoluteString == "https://meet.google.com/abc-defg-hij"
                        && meeting?.absoluteString == "https://meet.google.com/abc-defg-hij"
                        && dates.count == 1
                }
            }
            for await ok in group {
                XCTAssertTrue(ok)
            }
        }
    }
}
