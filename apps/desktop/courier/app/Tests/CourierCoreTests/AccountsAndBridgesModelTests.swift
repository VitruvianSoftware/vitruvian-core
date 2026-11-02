// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation
import XCTest

private final class FakeDockTileService: DockTileService, @unchecked Sendable {
    var dockBundles: Set<String> = ["net.whatsapp.WhatsApp", "ru.keepcoder.Telegram"]
    var removedBundles: [String] = []

    func isAppInDock(bundleIdentifier: String) -> Bool {
        dockBundles.contains(bundleIdentifier)
    }

    func removeAppFromDock(bundleIdentifier: String) -> Bool {
        guard dockBundles.remove(bundleIdentifier) != nil else { return false }
        removedBundles.append(bundleIdentifier)
        return true
    }
}

private final class SpyTextPasteboard: TextPasteboard {
    var copiedStrings: [String] = []
    func setString(_ string: String) {
        copiedStrings.append(string)
    }
}

private struct LockedTestLoginItemService: LoginItemService {
    func status() -> LoginItemRegistrationStatus { .notRegistered }
    func register() throws {}
    func unregister() throws {}
}

private struct LockedTestBiometricService: BiometricAuthService {
    func canEvaluateBiometricsOrWatch() -> Bool { true }
    func authenticate(reason _: String) async throws -> Bool { false }
}

