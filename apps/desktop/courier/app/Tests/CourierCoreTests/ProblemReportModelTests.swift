// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest

@testable import CourierCore

@MainActor
final class ProblemReportModelTests: XCTestCase {
    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
    }

    private func makeConnectedApp(
        server: TestEngineServer,
        stderrLines: [String] = []
    ) async throws -> (EngineSupervisor, AppModel) {
        let socket = server.path
        let launcher = FakeLauncher { _, process in
            for line in stderrLines {
                process.printError(line)
            }
            process.printReady(socket: socket)
        }
        let supervisor = EngineSupervisor(
            enginePath: "/bin/true",
            dataDir: URL(fileURLWithPath: "/tmp"),
            environment: [:],
            launcher: launcher
        )
        let app = AppModel(supervisor: supervisor)
        app.start()
        try await waitUntil { app.client != nil }
        return (supervisor, app)
    }

    func testLoadDiagnosticsWithIncludeMessageDetailsOffVsOn() async throws {
        let rawStderr = [
            #"{"level":"warn","bridge":"whatsapp","pn":"+15550100101","token":"xoxc-123-456","time":"2026-10-25T12:00:00Z","message":"syncing +15550100101 with xoxc-123-456 for \"Alice Example\""}"#,
            "arbitrary third-party stderr line with +15550100101 and /Users/alice/secret",
            "courier-engine: open /Users/alice/Library/Application Support/Courier/courier.db: permission denied (token xoxc-123-456, phone +15550100101)",
            #"panic: failed to parse "+15550100101: Alice Example" with token xoxc-123-456"#,
            "goroutine 42 [running]:",
            "maunium.net/go/mautrix/bridgev2.(*Portal).handleRemoteEvent(0x1400012a000, {0x104c92a00, 0x14000180000})",
            "\t/Users/alice/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/bridgev2/portal.go:2690 +0x1c4",
        ]

        var exportCalls: [[String: Any]] = []
        let server = try TestEngineServer { method, params in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.list":
                return .result(["accounts": [[String: Any]]()])
            case "diagnostics.export":
                if let dict = params {
                    exportCalls.append(dict)
                }
                let dict = params
                let roomID = dict?["room_id"] as? String
                let eventID = dict?["event_id"] as? String
                var res: [String: Any] = [
                    "protocol_version": CourierProtocol.version,
                    "schema_version": 10,
                    "go_version": "go1.23.2",
                    "bridges": [
                        [
                            "network": "whatsapp",
                            "display_name": "WhatsApp",
                            "bridge_id": "whatsapp",
                            "module_path": "go.mau.fi/mautrix-whatsapp",
                            "version": "v0.2609.0",
                            "mautrix_version": "v0.31.0",
                            "state": "CONNECTED",
                            "error": "failed for /Users/alice and +15550100101 with xoxc-123-456",
                            "started_at": 1_761_393_600_000,
                            "accounts": [
                                [
                                    "network": "whatsapp",
                                    "display_name": "WhatsApp",
                                    "flows": ["qr"],
                                    "state": "CONNECTED",
                                    "error": "",
                                    "remote_name": "Alice Example (+15550100101)",
                                    "not_started": "",
                                    "syncs": ["messages"],
                                    "logins": [
                                        [
                                            "account_id": "wa-1",
                                            "remote_name": "Alice Example (+15550100101)",
                                            "state": "CONNECTED",
                                            "error": "",
                                        ],
                                    ],
                                ],
                            ],
                        ],
                    ],
                    "scrubbed_stderr": [
                        #"{"level":"error","bridge":"whatsapp","time":"2026-10-25T12:00:00Z","message":"bridge disconnected [id]"}"#,
                    ],
                ]
                if let roomID {
                    res["room_details"] = [
                        "room_id": roomID,
                        "network": "whatsapp",
                        "is_direct": true,
                    ]
                }
                if let eventID {
                    res["message_details"] = [
                        "event_id": eventID,
                        "room_id": roomID ?? "!r1:courier.local",
                        "network": "whatsapp",
                        "type": "m.room.message",
                        "ts": 1_761_393_600_000,
                        "status": "failed",
                        "status_reason": "[id] not reachable",
                        "has_media": false,
                        "is_redacted": false,
                    ]
                }
                return .result(res)
            default:
                return TestEngineServer.standard(method, params)
            }
        }
        defer { server.stop() }

        let (supervisor, app) = try await makeConnectedApp(server: server, stderrLines: rawStderr)
        defer { supervisor.stop() }

        let model = ProblemReportModel(
            appModel: app,
            contextRoomID: "!r1:courier.local",
            contextEventID: "$ev1"
        )
        XCTAssertFalse(model.includeMessageDetails)

        // 1. includeMessageDetails == false -> room_id and event_id are omitted
        await model.loadDiagnostics()
        let firstCall = try XCTUnwrap(exportCalls.first)
        XCTAssertNil(firstCall["room_id"])
        XCTAssertNil(firstCall["event_id"])
        XCTAssertNil(model.diagnostics?.roomDetails)
        XCTAssertNil(model.diagnostics?.messageDetails)

        // Supervisor lines must be scrubbed by Ruling 10
        let joinedSupervisor = model.scrubbedSupervisorLines.joined(separator: "\n")
        XCTAssertTrue(joinedSupervisor.contains("panic: [redacted]"))
        XCTAssertTrue(joinedSupervisor.contains("maunium.net/go/mautrix/bridgev2.(*Portal).handleRemoteEvent(...)"))
        XCTAssertTrue(joinedSupervisor.contains("\tmaunium.net/go/mautrix@v0.31.0/bridgev2/portal.go:2690 +0x1c4"))
        for forbidden in ["+15550100101", "15550100101", "xoxc-123-456", "/Users/alice", "Alice Example", "arbitrary third-party"] {
            XCTAssertFalse(joinedSupervisor.contains(forbidden), "Supervisor log leaked \(forbidden)")
        }

        // 2. includeMessageDetails == true -> room_id and event_id are sent
        model.includeMessageDetails = true
        await model.loadDiagnostics()
        let secondCall = try XCTUnwrap(exportCalls.last)
        XCTAssertEqual(secondCall["room_id"] as? String, "!r1:courier.local")
        XCTAssertEqual(secondCall["event_id"] as? String, "$ev1")
        XCTAssertEqual(model.diagnostics?.roomDetails?.roomID, "!r1:courier.local")
        XCTAssertEqual(model.diagnostics?.messageDetails?.eventID, "$ev1")
    }

    func testWriteBundleScrubsSecretsHomePathsPhonesAndNamesAndRefusesWhenLocked() async throws {
        let rawStderr = [
            #"{"level":"warn","bridge":"slack","time":"2026-10-25T12:00:00Z","message":"auth failed for \"Alice Example\" (+15550100101) token xoxc-123-456"}"#,
            "courier-engine: cannot open /Users/alice/Library/Application Support/Courier/courier.db for +15550100101",
            #"panic: token xoxc-123-456 for "Alice Example" at /Users/alice/secret (+15550100101)"#,
            "goroutine 7 [running]:",
            "github.com/VitruvianSoftware/courier/engine/internal/host.(*Host).Start(0x1400012a000)",
            "\t/Users/alice/Workspace/vitruvian-core/apps/desktop/courier/engine/internal/host/host.go:200 +0x88",
        ]

        let server = try TestEngineServer { method, params in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.list":
                return .result(["accounts": [[String: Any]]()])
            case "diagnostics.export":
                return .result([
                    "protocol_version": CourierProtocol.version,
                    "schema_version": 10,
                    "go_version": "go1.23.2",
                    "bridges": [
                        [
                            "network": "slack",
                            "display_name": "Slack",
                            "bridge_id": "slack",
                            "module_path": "go.mau.fi/mautrix-slack",
                            "version": "v0.2609.1",
                            "mautrix_version": "v0.31.0",
                            "state": "ERROR",
                            "error": "token xoxc-123-456 rejected at /Users/alice/Library/Courier for \"Alice Example\" +15550100101",
                            "started_at": 1_761_393_600_000,
                            "accounts": [
                                [
                                    "network": "slack",
                                    "display_name": "Slack",
                                    "flows": ["cookies"],
                                    "state": "ERROR",
                                    "error": "token xoxc-123-456 rejected",
                                    "remote_name": "Alice Example (+15550100101)",
                                    "not_started": "",
                                    "syncs": ["messages"],
                                    "logins": [
                                        [
                                            "account_id": "T0123ABCD-U0123ABCD",
                                            "remote_name": "Alice Example (+15550100101)",
                                            "state": "ERROR",
                                            "error": "",
                                        ],
                                    ],
                                ],
                            ],
                        ],
                    ],
                    "scrubbed_stderr": [
                        #"{"level":"error","bridge":"slack","time":"2026-10-25T12:00:00Z","message":"token [id] rejected"}"#,
                    ],
                ])
            default:
                return TestEngineServer.standard(method, params)
            }
        }
        defer { server.stop() }

        let (supervisor, app) = try await makeConnectedApp(server: server, stderrLines: rawStderr)
        defer { supervisor.stop() }

        let model = ProblemReportModel(
            appModel: app,
            contextRoomID: "!r1:courier.local",
            contextEventID: "$ev1"
        )
        model.descriptionText = "Crash when messaging \"Alice Example\" at +15550100101 from /Users/alice/Library/Application Support/Courier with token xoxc-123-456"
        await model.loadDiagnostics()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-problem-report-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try model.writeBundle(to: tempDir)

        let reportJSON = try String(contentsOf: tempDir.appendingPathComponent("report.json"), encoding: .utf8)
        let bridgesJSON = try String(contentsOf: tempDir.appendingPathComponent("bridges.json"), encoding: .utf8)
        let stderrLog = try String(contentsOf: tempDir.appendingPathComponent("stderr-scrubbed.log"), encoding: .utf8)

        let combined = [reportJSON, bridgesJSON, stderrLog].joined(separator: "\n")
        for forbidden in [
            "xoxc-123-456",
            "/Users/alice",
            "alice",
            "+15550100101",
            "15550100101",
            "Alice Example",
            "0x1400012a000",
        ] {
            XCTAssertFalse(combined.contains(forbidden), "Bundle leaked forbidden text: \(forbidden)")
        }
        XCTAssertTrue(stderrLog.contains("panic: [redacted]"))
        XCTAssertTrue(stderrLog.contains("github.com/VitruvianSoftware/courier/engine/internal/host/host.go:200 +0x88"))

        // Refused while locked
        let lifecycle = SystemLifecycleModel(defaults: UserDefaults(suiteName: "test.problemreport.lock.\(UUID().uuidString)")!)
        lifecycle.requireTouchIDOnLaunch = true
        lifecycle.lockNow()
        XCTAssertThrowsError(try model.writeBundle(to: tempDir.appendingPathComponent("locked"))) { error in
            XCTAssertEqual(error as? EngineError, .appLocked)
        }
    }
}
