// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest

@testable import CourierCore

@MainActor
final class MediaViewerModelTests: XCTestCase {
    private var tempDir: URL!
    private var servers: [TestEngineServer] = []
    private var apps: [AppModel] = []

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-mediaviewer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for app in apps { await app.stop() }
        apps.removeAll()
        for server in servers { server.stop() }
        servers.removeAll()
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
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
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"),
            environment: [:],
            launcher: launcher,
            credentials: InMemoryCredentialStore(),
            clientName: "Courier/test",
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

        // 2. MediaViewerModel must exclude view-once media hits.
        let (_, appModel) = try await startApp { method, _ in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.list":
                return .result(["accounts": []])
            case "search.query":
                let hits: [[String: Any]] = [
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
                        "snippet": "View-once secret",
                        "ranges": [],
                        "media_path": viewOncePath,
                        "partial": false,
                        "view_once": true,
                    ],
                    [
                        "event_id": "$vo-2",
                        "room_id": "!dm:courier.local",
                        "room_name": "Alice Example",
                        "network": "whatsapp",
                        "is_direct": true,
                        "place": "inbox",
                        "sender": "@alice:courier.local",
                        "sender_name": "Alice Example",
                        "mine": false,
                        "ts": 1_760_000_003_000,
                        "seq": 3,
                        "kind": "image",
                        "snippet": "Timeline view-once",
                        "ranges": [],
                        "media_path": viewOncePath,
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

        let viewer = MediaViewerModel(
            appModel: appModel,
            roomID: "!dm:courier.local",
            knownViewOnceEventIDs: ["$vo-2"]
        )
        await viewer.refresh()
        XCTAssertEqual(viewer.items.map(\.eventID), ["$normal-1"], "View-once items must never appear in MediaViewerModel")
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
}