@MainActor
final class AccountsAndBridgesModelTests: XCTestCase {
    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
    }

    private func makeConnectedApp(server: TestEngineServer) async throws -> (AppModel, FakeProcess) {
        let socket = server.path
        let launcher = FakeLauncher { _, process in process.printReady(socket: socket) }
        let supervisor = EngineSupervisor(
            enginePath: "/bin/true",
            dataDir: URL(fileURLWithPath: "/tmp"),
            environment: [:],
            launcher: launcher
        )
        let app = AppModel(supervisor: supervisor)
        app.start()
        try await waitUntil { app.client != nil }
        XCTAssertNotNil(app.client)
        return (app, try XCTUnwrap(launcher.processes.first))
    }

    func testRefreshRestartRemoveSubAccountsAndRemoveOfficialAppFromDock() async throws {
        var restartedNetworks: [String] = []
        var removedCalls: [[String: Any]] = []
        var subAccountUpdates: [[String: Any]] = []

        let server = try TestEngineServer { method, params in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.list":
                let logins: [[String: Any]] = removedCalls.isEmpty ? [
                    [
                        "account_id": "tg1",
                        "remote_name": "@alice",
                        "state": "CONNECTED",
                        "error": "",
                    ],
                ] : []
                return .result([
                    "accounts": [
                        [
                            "network": "telegram",
                            "display_name": "Telegram",
                            "flows": ["qr", "phone"],
                            "state": removedCalls.isEmpty ? "CONNECTED" : "UNCONFIGURED",
                            "error": "",
                            "remote_name": removedCalls.isEmpty ? "@alice" : "",
                            "not_started": "",
                            "syncs": [String](),
                            "logins": logins,
                        ],
                    ],
                ])
            case "bridges.list":
                let logins: [[String: Any]] = removedCalls.isEmpty ? [
                    [
                        "account_id": "tg1",
                        "remote_name": "@alice",
                        "state": "CONNECTED",
                        "error": "",
                    ],
                ] : []
                return .result([
                    "bridges": [
                        [
                            "network": "telegram",
                            "display_name": "Telegram",
                            "bridge_id": "telegram",
                            "module_path": "go.mau.fi/mautrix-telegram",
                            "version": "v0.2609.0",
                            "mautrix_version": "v0.31.0",
                            "state": removedCalls.isEmpty ? "CONNECTED" : "UNCONFIGURED",
                            "started_at": 1_700_000_000_000,
                            "accounts": [
                                [
                                    "network": "telegram",
                                    "display_name": "Telegram",
                                    "flows": ["qr", "phone"],
                                    "remote_name": removedCalls.isEmpty ? "@alice" : "",
                                    "not_started": "",
                                    "syncs": [String](),
                                    "state": removedCalls.isEmpty ? "CONNECTED" : "UNCONFIGURED",
                                    "error": "",
                                    "logins": logins,
                                ],
                            ],
                        ],
                    ],
                ])
            case "bridges.restart":
                if let net = params?["network"] as? String {
                    restartedNetworks.append(net)
                }
                return .result([String: Any]())
            case "accounts.remove":
                if let params {
                    removedCalls.append(params)
                }
                return .result([String: Any]())
            case "accounts.subAccounts":
                return .result([
                    "sub_accounts": [
                        [
                            "network": "telegram",
                            "account_id": "tg1",
                            "sub_id": "!folder:courier.local",
                            "title": "Work Folder",
                            "avatar_uri": "",
                            "kind": "space",
                            "enabled": false,
                            "show_in_inbox": "all",
                        ],
                    ],
                ])
            case "accounts.setSubAccount":
                if let params {
                    subAccountUpdates.append(params)
                }
                return .result([String: Any]())
            default:
                return .result([String: Any]())
            }
        }
        defer { server.stop() }

        let (app, process) = try await makeConnectedApp(server: server)
        defer {
            process.exit(0)
            app.supervisor.stop()
        }

        let dock = FakeDockTileService()
        let pasteboard = SpyTextPasteboard()
        let model = AccountsAndBridgesModel(appModel: app, dockTileService: dock, pasteboard: pasteboard)

        await model.refresh()
        XCTAssertEqual(model.bridges.count, 1)
        XCTAssertEqual(model.bridges.first?.version, "v0.2609.0")
        XCTAssertEqual(model.selectedAccountKey, "telegram:tg1")

        let json = try XCTUnwrap(model.bridgeJSON(for: "telegram"))
        XCTAssertTrue(json.contains("mautrix-telegram"))
        XCTAssertTrue(json.contains("v0.2609.0"))

        model.copyAccountID("tg1")
        XCTAssertEqual(pasteboard.copiedStrings.last, "tg1")
        XCTAssertEqual(model.lastToast, "Account ID copied")

        model.copyBridgeID(for: "telegram")
        XCTAssertEqual(pasteboard.copiedStrings.last, "telegram")
        XCTAssertEqual(model.lastToast, "Bridge ID copied")

        model.copyBridgeInfoJSON(for: "telegram")
        XCTAssertTrue(pasteboard.copiedStrings.last?.contains("mautrix-telegram") == true)
        XCTAssertEqual(model.lastToast, "Bridge info copied")

        await model.loadSubAccounts(network: "telegram", accountID: "tg1", forceRefresh: true)
        XCTAssertEqual(model.subAccountsByKey["telegram:tg1"]?.count, 1)
        XCTAssertEqual(model.subAccountsByKey["telegram:tg1"]?.first?.enabled, false)

        await model.updateSubAccount(
            network: "telegram",
            accountID: "tg1",
            subID: "!folder:courier.local",
            enabled: true,
            showInInbox: .dms
        )
        XCTAssertEqual(subAccountUpdates.count, 1)
        XCTAssertEqual(model.subAccountsByKey["telegram:tg1"]?.first?.enabled, true)
        XCTAssertEqual(model.subAccountsByKey["telegram:tg1"]?.first?.showInInbox, .dms)

        await model.restartBridge(network: "telegram")
        XCTAssertEqual(restartedNetworks, ["telegram"])
        XCTAssertEqual(model.lastToast, "Bridge restarted")

        XCTAssertTrue(model.canOfferRemoveFromDock(network: "telegram"))
        XCTAssertTrue(model.removeOfficialAppFromDock(network: "telegram"))
        XCTAssertEqual(dock.removedBundles, ["ru.keepcoder.Telegram"])
        XCTAssertFalse(model.canOfferRemoveFromDock(network: "telegram"))
        XCTAssertFalse(model.canOfferRemoveFromDock(network: "gmessages"))
        XCTAssertFalse(model.removeOfficialAppFromDock(network: "gmessages"))

        await model.removeAccount(network: "telegram", accountID: "tg1", logoutRemote: true, deleteChats: true)
        XCTAssertEqual(removedCalls.count, 1)
        XCTAssertEqual(removedCalls.first?["account_id"] as? String, "tg1")
        XCTAssertEqual(removedCalls.first?["logout_remote"] as? Bool, true)
        XCTAssertEqual(removedCalls.first?["delete_chats"] as? Bool, true)
        XCTAssertNil(model.subAccountsByKey["telegram:tg1"])
        XCTAssertNil(model.selectedAccountKey)
        XCTAssertEqual(model.lastToast, "Account removed")
    }

    func testRemoveAccountConfirmationCancelPathDeletesNothingAndSlackDefaultLogoutRemoteIsFalse() async throws {
        var removedCalls: [[String: Any]] = []
        let server = try TestEngineServer { method, params in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.remove":
                if let params {
                    removedCalls.append(params)
                }
                return .result([String: Any]())
            default:
                return .result([String: Any]())
            }
        }
        defer { server.stop() }

        let (app, process) = try await makeConnectedApp(server: server)
        defer {
            process.exit(0)
            app.supervisor.stop()
        }

        XCTAssertTrue(AccountsAndBridgesModel.defaultLogoutRemote(for: "whatsapp"))
        XCTAssertTrue(AccountsAndBridgesModel.defaultLogoutRemote(for: "signal"))
        XCTAssertTrue(AccountsAndBridgesModel.defaultLogoutRemote(for: "telegram"))
        XCTAssertTrue(AccountsAndBridgesModel.defaultLogoutRemote(for: "gmessages"))
        XCTAssertFalse(AccountsAndBridgesModel.defaultLogoutRemote(for: "slack"))

        let model = AccountsAndBridgesModel(appModel: app, dockTileService: FakeDockTileService())
        model.requestRemoveAccount(network: "slack", accountID: "sl1", remoteName: "Acme Workspace", displayName: "Slack")

        let pending = try XCTUnwrap(model.pendingRemoval)
        XCTAssertEqual(pending.network, "slack")
        XCTAssertEqual(pending.accountID, "sl1")
        XCTAssertFalse(pending.logoutRemote, "Slack must default logoutRemote to false so removing does not revoke browser cookies")
        XCTAssertFalse(pending.deleteChats)
        XCTAssertTrue(pending.message.contains("Acme Workspace"))
        XCTAssertTrue(pending.message.contains("local chats"))

        // Cancel path: must clear pendingRemoval and leave the account untouched (zero accounts.remove calls).
        model.cancelRemoveAccount()
        XCTAssertNil(model.pendingRemoval)
        XCTAssertTrue(removedCalls.isEmpty, "Cancelling Remove Account confirmation must not call accounts.remove")

        // Confirm path with WhatsApp (defaults logoutRemote == true).
        model.requestRemoveAccount(network: "whatsapp", accountID: "wa1", remoteName: "+1 555 0101", displayName: "WhatsApp")
        XCTAssertEqual(model.pendingRemoval?.logoutRemote, true)
        model.pendingRemoval?.deleteChats = true
        await model.confirmRemoveAccount()
        XCTAssertNil(model.pendingRemoval)
        XCTAssertEqual(removedCalls.count, 1)
        XCTAssertEqual(removedCalls.first?["network"] as? String, "whatsapp")
        XCTAssertEqual(removedCalls.first?["account_id"] as? String, "wa1")
        XCTAssertEqual(removedCalls.first?["logout_remote"] as? Bool, true)
        XCTAssertEqual(removedCalls.first?["delete_chats"] as? Bool, true)
    }

    func testMutationsAreRefusedWhileAppIsLocked() async throws {
        var rpcMethods: [String] = []
        let server = try TestEngineServer { method, _ in
            if method == "hello" { return TestEngineServer.helloOK }
            rpcMethods.append(method)
            return .result([String: Any]())
        }
        defer { server.stop() }

        let (app, process) = try await makeConnectedApp(server: server)
        defer {
            process.exit(0)
            app.supervisor.stop()
        }

        let suiteName = "courier.accounts.lock.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: LockedTestLoginItemService(),
            biometrics: LockedTestBiometricService()
        )
        let dock = FakeDockTileService()
        let model = AccountsAndBridgesModel(appModel: app, dockTileService: dock, lifecycle: lifecycle)

        model.requestRemoveAccount(network: "whatsapp", accountID: "wa1", remoteName: "+1 555 0101")
        model.requestRestartBridge(network: "whatsapp")
        XCTAssertNotNil(model.pendingRemoval)
        XCTAssertNotNil(model.pendingRestartNetwork)

        rpcMethods.removeAll()
        lifecycle.lockApp()
        XCTAssertTrue(lifecycle.isLocked)
        XCTAssertNil(model.pendingRemoval, "Locking must dismiss pending Remove Account confirmation")
        XCTAssertNil(model.pendingRestartNetwork, "Locking must dismiss pending Restart Bridge confirmation")

        await model.restartBridge(network: "whatsapp")
        await model.removeAccount(network: "whatsapp", accountID: "wa1", logoutRemote: true, deleteChats: true)
        await model.loadSubAccounts(network: "telegram", accountID: "tg1", forceRefresh: true)
        await model.updateSubAccount(network: "telegram", accountID: "tg1", subID: "!f:courier.local", enabled: true)
        model.requestRemoveAccount(network: "whatsapp", accountID: "wa1")
        model.requestRestartBridge(network: "whatsapp")
        XCTAssertFalse(model.removeOfficialAppFromDock(network: "whatsapp"))

        XCTAssertNil(model.pendingRemoval)
        XCTAssertNil(model.pendingRestartNetwork)
        XCTAssertTrue(dock.removedBundles.isEmpty)
        XCTAssertTrue(rpcMethods.isEmpty, "Locked app must refuse all AccountsAndBridgesModel RPC mutations")
    }

    func testPlainEnglishStatusLabelsAndSubAccountsAcrossNetworks() async throws {
        var listedNetworks: [String] = []
        let server = try TestEngineServer { method, params in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.subAccounts":
                let network = (params?["network"] as? String) ?? ""
                let accountID = (params?["account_id"] as? String) ?? ""
                listedNetworks.append("\(network):\(accountID)")
                return .result([
                    "sub_accounts": [
                        [
                            "network": network,
                            "account_id": accountID,
                            "sub_id": "sub-\(network)-1",
                            "title": "\(network.capitalized) Space",
                            "avatar_uri": "",
                            "kind": "space",
                            "enabled": true,
                            "show_in_inbox": "all",
                        ],
                    ],
                ])
            case "accounts.setSubAccount":
                return .result([String: Any]())
            default:
                return .result([String: Any]())
            }
        }
        defer { server.stop() }

        let (app, process) = try await makeConnectedApp(server: server)
        defer {
            process.exit(0)
            app.supervisor.stop()
        }

        let model = AccountsAndBridgesModel(appModel: app, dockTileService: FakeDockTileService())
        await model.loadSubAccounts(network: "slack", accountID: "T1-U1", forceRefresh: false)
        XCTAssertEqual(listedNetworks, ["slack:T1-U1"])
        XCTAssertEqual(model.subAccountsByKey["slack:T1-U1"]?.first?.title, "Slack Space")
        await model.updateSubAccount(
            network: "slack",
            accountID: "T1-U1",
            subID: "sub-slack-1",
            enabled: false,
            showInInbox: .dms
        )
        XCTAssertEqual(model.subAccountsByKey["slack:T1-U1"]?.first?.enabled, false)
        XCTAssertEqual(model.subAccountsByKey["slack:T1-U1"]?.first?.showInInbox, .dms)

        let rawStates: [AccountState] = [
            .connected,
            .connecting,
            .backfilling,
            .transientDisconnect,
            .badCredentials,
            .loggedOut,
            .unknownError,
            .unconfigured,
            .notStarted,
        ]
        for state in rawStates {
            let label = AccountsAndBridgesModel.statusLabel(for: state)
            XCTAssertFalse(label.isEmpty)
            XCTAssertNotEqual(label, state.rawValue, "Status label must be plain English, never raw state code \(state.rawValue)")
            XCTAssertFalse(label.contains("_"), "Status label must not contain raw underscore code: \(label)")
        }
        XCTAssertEqual(AccountsAndBridgesModel.statusLabel(for: .connected), "Connected")
        XCTAssertEqual(AccountsAndBridgesModel.statusLabel(for: .badCredentials), "Signed out — reconnect")
        XCTAssertEqual(AccountsAndBridgesModel.statusLabel(for: .transientDisconnect), "Reconnecting…")
        XCTAssertEqual(AccountsAndBridgesModel.statusLabel(for: .notStarted), "Not started")
        XCTAssertEqual(AccountsAndBridgesModel.statusLabel(for: "STOPPED"), "Not started")
    }

    func testFailedRemoveAccountRestartBridgeAndSubAccountToggleProducePlainEnglishErrors() async throws {
        var allErrors: [EngineError] = [
            .protocolMismatch(engine: 8),
            .notConnected,
            .disconnected,
            .frameTooLarge,
            .badResponse,
            .timedOut,
            .appLocked,
        ]
        for entry in RPCErrorCode.known {
            allErrors.append(.rpc(entry.code, message: "wire log message", reason: nil))
        }
        allErrors.append(.rpc(.other(-32099), message: "unknown wire error", reason: nil))

        for err in allErrors {
            let text = err.localizedDescription
            XCTAssertFalse(text.isEmpty, "EngineError \(err) must have a non-empty localizedDescription")
            XCTAssertFalse(
                text.contains("CourierCore.EngineError"),
                "EngineError \(err) localizedDescription must be plain English, got: \(text)"
            )
            XCTAssertFalse(
                text.contains("The operation couldn"),
                "EngineError \(err) must conform to LocalizedError, got: \(text)"
            )
        }

        let server = try TestEngineServer { method, _ in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "accounts.remove":
                return .error(code: -32020, message: "no such chat or label")
            case "bridges.restart":
                return .error(code: -32016, message: "this network isn't running")
            case "accounts.setSubAccount":
                return .error(code: -32014, message: "invalid sub-account value")
            default:
                return .result([String: Any]())
            }
        }
        defer { server.stop() }

        let (app, process) = try await makeConnectedApp(server: server)
        defer {
            process.exit(0)
            app.supervisor.stop()
        }

        let model = AccountsAndBridgesModel(appModel: app, dockTileService: FakeDockTileService())

        await model.removeAccount(network: "telegram", accountID: "tg-missing", logoutRemote: false, deleteChats: false)
        let removeError: String = try XCTUnwrap(model.lastError)
        XCTAssertFalse(removeError.contains("CourierCore.EngineError"), "Failed Remove Account must show plain English: \(removeError)")
        XCTAssertEqual(removeError, "That account or chat is no longer there.")

        await model.restartBridge(network: "telegram")
        let restartError: String = try XCTUnwrap(model.lastError)
        XCTAssertFalse(restartError.contains("CourierCore.EngineError"), "Failed Restart Bridge must show plain English: \(restartError)")
        XCTAssertEqual(restartError, "This network isn’t running.")

        await model.updateSubAccount(network: "telegram", accountID: "tg1", subID: "!folder:courier.local", enabled: true)
        let subAccountError: String = try XCTUnwrap(model.lastError)
        XCTAssertFalse(subAccountError.contains("CourierCore.EngineError"), "Failed sub-account toggle must show plain English: \(subAccountError)")
        XCTAssertEqual(subAccountError, "That isn’t accepted. Check it and try again.")
    }
    /// A failure to read the bridges (an engine restarting, say) goes once a read works: it doesn't stay in red.
    func testASuccessfulRefreshClearsAnEarlierReadError() async throws {
        final class Failing: @unchecked Sendable {
            let lock = NSLock()
            var on = true
        }
        let failing = Failing()
        let server = try TestEngineServer { method, _ in
            switch method {
            case "hello":
                return TestEngineServer.helloOK
            case "bridges.list":
                if failing.lock.withLock({ failing.on }) {
                    return .error(code: -32016, message: "this network isn't running")
                }
                return .result(["bridges": [[String: Any]]()])
            default:
                return .result([String: Any]())
            }
        }
        defer { server.stop() }
        let (app, process) = try await makeConnectedApp(server: server)
        defer {
            process.exit(0)
            app.supervisor.stop()
        }
        let model = AccountsAndBridgesModel(appModel: app, dockTileService: FakeDockTileService())

        await model.refresh()
        XCTAssertNotNil(model.lastError, "the failed read shows")
        failing.lock.withLock { failing.on = false }
        await model.refresh()
        XCTAssertNil(model.lastError, "and goes once a read works")
    }
}

