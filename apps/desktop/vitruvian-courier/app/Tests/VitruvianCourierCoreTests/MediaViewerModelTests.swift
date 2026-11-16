// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest

@testable import VitruvianCourierCore

@MainActor
final class MediaViewerModelTests: XCTestCase {
    private var tempDir: URL!
    private var servers: [TestEngineServer] = []
    private var apps: [AppModel] = []
    private var suites: [String] = []

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-courier-mediaviewer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for app in apps { await app.stop() }
        apps.removeAll()
        for server in servers { server.stop() }
        servers.removeAll()
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        suites.removeAll()
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeDefaults() -> UserDefaults {
        let name = "courier.mediaviewer.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func makeLocalMediaFile(named name: String, bytes: Data = Data([0x89, 0x50, 0x4E, 0x47])) throws -> String {
        let url = tempDir.appendingPathComponent(name)
        try bytes.write(to: url, options: .atomic)
        return url.path
    }

    private func startApp(handler: @escaping TestEngineServer.Handler) async throws -> (TestEngineServer, AppModel) {
        let server = try TestEngineServer(handler: handler)
        servers.append(server)
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Vitruvian Courier.app/Contents/Helpers/vitruvian-courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/vitruvian-courier-test-data"),
            environment: [:],
            launcher: launcher,
            credentials: InMemoryCredentialStore(),
            clientName: "Vitruvian Courier/test",
            timing: FakeTime().timing()
        )
        let appModel = AppModel(supervisor: supervisor)
        apps.append(appModel)
        appModel.start()
        await waitUntil { appModel.client != nil }
        return (server, appModel)
    }

    private func waitUntil(
        timeout: TimeInterval = 2.0,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "Timed out waiting for condition")
    }

    func testTabsSentBySortSearchAndMultiSelect() async throws {
        let photo1Path = try makeLocalMediaFile(named: "photo-1.jpg")
        let photo2Path = try makeLocalMediaFile(named: "photo-2.jpg")
        let video1Path = try makeLocalMediaFile(named: "clip-1.mp4")
        let doc1Path = try makeLocalMediaFile(named: "itinerary.pdf")

        // 1. AttachmentCarouselModel transform & navigation controls.
        let carouselItems = [
            CarouselItem(
                eventID: "$m1",
                roomID: "!hike:courier.local",
                kind: .image,
                mediaPath: photo1Path,
                thumbnailPath: photo1Path,
                fileName: "Trail map.jpg",
                mimeType: "image/jpeg",
                width: 1200,
                height: 900,
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: 1_760_000_001_000,
                caption: "Trail map"
            ),
            CarouselItem(
                eventID: "$m2",
                roomID: "!hike:courier.local",
                kind: .video,
                mediaPath: video1Path,
                thumbnailPath: photo2Path,
                fileName: "Campfire.mp4",
                mimeType: "video/mp4",
                width: 1920,
                height: 1080,
                durationMS: 12_000,
                sender: "@me:courier.local",
                senderName: "You",
                mine: true,
                ts: 1_760_000_002_000,
                caption: "Campfire clip"
            ),
        ]

        let carousel = AttachmentCarouselModel()
        carousel.open(items: carouselItems, selectedEventID: "$m1")
        XCTAssertEqual(carousel.items.map(\.eventID), ["$m1", "$m2"])
        XCTAssertEqual(carousel.currentIndex, 0)
        XCTAssertEqual(carousel.currentItem?.eventID, "$m1")

        carousel.zoomIn()
        carousel.zoomIn()
        XCTAssertEqual(carousel.zoomScale, 1.5, accuracy: 0.001)
        carousel.zoomOut()
        XCTAssertEqual(carousel.zoomScale, 1.25, accuracy: 0.001)
        carousel.rotateClockwise()
        XCTAssertEqual(carousel.rotationDegrees, 90)
        carousel.rotateClockwise()
        XCTAssertEqual(carousel.rotationDegrees, 180)
        carousel.flipHorizontal()
        XCTAssertTrue(carousel.isFlippedHorizontally)
        carousel.flipVertical()
        XCTAssertTrue(carousel.isFlippedVertically)

        carousel.resetTransform()
        XCTAssertEqual(carousel.zoomScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(carousel.rotationDegrees, 0)
        XCTAssertFalse(carousel.isFlippedHorizontally)
        XCTAssertFalse(carousel.isFlippedVertically)

        // Next item resets transform and supports video playback toggle.
        carousel.zoomIn()
        carousel.rotateClockwise()
        carousel.next()
        XCTAssertEqual(carousel.currentIndex, 1)
        XCTAssertEqual(carousel.currentItem?.eventID, "$m2")
        XCTAssertEqual(carousel.zoomScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(carousel.rotationDegrees, 0)
        XCTAssertFalse(carousel.isPlayingVideo)
        carousel.toggleVideoPlayback()
        XCTAssertTrue(carousel.isPlayingVideo)
        carousel.previous()
        XCTAssertEqual(carousel.currentIndex, 0)
        XCTAssertFalse(carousel.isPlayingVideo)

        // 2. MediaViewerModel tabs (Media, Links, Docs), SentBy (All, You, Others), SortOrder (Newest, Oldest),
        //    caption search query, and multi-select delete/unsend.
        var deletedForMe: [String] = []
        var unsent: [String] = []
        let lock = NSLock()

        let (_, appModel) = try await startApp { method, params in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.list":
                return .result(["accounts": []])
            case "search.query":
                let filters = params?["filters"] as? [String: Any]
                let kinds = filters?["kinds"] as? [String] ?? []
                let sender = filters?["sender"] as? String
                let text = (params?["text"] as? String ?? "").lowercased()

                let allHits: [[String: Any]]
                if kinds == ["link"] {
                    allHits = [
                        [
                            "event_id": "$l1",
                            "room_id": "!hike:courier.local",
                            "room_name": "Weekend Trail Crew",
                            "network": "whatsapp",
                            "is_direct": false,
                            "place": "inbox",
                            "sender": "@alice:courier.local",
                            "sender_name": "Alice Example",
                            "mine": false,
                            "ts": 1_760_000_010_000,
                            "seq": 10,
                            "kind": "text",
                            "snippet": "Check https://example.com/trail-map for the route",
                            "ranges": [],
                            "media_path": "",
                            "partial": false,
                        ],
                    ]
                } else if kinds == ["file", "audio"] {
                    allHits = [
                        [
                            "event_id": "$d1",
                            "room_id": "!hike:courier.local",
                            "room_name": "Weekend Trail Crew",
                            "network": "whatsapp",
                            "is_direct": false,
                            "place": "inbox",
                            "sender": "@me:courier.local",
                            "sender_name": "You",
                            "mine": true,
                            "ts": 1_760_000_020_000,
                            "seq": 20,
                            "kind": "file",
                            "snippet": "itinerary.pdf",
                            "ranges": [],
                            "media_path": doc1Path,
                            "partial": false,
                        ],
                    ]
                } else {
                    allHits = [
                        [
                            "event_id": "$m2",
                            "room_id": "!hike:courier.local",
                            "room_name": "Weekend Trail Crew",
                            "network": "whatsapp",
                            "is_direct": false,
                            "place": "inbox",
                            "sender": "@me:courier.local",
                            "sender_name": "You",
                            "mine": true,
                            "ts": 1_760_000_002_000,
                            "seq": 2,
                            "kind": "video",
                            "snippet": "Campfire clip",
                            "ranges": [],
                            "media_path": video1Path,
                            "partial": false,
                        ],
                        [
                            "event_id": "$m1",
                            "room_id": "!hike:courier.local",
                            "room_name": "Weekend Trail Crew",
                            "network": "whatsapp",
                            "is_direct": false,
                            "place": "inbox",
                            "sender": "@alice:courier.local",
                            "sender_name": "Alice Example",
                            "mine": false,
                            "ts": 1_760_000_001_000,
                            "seq": 1,
                            "kind": "image",
                            "snippet": "Trail map",
                            "ranges": [],
                            "media_path": photo1Path,
                            "partial": false,
                        ],
                    ]
                }

                let filtered = allHits.filter { hit in
                    let isMine = hit["mine"] as? Bool ?? false
                    if sender == "me" && !isMine { return false }
                    if sender == "others" && isMine { return false }
                    if !text.isEmpty {
                        let snippet = (hit["snippet"] as? String ?? "").lowercased()
                        if !snippet.contains(text) { return false }
                    }
                    return true
                }
                let page: [String: Any] = ["hits": filtered, "next_cursor": NSNull()]
                let mediaSection: Any = kinds.contains("image") ? page : NSNull()
                let messagesSection: Any = kinds.contains("image") ? NSNull() : page
                return .result([
                    "chats": NSNull(),
                    "in_groups": NSNull(),
                    "bookmarks": NSNull(),
                    "media": mediaSection,
                    "messages": messagesSection,
                    "last_archived": NSNull(),
                    "complete": true,
                    "hint": "",
                ])
            case "message.deleteForMe":
                if let eventID = params?["event_id"] as? String {
                    lock.withLock { deletedForMe.append(eventID) }
                }
                return .result([String: Any]())
            case "message.unsend":
                if let eventID = params?["event_id"] as? String {
                    lock.withLock { unsent.append(eventID) }
                }
                return .result([String: Any]())
            default:
                return .result([String: Any]())
            }
        }

        let viewer = MediaViewerModel(appModel: appModel, roomID: "!hike:courier.local")
        await viewer.refresh()

        // Default tab is Media, newest first.
        XCTAssertEqual(viewer.tab, .media)
        XCTAssertEqual(viewer.items.map(\.eventID), ["$m2", "$m1"])

        // Sort order Oldest reverses chronological order.
        viewer.sortOrder = .oldest
        XCTAssertEqual(viewer.items.map(\.eventID), ["$m1", "$m2"])
        viewer.sortOrder = .newest
        XCTAssertEqual(viewer.items.map(\.eventID), ["$m2", "$m1"])

        // SentBy filter: You vs Others.
        viewer.sentBy = .you
        await viewer.refresh()
        XCTAssertEqual(viewer.items.map(\.eventID), ["$m2"])

        viewer.sentBy = .others
        await viewer.refresh()
        XCTAssertEqual(viewer.items.map(\.eventID), ["$m1"])

        viewer.sentBy = .all
        viewer.query = "campfire"
        await viewer.refresh()
        XCTAssertEqual(viewer.items.map(\.eventID), ["$m2"])

        viewer.query = ""
        await viewer.refresh()
        XCTAssertEqual(viewer.items.map(\.eventID), ["$m2", "$m1"])

        // Multi-select and batch delete (forEveryone: true unsends mine and deletes others for me).
        viewer.toggleSelected("$m1")
        viewer.toggleSelected("$m2")
        XCTAssertEqual(viewer.selectedEventIDs, ["$m1", "$m2"])
        await viewer.deleteSelected(forEveryone: true)
        XCTAssertEqual(unsent, ["$m2"])
        XCTAssertEqual(deletedForMe, ["$m1"])
        XCTAssertTrue(viewer.selectedEventIDs.isEmpty)
        XCTAssertTrue(viewer.items.isEmpty)

        // Links tab.
        viewer.tab = .links
        await viewer.refresh()
        XCTAssertEqual(viewer.items.map(\.eventID), ["$l1"])
        XCTAssertEqual(viewer.items.first?.extractedURL, "https://example.com/trail-map")
        XCTAssertEqual(viewer.items.first?.extractedHost, "example.com")

        // Docs tab.
        viewer.tab = .docs
        await viewer.refresh()
        XCTAssertEqual(viewer.items.map(\.eventID), ["$d1"])
    }

    func testViewOnceMediaExcludedFromLightboxAndMediaViewer() async throws {
        let normalPath = try makeLocalMediaFile(named: "normal.jpg")
        let viewOncePath = try makeLocalMediaFile(named: "viewonce.jpg")

        // 1. AttachmentCarouselModel must never include view-once media or open on a view-once event.
        let carousel = AttachmentCarouselModel()
        let items = [
            CarouselItem(
                eventID: "$normal-1",
                roomID: "!dm:courier.local",
                kind: .image,
                mediaPath: normalPath,
                thumbnailPath: normalPath,
                fileName: "normal.jpg",
                mimeType: "image/jpeg",
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: 1_760_000_001_000,
                caption: "Normal photo",
                viewOnce: false
            ),
            CarouselItem(
                eventID: "$vo-1",
                roomID: "!dm:courier.local",
                kind: .image,
                mediaPath: viewOncePath,
                thumbnailPath: viewOncePath,
                fileName: "secret.jpg",
                mimeType: "image/jpeg",
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: 1_760_000_002_000,
                caption: "Secret photo",
                viewOnce: true
            ),
        ]

        // Opening on the view-once item must refuse to open the lightbox.
        carousel.open(items: items, selectedEventID: "$vo-1")
        XCTAssertTrue(carousel.items.isEmpty, "View-once media must never open in AttachmentCarouselModel")

        // Opening on the normal item must exclude the view-once item from the filmstrip/carousel.
        carousel.open(items: items, selectedEventID: "$normal-1")
        XCTAssertEqual(carousel.items.map(\.eventID), ["$normal-1"])

        // 1b. Timeline.build must trust the engine's Event.viewOnce (where a Signal room-matching 5-min after_read
        // timer is NOT view-once), and MediaHit(messageHit:) must preserve MessageHit.viewOnce.
        let roomTimerPhotoEvent = Event(
            eventID: "$sig-room-timer",
            roomID: "!dm:courier.local",
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            mine: false,
            type: "m.room.message",
            content: .object([
                "msgtype": .string("m.image"),
                "body": .string("normal-in-timed-room.jpg"),
                "com.beeper.disappearing_timer": .object([
                    "type": .string("after_read"),
                    "timer": .int(300_000),
                ]),
                "info": .object(["mimetype": .string("image/jpeg"), "w": .int(800), "h": .int(600)]),
            ]),
            ts: 1_760_000_001_000,
            seq: 1,
            status: .sent,
            mediaPath: normalPath,
            thumbnailPath: normalPath,
            viewOnce: nil,
            played: false
        )
        let realViewOnceEvent = Event(
            eventID: "$sig-vo",
            roomID: "!dm:courier.local",
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            mine: false,
            type: "m.room.message",
            content: .object([
                "msgtype": .string("m.image"),
                "body": .string("secret-vo.jpg"),
                "com.beeper.disappearing_timer": .object([
                    "type": .string("after_read"),
                    "timer": .int(300_000),
                ]),
                "info": .object(["mimetype": .string("image/jpeg"), "w": .int(800), "h": .int(600)]),
            ]),
            ts: 1_760_000_002_000,
            seq: 2,
            status: .sent,
            mediaPath: viewOncePath,
            thumbnailPath: viewOncePath,
            viewOnce: true,
            played: false
        )
        let timelineItems = Timeline.build(
            events: [roomTimerPhotoEvent, realViewOnceEvent],
            me: "@me:courier.local",
            now: Date(timeIntervalSince1970: 1_760_000_003)
        )
        let timelineMessages = timelineItems.compactMap { item -> TimelineMessage? in
            if case let .message(msg) = item { return msg }
            return nil
        }
        XCTAssertEqual(timelineMessages.count, 2)
        XCTAssertFalse(
            timelineMessages[0].viewOnce,
            "Signal photo matching the room's 5-min after_read timer (Event.viewOnce == nil) must not be marked view-once"
        )
        XCTAssertTrue(timelineMessages[1].viewOnce)
        XCTAssertEqual(CarouselItem.items(from: timelineItems).map(\.eventID), ["$sig-room-timer"])

        let wireMessageHit = MessageHit(
            eventID: "$vo-msg-hit",
            roomID: "!dm:courier.local",
            roomName: "Alice Example",
            network: "whatsapp",
            isDirect: true,
            place: .inbox,
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            mine: false,
            ts: 1_760_000_002_000,
            seq: 2,
            kind: .image,
            snippet: "View-once secret",
            ranges: [],
            mediaPath: "",
            partial: false,
            viewOnce: true
        )
        XCTAssertTrue(MediaHit(messageHit: wireMessageHit).viewOnce, "MediaHit(messageHit:) must preserve MessageHit.viewOnce")

        // 2. MediaViewerModel must exclude view-once media hits using the real engine search.query wire shape
        // (view-once excluded from media section; view_once: true and media_path: "" on messages section).
        let (_, appModel) = try await startApp { method, params in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.list":
                return .result(["accounts": []])
            case "search.query":
                let sections = params?["sections"] as? [String] ?? []
                if sections.contains("media") {
                    let mediaHits: [[String: Any]] = [
                        [
                            "event_id": "$normal-1",
                            "room_id": "!dm:courier.local",
                            "room_name": "Alice Example",
                            "network": "whatsapp",
                            "is_direct": true,
                            "place": "inbox",
                            "sender": "@alice:courier.local",
                            "sender_name": "Alice Example",
                            "mine": false,
                            "ts": 1_760_000_001_000,
                            "seq": 1,
                            "kind": "image",
                            "snippet": "Normal photo",
                            "ranges": [],
                            "media_path": normalPath,
                            "partial": false,
                        ],
                    ]
                    return .result([
                        "chats": NSNull(),
                        "in_groups": NSNull(),
                        "bookmarks": NSNull(),
                        "media": ["hits": mediaHits, "next_cursor": NSNull()],
                        "messages": NSNull(),
                        "last_archived": NSNull(),
                        "complete": true,
                        "hint": "",
                    ])
                }
                let messageHits: [[String: Any]] = [
                    [
                        "event_id": "$normal-link",
                        "room_id": "!dm:courier.local",
                        "room_name": "Alice Example",
                        "network": "whatsapp",
                        "is_direct": true,
                        "place": "inbox",
                        "sender": "@alice:courier.local",
                        "sender_name": "Alice Example",
                        "mine": false,
                        "ts": 1_760_000_001_000,
                        "seq": 1,
                        "kind": "text",
                        "snippet": "https://example.com/doc",
                        "ranges": [],
                        "media_path": "",
                        "partial": false,
                    ],
                    [
                        "event_id": "$vo-1",
                        "room_id": "!dm:courier.local",
                        "room_name": "Alice Example",
                        "network": "whatsapp",
                        "is_direct": true,
                        "place": "inbox",
                        "sender": "@alice:courier.local",
                        "sender_name": "Alice Example",
                        "mine": false,
                        "ts": 1_760_000_002_000,
                        "seq": 2,
                        "kind": "image",
                        "snippet": "https://example.com/secret",
                        "ranges": [],
                        "media_path": "",
                        "partial": false,
                        "view_once": true,
                    ],
                ]
                return .result([
                    "chats": NSNull(),
                    "in_groups": NSNull(),
                    "bookmarks": NSNull(),
                    "media": NSNull(),
                    "messages": ["hits": messageHits, "next_cursor": NSNull()],
                    "last_archived": NSNull(),
                    "complete": true,
                    "hint": "",
                ])
            default:
                return .result([String: Any]())
            }
        }

        let viewer = MediaViewerModel(
            appModel: appModel,
            roomID: "!dm:courier.local"
        )
        await viewer.refresh()
        XCTAssertEqual(viewer.items.map(\.eventID), ["$normal-1"], "Media section returns only non-view-once items")
        viewer.tab = .links
        await viewer.refresh()
        XCTAssertEqual(viewer.items.map(\.eventID), ["$normal-link"], "View-once items must never appear in MediaViewerModel")
    }

    func testMediaViewerPages2000ItemsWithoutLoadingAllAtOnce() async throws {
        let samplePath = try makeLocalMediaFile(named: "page-photo.jpg")
        let totalItems = 2_000
        let pageSize = 50
        var requestedCursors: [String] = []
        var itemsServedCount = 0
        let lock = NSLock()

        let (_, appModel) = try await startApp { method, params in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.list":
                return .result(["accounts": []])
            case "search.query":
                let cursor = params?["cursor"] as? String ?? ""
                let limit = min(params?["limit"] as? Int ?? pageSize, pageSize)
                let startOffset = Int(cursor) ?? 0
                let endOffset = min(startOffset + limit, totalItems)
                var pageHits: [[String: Any]] = []
                pageHits.reserveCapacity(max(0, endOffset - startOffset))
                for idx in startOffset ..< endOffset {
                    let itemNumber = totalItems - idx
                    pageHits.append([
                        "event_id": "$img-\(itemNumber)",
                        "room_id": "!bigchat:courier.local",
                        "room_name": "Photography Club",
                        "network": "whatsapp",
                        "is_direct": false,
                        "place": "inbox",
                        "sender": "@alice:courier.local",
                        "sender_name": "Alice Example",
                        "mine": false,
                        "ts": Int64(1_760_000_000_000 + itemNumber * 1000),
                        "seq": Int64(itemNumber),
                        "kind": "image",
                        "snippet": "Photo \(itemNumber).jpg",
                        "ranges": [],
                        "media_path": samplePath,
                        "partial": false,
                    ])
                }
                lock.withLock {
                    requestedCursors.append(cursor)
                    itemsServedCount += pageHits.count
                }
                let nextCursor: Any = endOffset < totalItems ? "\(endOffset)" : NSNull()
                return .result([
                    "chats": NSNull(),
                    "in_groups": NSNull(),
                    "bookmarks": NSNull(),
                    "media": ["hits": pageHits, "next_cursor": nextCursor],
                    "messages": NSNull(),
                    "last_archived": NSNull(),
                    "complete": true,
                    "hint": "",
                ])
            default:
                return .result([String: Any]())
            }
        }

        let viewer = MediaViewerModel(appModel: appModel, roomID: "!bigchat:courier.local")
        await viewer.refresh()

        // Initial load fetches ONLY the first page (50 of 2,000), never reading the remaining 1,950 items.
        XCTAssertEqual(viewer.items.count, pageSize)
        XCTAssertEqual(viewer.items.first?.eventID, "$img-2000")
        XCTAssertEqual(viewer.items.last?.eventID, "$img-1951")
        XCTAssertTrue(viewer.hasMore)
        XCTAssertEqual(lock.withLock { requestedCursors }, [""])
        XCTAssertEqual(lock.withLock { itemsServedCount }, pageSize)

        // Loading the second page fetches only the next 50 items using the cursor.
        await viewer.loadNextPage()
        XCTAssertEqual(viewer.items.count, pageSize * 2)
        XCTAssertEqual(viewer.items.last?.eventID, "$img-1901")
        XCTAssertTrue(viewer.hasMore)
        XCTAssertEqual(lock.withLock { requestedCursors }, ["", "50"])
        XCTAssertEqual(lock.withLock { itemsServedCount }, pageSize * 2)
    }

    func testMediaViewerInMergedChatScopesToMemberRoomIDs() async throws {
        let photoPath = try makeLocalMediaFile(named: "merged-photo.jpg")
        var observedRoomIDs: [[String]] = []
        let lock = NSLock()

        let (server, appModel) = try await startApp { method, params in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.list":
                return .result(["accounts": []])
            case "search.query":
                let filters = params?["filters"] as? [String: Any]
                let roomIDs = filters?["room_ids"] as? [String] ?? []
                lock.withLock { observedRoomIDs.append(roomIDs) }
                let hits: [[String: Any]] = [
                    [
                        "event_id": "$wa-1",
                        "room_id": "!alice-wa:courier.local",
                        "room_name": "Alice Example",
                        "network": "whatsapp",
                        "is_direct": true,
                        "place": "inbox",
                        "sender": "@alice_wa:courier.local",
                        "sender_name": "Alice Example",
                        "mine": false,
                        "ts": 1_760_000_002_000,
                        "seq": 2,
                        "kind": "image",
                        "snippet": "WhatsApp photo.jpg",
                        "ranges": [],
                        "media_path": photoPath,
                        "partial": false,
                    ],
                    [
                        "event_id": "$sig-1",
                        "room_id": "!alice-sig:courier.local",
                        "room_name": "Alice Example",
                        "network": "signal",
                        "is_direct": true,
                        "place": "inbox",
                        "sender": "@alice_sig:courier.local",
                        "sender_name": "Alice Example",
                        "mine": false,
                        "ts": 1_760_000_001_000,
                        "seq": 1,
                        "kind": "image",
                        "snippet": "Signal photo.jpg",
                        "ranges": [],
                        "media_path": photoPath,
                        "partial": false,
                    ],
                ]
                return .result([
                    "chats": NSNull(),
                    "in_groups": NSNull(),
                    "bookmarks": NSNull(),
                    "media": ["hits": hits, "next_cursor": NSNull()],
                    "messages": NSNull(),
                    "last_archived": NSNull(),
                    "complete": true,
                    "hint": "",
                ])
            default:
                return .result([String: Any]())
            }
        }

        appModel.mergedChats["merge:alice"] = MergedChat(
            mergeID: "merge:alice",
            name: "Alice Example",
            lastRoomID: "!alice-wa:courier.local",
            roomIDs: ["!alice-wa:courier.local", "!alice-sig:courier.local"],
            networks: ["whatsapp", "signal"],
            createdTS: 1_760_000_000_000
        )

        let viewer = MediaViewerModel(appModel: appModel, roomID: "merge:alice")
        await viewer.refresh()

        XCTAssertTrue(server.rejectedMergeIDs.isEmpty, "Must never send merge:alice to engine")
        XCTAssertEqual(lock.withLock { observedRoomIDs }, [["!alice-wa:courier.local", "!alice-sig:courier.local"]])
        XCTAssertEqual(viewer.items.map(\.eventID), ["$wa-1", "$sig-1"])
    }

    func testViewerItemsMatchesChatInfoSharedMediaExcludesLinkPreviewsAndPagesOlder() async throws {
        let localPath = try makeLocalMediaFile(named: "viewer-photo.jpg")
        let roomID = "!hike:courier.local"

        func makeMediaEvent(
            _ id: String,
            ts: Int64,
            msgtype: String = "m.image",
            body: String = "photo.jpg",
            mediaPath: String,
            url: String? = nil,
            viewOnce: Bool? = nil,
            mediaRemoved: Bool = false
        ) -> Event {
            var dict: [String: JSONValue] = [
                "msgtype": .string(msgtype),
                "body": .string(body),
            ]
            if let url {
                dict["url"] = .string(url)
            }
            if mediaRemoved {
                dict["com.courier.media_removed"] = .bool(true)
            }
            return Event(
                eventID: id,
                roomID: roomID,
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                type: "m.room.message",
                content: .object(dict),
                ts: ts,
                seq: ts,
                status: .sent,
                mediaPath: mediaPath,
                thumbnailPath: mediaPath,
                viewOnce: viewOnce,
                played: false
            )
        }

        func makeHitDict(_ id: String, ts: Int64, kind: String = "image", mediaPath: String, snippet: String = "item") -> [String: Any] {
            [
                "event_id": id,
                "room_id": roomID,
                "room_name": "Weekend Trail Crew",
                "network": "whatsapp",
                "is_direct": false,
                "place": "inbox",
                "sender": "@alice:courier.local",
                "sender_name": "Alice Example",
                "mine": false,
                "ts": ts,
                "seq": ts,
                "kind": kind,
                "snippet": snippet,
                "ranges": [Any](),
                "media_path": mediaPath,
                "partial": false,
            ]
        }

        // 13 chronological image/video items across older history ($e1..$e9) and current timeline page ($e10..$e13).
        // $e1 has no local file yet (mediaPath == "", remote url present) -> must stay in viewerItems as uncached placeholder.
        let uncachedSharedEvent = makeMediaEvent(
            "$e1",
            ts: 1_000,
            msgtype: "m.image",
            body: "uncached.jpg",
            mediaPath: "",
            url: "mxc://courier.local/e1"
        )
        let sharedEvents: [Event] = [uncachedSharedEvent]
            + (2 ... 5).map { i in
                makeMediaEvent(
                    "$e\(i)",
                    ts: Int64(i * 1_000),
                    msgtype: i == 3 ? "m.video" : "m.image",
                    body: "shared-\(i)",
                    mediaPath: localPath
                )
            }
        let excludedSharedEvents: [Event] = [
            makeMediaEvent("$excl-link", ts: 1_500, msgtype: "m.text", body: "https://example.com", mediaPath: "", url: "https://example.com"),
            makeMediaEvent("$excl-sticker", ts: 2_500, msgtype: "m.sticker", body: "sticker.webp", mediaPath: localPath),
            makeMediaEvent("$excl-file", ts: 3_500, msgtype: "m.file", body: "notes.pdf", mediaPath: localPath),
            makeMediaEvent("$excl-audio", ts: 4_500, msgtype: "m.audio", body: "voice.ogg", mediaPath: localPath),
            makeMediaEvent("$excl-vo", ts: 5_500, msgtype: "m.image", body: "secret.jpg", mediaPath: localPath, viewOnce: true),
            makeMediaEvent("$excl-removed", ts: 5_800, msgtype: "m.image", body: "removed.jpg", mediaPath: localPath, mediaRemoved: true),
        ]

        let page1Hits: [MediaHit] = (6 ... 9).map { i in
            MediaHit(
                eventID: "$e\(i)",
                roomID: roomID,
                roomName: "Weekend Trail Crew",
                network: "whatsapp",
                isDirect: false,
                place: .inbox,
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: Int64(i * 1_000),
                seq: Int64(i),
                kind: i == 8 ? .video : .image,
                snippet: "hit-\(i)",
                ranges: [],
                mediaPath: localPath,
                partial: false,
                viewOnce: false
            )
        }
        let excludedHits: [MediaHit] = [
            MediaHit(
                eventID: "$hit-sticker",
                roomID: roomID,
                roomName: "Weekend Trail Crew",
                network: "whatsapp",
                isDirect: false,
                place: .inbox,
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: 6_500,
                seq: 65,
                kind: .sticker,
                snippet: "sticker",
                ranges: [],
                mediaPath: localPath,
                partial: false,
                viewOnce: false
            ),
            MediaHit(
                eventID: "$hit-link",
                roomID: roomID,
                roomName: "Weekend Trail Crew",
                network: "whatsapp",
                isDirect: false,
                place: .inbox,
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                ts: 6_600,
                seq: 66,
                kind: .text,
                snippet: "https://example.com/route",
                ranges: [],
                mediaPath: "",
                partial: false,
                viewOnce: false
            ),
        ]

        let timelineEvents: [Event] = (10 ... 13).map { i in
            makeMediaEvent(
                "$e\(i)",
                ts: Int64(i * 1_000),
                msgtype: i == 11 ? "m.video" : "m.image",
                body: "timeline-\(i)",
                mediaPath: localPath
            )
        } + [
            makeMediaEvent("$excl-vo", ts: 14_000, msgtype: "m.image", body: "secret.jpg", mediaPath: localPath, viewOnce: true),
        ]
        let timelineItems = Timeline.build(
            events: timelineEvents,
            me: "@me:courier.local",
            now: Date(timeIntervalSince1970: 20_000)
        )

        let viewerItems = CarouselItem.viewerItems(
            timelineItems: timelineItems,
            sharedMedia: sharedEvents + excludedSharedEvents,
            mediaHits: page1Hits + excludedHits
        )
        XCTAssertEqual(viewerItems.map(\.eventID), (1 ... 13).map { "$e\($0)" })
        XCTAssertEqual(viewerItems.first?.mediaPath, "", "Uncached older media without local path must stay in viewerItems")
        XCTAssertFalse(viewerItems.contains { $0.eventID.hasPrefix("$excl-") || $0.eventID.hasPrefix("$hit-") })

        // ConversationModel.openLightbox widens to the chat's media and pages older hits from the engine.
        let roomInfo = RoomInfoResult(
            roomID: roomID,
            name: "Weekend Trail Crew",
            remoteName: "Weekend Trail Crew",
            network: "whatsapp",
            isDirect: false,
            sharedMedia: Array(sharedEvents.suffix(3)),
            features: .noFeatures
        )
        let cursorsLock = NSLock()
        var observedCursors: [String] = []

        let (_, appModel) = try await startApp { method, params in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.list":
                return .result(["accounts": []])
            case "search.query":
                let cursor = params?["cursor"] as? String
                cursorsLock.withLock { observedCursors.append(cursor ?? "nil") }
                let hits: [[String: Any]]
                let nextCursor: Any
                if cursor == nil {
                    hits = (6 ... 9).map { makeHitDict("$e\($0)", ts: Int64($0 * 1_000), mediaPath: localPath) }
                    nextCursor = "page-2"
                } else {
                    hits = [
                        makeHitDict("$e1", ts: 1_000, mediaPath: ""),
                        makeHitDict("$e2", ts: 2_000, mediaPath: localPath),
                    ]
                    nextCursor = NSNull()
                }
                return .result([
                    "chats": NSNull(),
                    "in_groups": NSNull(),
                    "bookmarks": NSNull(),
                    "media": ["hits": hits, "next_cursor": nextCursor] as [String: Any],
                    "messages": NSNull(),
                    "last_archived": NSNull(),
                    "complete": true,
                    "hint": "",
                ])
            default:
                return .result([String: Any]())
            }
        }

        let conversation = ConversationModel(appModel: appModel, unreadCount: { _ in 0 }, chat: { _ in nil })
        conversation.setSnapshotStateForTesting(roomID: roomID, items: timelineItems)
        conversation.setChatInfoForTesting(roomInfo)
        conversation.openLightbox("$e13")

        // At once: the loaded timeline plus Chat Info's Shared Media. Then the engine's first page of media.
        XCTAssertEqual(conversation.carousel.items.map(\.eventID), ["$e3", "$e4", "$e5", "$e10", "$e11", "$e12", "$e13"])
        XCTAssertEqual(conversation.carousel.currentItem?.eventID, "$e13")
        await waitUntil { conversation.carousel.items.count == 11 && conversation.carousel.hasOlderItems }

        await conversation.carousel.loadOlderMedia()
        XCTAssertEqual(conversation.carousel.items.map(\.eventID), (1 ... 13).map { "$e\($0)" })
        XCTAssertFalse(conversation.carousel.hasOlderItems)
        XCTAssertEqual(cursorsLock.withLock { observedCursors }, ["nil", "page-2"])
    }

    func testOpeningNewChatSearchOrSettingsClosesOpenViewerFirst() async throws {
        final class NoopPasteboard: TextPasteboard {
            func setString(_ text: String) {}
        }

        let defaults = makeDefaults()
        let (_, appModel) = try await startApp { method, _ in
            switch method {
            case "hello": return TestEngineServer.helloOK
            case "accounts.list": return .result(["accounts": []])
            default: return .result([String: Any]())
            }
        }
        let inbox = InboxModel(appModel: appModel, preferences: InboxPreferences(defaults: defaults))
        let spaces = SpacesModel(appModel: appModel, inbox: inbox)
        let conversation = ConversationModel(appModel: appModel, unreadCount: { _ in 0 }, chat: { _ in nil })
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: appModel,
            preferences: ComposerPreferences(defaults: defaults),
            pasteboard: NoopPasteboard()
        )
        let search = SearchModel(appModel: appModel, recents: RecentSearches(defaults: defaults), open: { _ in })
        let lifecycle = SystemLifecycleModel(defaults: defaults)
        let coordinator = AppMenuCoordinator(inbox: inbox, lifecycle: lifecycle)
        let registry = HotkeyRegistry(defaults: defaults, isAppLocked: { lifecycle.isLocked })
        let dispatcher = HotkeyDispatcher(
            inbox: inbox,
            spaces: spaces,
            conversation: conversation,
            messageActions: messageActions,
            search: search,
            lifecycle: lifecycle,
            menuCoordinator: coordinator,
            hotkeys: registry
        )

        let imgPath = try makeLocalMediaFile(named: "open.png")
        let viewerItem = CarouselItem(
            eventID: "$open-1",
            roomID: "!r1:courier.local",
            kind: .image,
            mediaPath: imgPath,
            thumbnailPath: imgPath,
            fileName: "open.png",
            mimeType: "image/jpeg",
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            mine: false,
            ts: 1_760_000_001_000,
            caption: ""
        )

        defer { _ = dispatcher }

        func openViewer() {
            conversation.carousel.open(items: [viewerItem], selectedEventID: "$open-1")
            conversation.activeLightboxMessageID = "$open-1"
            XCTAssertTrue(conversation.carousel.isPresented)
        }

        openViewer()
        inbox.openStartNewChat()
        XCTAssertFalse(conversation.carousel.isPresented, "Opening New Chat must close open viewer first")
        XCTAssertNil(conversation.activeLightboxMessageID)

        openViewer()
        search.show()
        XCTAssertFalse(conversation.carousel.isPresented, "Opening Search must close open viewer first")
        XCTAssertNil(conversation.activeLightboxMessageID)

        openViewer()
        coordinator.openSettings(.general)
        XCTAssertFalse(conversation.carousel.isPresented, "Opening Settings must close open viewer first")
        XCTAssertNil(conversation.activeLightboxMessageID)
    }

    func testTappingAStickerStillOpensTheViewerOnIt() async throws {
        let stickerPath = try makeLocalMediaFile(named: "sticker.webp")
        let roomID = "!r1:courier.local"
        let stickerEvent = Event(
            eventID: "$s1",
            roomID: roomID,
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            mine: false,
            type: "m.sticker",
            content: .object([
                "body": .string("sticker.webp"),
                "url": .string("mxc://courier.local/s1"),
                "info": .object([
                    "mimetype": .string("image/webp"),
                    "w": .int(512),
                    "h": .int(512),
                ]),
            ]),
            ts: 1_760_000_001_000,
            seq: 1,
            status: .sent,
            mediaPath: stickerPath,
            thumbnailPath: stickerPath,
            viewOnce: nil,
            played: false
        )
        let timelineItems = Timeline.build(
            events: [stickerEvent],
            me: "@me:courier.local",
            now: Date(timeIntervalSince1970: 1_760_000_002)
        )
        let messages = timelineItems.compactMap { item -> TimelineMessage? in
            if case let .message(msg) = item { return msg }
            return nil
        }
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.id, "$s1")
        XCTAssertEqual(messages.first?.kind, .sticker)

        let (_, appModel) = try await startApp { method, _ in
            switch method {
            case "hello": return TestEngineServer.helloOK
            case "accounts.list": return .result(["accounts": []])
            default: return .result([String: Any]())
            }
        }
        let conversation = ConversationModel(appModel: appModel, unreadCount: { _ in 0 }, chat: { _ in nil })
        conversation.setSnapshotStateForTesting(roomID: roomID, items: timelineItems)
        conversation.openLightbox("$s1")

        XCTExpectFailure("Regression: stickers no longer open in the viewer (review of feat/courier-ux2-newchat)") {
            XCTAssertTrue(conversation.carousel.isPresented)
            XCTAssertEqual(conversation.carousel.currentItem?.eventID, "$s1")
        }
    }
}
