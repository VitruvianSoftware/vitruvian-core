// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation
import XCTest

private struct LockedStorageLoginItemService: LoginItemService {
    func status() -> LoginItemRegistrationStatus { .notRegistered }
    func register() throws {}
    func unregister() throws {}
}

private struct LockedStorageBiometricService: BiometricAuthService {
    func canEvaluateBiometricsOrWatch() -> Bool { true }
    func authenticate(reason _: String) async throws -> Bool { false }
}

@MainActor
final class StorageModelTests: XCTestCase {
    override func setUp() {
        AppLockGate.shared.resetForTesting()
    }

    override func tearDown() {
        AppLockGate.shared.resetForTesting()
    }

    private func makeConnectedApp(server: TestEngineServer, lifecycle: SystemLifecycleModel? = nil) async throws -> AppModel {
        let socket = server.path
        let launcher = FakeLauncher { _, process in process.printReady(socket: socket) }
        let supervisor = EngineSupervisor(
            enginePath: "/bin/true",
            dataDir: URL(fileURLWithPath: "/tmp"),
            environment: [:],
            launcher: launcher
        )
        let app = AppModel(supervisor: supervisor, lifecycle: lifecycle)
        app.start()
        try await waitUntil { app.client != nil }
        return app
    }

    func testRefreshLoadsStorageUsageAndFiltersRoomsByQuery() async throws {
        let server = try TestEngineServer { method, _ in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.list":
                return .result(["accounts": [[String: Any]]()])
            case "storage.usage":
                return .result([
                    "total_bytes": 152_400_000,
                    "database_bytes": 12_400_000,
                    "photos_and_videos_bytes": 96_000_000,
                    "audio_bytes": 14_000_000,
                    "files_bytes": 22_000_000,
                    "stickers_bytes": 5_000_000,
                    "other_media_bytes": 3_000_000,
                    "rooms": [
                        [
                            "room_id": "!wa:design",
                            "name": "Design System Sync",
                            "network": "whatsapp",
                            "media_bytes": 84_000_000,
                            "item_count": 42,
                        ],
                        [
                            "room_id": "!sig:alice",
                            "name": "Alice Nguyen",
                            "network": "signal",
                            "media_bytes": 36_000_000,
                            "item_count": 18,
                        ],
                        [
                            "room_id": "!tg:rust",
                            "name": "Rust Bridges",
                            "network": "telegram",
                            "media_bytes": 20_000_000,
                            "item_count": 9,
                        ],
                    ],
                ])
            default:
                return .result([String: Any]())
            }
        }
        defer { server.stop() }

        let app = try await makeConnectedApp(server: server)
        defer { supervisorStop(app) }

        let model = StorageModel(appModel: app)
        await model.refresh()

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.lastErrorMessage)
        let usage = try XCTUnwrap(model.usage)
        XCTAssertEqual(usage.totalBytes, 152_400_000)
        XCTAssertEqual(usage.databaseBytes, 12_400_000)
        XCTAssertEqual(usage.photosAndVideosBytes, 96_000_000)
        XCTAssertEqual(usage.audioBytes, 14_000_000)
        XCTAssertEqual(usage.filesBytes, 22_000_000)
        XCTAssertEqual(usage.stickersBytes, 5_000_000)
        XCTAssertEqual(usage.otherMediaBytes, 3_000_000)
        XCTAssertEqual(usage.rooms.count, 3)
        XCTAssertEqual(model.filteredRooms.map(\.roomID), ["!wa:design", "!sig:alice", "!tg:rust"])

        // Filter by chat name (case-insensitive)
        model.roomFilterQuery = "alice"
        XCTAssertEqual(model.filteredRooms.map(\.roomID), ["!sig:alice"])

        // Filter by network name (case-insensitive)
        model.roomFilterQuery = "TELEGRAM"
        XCTAssertEqual(model.filteredRooms.map(\.roomID), ["!tg:rust"])

        model.roomFilterQuery = ""
        XCTAssertEqual(model.filteredRooms.count, 3)
    }

    func testClearMediaByAgeAndByRoomCallsStorageCleanupAndRefreshes() async throws {
        var cleanupCalls: [[String: Any]] = []
        var usageCallCount = 0

        let server = try TestEngineServer { method, params in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.list":
                return .result(["accounts": [[String: Any]]()])
            case "storage.usage":
                usageCallCount += 1
                return .result([
                    "total_bytes": 50_000_000,
                    "database_bytes": 10_000_000,
                    "photos_and_videos_bytes": 30_000_000,
                    "audio_bytes": 5_000_000,
                    "files_bytes": 3_000_000,
                    "stickers_bytes": 1_000_000,
                    "other_media_bytes": 1_000_000,
                    "rooms": [
                        [
                            "room_id": "!wa:1",
                            "name": "Project Launch",
                            "network": "whatsapp",
                            "media_bytes": 30_000_000,
                            "item_count": 15,
                        ],
                    ],
                ])
            case "storage.cleanup":
                cleanupCalls.append(params ?? [:])
                return .result([
                    "freed_bytes": 14_889_779,
                    "removed_blobs": 12,
                ])
            default:
                return .result([String: Any]())
            }
        }
        defer { server.stop() }

        let app = try await makeConnectedApp(server: server)
        defer { supervisorStop(app) }

        let model = StorageModel(appModel: app)
        await model.clearMedia(olderThan: .oneMonth)

        XCTAssertEqual(cleanupCalls.count, 1)
        XCTAssertEqual(cleanupCalls.first?["older_than_ms"] as? Int64, Int64(30) * 86_400_000)
        XCTAssertNil(cleanupCalls.first?["room_ids"])
        XCTAssertEqual(usageCallCount, 1, "clearMedia(olderThan:) should automatically refresh storage.usage")
        XCTAssertNotNil(model.lastStatusMessage)
        XCTAssertTrue(model.lastStatusMessage?.contains("Cleared") == true)

        await model.clearMedia(forRoomID: "!wa:1")
        XCTAssertEqual(cleanupCalls.count, 2)
        XCTAssertEqual(cleanupCalls[1]["room_ids"] as? [String], ["!wa:1"])
        XCTAssertEqual(usageCallCount, 2, "clearMedia(forRoomID:) should automatically refresh storage.usage")

        await model.clearAllCache()
        XCTAssertEqual(cleanupCalls.count, 3)
        XCTAssertEqual(cleanupCalls[2]["include_stickers"] as? Bool, true)
        XCTAssertEqual(usageCallCount, 3, "clearAllCache() should automatically refresh storage.usage")
    }

    func testStorageActionsAreRefusedWhileAppLocked() async throws {
        var storageRPCMethods: [String] = []
        let server = try TestEngineServer { method, _ in
            if method.hasPrefix("storage.") {
                storageRPCMethods.append(method)
            }
            if method == "hello" { return TestEngineServer.helloOK }
            return .result([String: Any]())
        }
        defer { server.stop() }

        let suiteName = "courier.storage.locked.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let lifecycle = SystemLifecycleModel(
            loginItemService: LockedStorageLoginItemService(),
            biometricService: LockedStorageBiometricService(),
            defaults: defaults
        )
        lifecycle.lockApp()
        XCTAssertTrue(lifecycle.isLocked)

        let app = try await makeConnectedApp(server: server, lifecycle: lifecycle)
        defer { supervisorStop(app) }

        let model = StorageModel(appModel: app)
        await model.refresh()
        await model.clearMedia(olderThan: .oneWeek)
        await model.clearMedia(forRoomID: "!wa:1")
        await model.clearAllCache()

        XCTAssertTrue(storageRPCMethods.isEmpty, "No storage.* RPC may be sent while Courier is locked")
        XCTAssertNil(model.usage)
    }

    private func supervisorStop(_ app: AppModel) {
        app.supervisor.stop()
    }
}
