// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import RemoteMenuCore
import RemoteToolCore
import VitruvianToolKit
import VitruvianToolProtocol
import XCTest

final class RemoteToolTests: XCTestCase {
    private func treeContains(_ tree: UITree, _ substring: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(tree),
              let str = String(data: data, encoding: .utf8)
        else { return false }
        return str.contains(substring)
    }

    private func treeFrom(_ answer: PanelAnswer) -> UITree? {
        switch answer {
        case .page(let tree):
            return tree
        default:
            return nil
        }
    }

    func testStatusMarkCoversAllStates() {
        let tmp = URL(fileURLWithPath: "/tmp/remote-status-test")
        let profile = RemoteProfile.extension(dataFolder: tmp, toolFolder: tmp, home: tmp)

        var state = RemotePages.State(profile: profile, role: .quietChosen)
        XCTAssertEqual(RemotePages.statusMark(for: state).state, .none)

        state.role = .quietAsking
        XCTAssertEqual(RemotePages.statusMark(for: state).state, .attention)

        state.role = .activeAlone
        state.snapshot = StatusSnapshot(state: .down)
        XCTAssertEqual(RemotePages.statusMark(for: state).state, .failure)

        state.snapshot = StatusSnapshot(
            state: .running(version: "0.1.3"),
            health: AgentHealth(ok: true, agentVersion: "0.1.3", paired: false),
            tailnetReachable: false
        )
        XCTAssertEqual(RemotePages.statusMark(for: state).state, .failure)

        state.snapshot.tailnetReachable = true
        XCTAssertEqual(RemotePages.statusMark(for: state).state, .attention)
        XCTAssertEqual(RemotePages.statusMark(for: state).text, "No phone paired")

        state.snapshot.health?.paired = true
        state.snapshot.phone = PhoneLink(connected: true, device: .init(model: "Pixel Fold"), tools: ["sms.list"])
        let connectedMark = RemotePages.statusMark(for: state)
        XCTAssertEqual(connectedMark.state, .ok)
        XCTAssertTrue(connectedMark.text.contains("Pixel Fold"))
    }

    func testActiveExtensionSettingsRoundTripAndQRPairing() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("remote-tool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dataDir = tmp.appendingPathComponent("Library/Application Support/Vitruvian/ToolData/dev.vitruvian.remote", isDirectory: true)
        let toolDir = tmp.appendingPathComponent("Library/Application Support/Vitruvian/Tools/dev.vitruvian.remote", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: toolDir.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let progPath = toolDir.appendingPathComponent("bin/tool").path
        FileManager.default.createFile(atPath: progPath, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])

        let controller = RemoteToolController.fromEnvironment(
            env: [
                "REMOTETOOL_HOME": tmp.path,
                "REMOTETOOL_DATA_FOLDER": dataDir.path,
                "REMOTETOOL_TOOL_FOLDER": toolDir.path,
                "REMOTETOOL_AGENT_COMMAND": "",
                "REMOTETOOL_FAKE_STATUS": "paired",
                "REMOTETOOL_TAILSCALE_ADDRESS": "100.124.228.116",
                "REMOTETOOL_STANDALONE_INSTALLED": "0",
            ],
            programPath: progPath
        )
        defer { controller.stop() }

        controller.start(programPath: progPath)
        XCTAssertEqual(RemotePages.statusMark(for: controller.currentState()).state, .ok)

        // Open island and start QR pairing.
        let island = controller.islandPage()
        XCTAssertTrue(treeContains(island, "Pixel Fold"))

        let qrTree = try XCTUnwrap(treeFrom(controller.handleIslandEvent(
            PanelEvent(block: RemotePages.Block.islandPairWithQR, kind: .tap)
        )))
        XCTAssertTrue(treeContains(qrTree, "data:image/png;base64,"))
        XCTAssertTrue(treeContains(qrTree, "http://100.124.228.116:7411/pair?code="))
        XCTAssertTrue(FileManager.default.fileExists(atPath: controller.profile.pairJSONURL.path))

        // Open settings and exercise all 4 tabs + persistence.
        let generalTree = controller.settingsPage()
        XCTAssertTrue(treeContains(generalTree, "Agent & Network"))

        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.intervalSeconds, kind: .submit, value: .string("5"))
        )

        // Pairing tab + permission hook toggle.
        let pairingTab = try XCTUnwrap(treeFrom(controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.tabPairing, kind: .tap)
        )))
        XCTAssertTrue(treeContains(pairingTab, "Phone MCP Bridge"))

        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.permissionHookToggle, kind: .toggle, value: .bool(true))
        )
        XCTAssertTrue(controller.supervisor.isPermissionHookInstalled())

        // Notifications tab: configure ntfy URL, topic, and secret token.
        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.tabNotifications, kind: .tap)
        )
        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.ntfyURL, kind: .submit, value: .string("https://ntfy.example.com"))
        )
        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.ntfyTopic, kind: .submit, value: .string("vitruvian-alerts"))
        )
        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.ntfyTokenField, kind: .submit, value: .string("tk_secret_123"))
        )

        // Integrations tab: configure kubeContext, prometheusURL, prometheusToken, ghExtraRepos.
        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.tabIntegrations, kind: .tap)
        )
        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.kubeContext, kind: .submit, value: .string("homelab-k3s"))
        )
        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.prometheusURL, kind: .submit, value: .string("https://prom.example.com"))
        )
        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.prometheusTokenField, kind: .submit, value: .string("prom_secret_456"))
        )
        _ = controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.ghExtraRepos, kind: .submit, value: .string("VitruvianSoftware/vitruvian-core"))
        )

        let store = RemoteSettingsStore(profile: controller.profile)
        let saved = store.load()
        XCTAssertEqual(saved.intervalSeconds, 5)
        XCTAssertEqual(saved.ntfyURL, "https://ntfy.example.com")
        XCTAssertEqual(saved.ntfyTopic, "vitruvian-alerts")
        XCTAssertEqual(saved.kubeContext, "homelab-k3s")
        XCTAssertEqual(saved.prometheusURL, "https://prom.example.com")
        XCTAssertEqual(saved.ghExtraRepos, "VitruvianSoftware/vitruvian-core")
        XCTAssertTrue(store.hasNtfyToken)
        XCTAssertTrue(store.hasPrometheusToken)
    }

    func testCoexistenceFlowCopiesStandaloneDataAndSwitchesSides() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("remote-both-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let appProfile = RemoteProfile.app(home: tmp)
        try FileManager.default.createDirectory(at: appProfile.configDirURL, withIntermediateDirectories: true)
        try Data("standalone-bearer-token\n".utf8).write(to: appProfile.configDirURL.appendingPathComponent("token"))
        try Data("2026-10-15T12:00:00Z\n".utf8).write(to: appProfile.configDirURL.appendingPathComponent("paired"))
        var appSettings = RemoteSettings()
        appSettings.ntfyURL = "https://ntfy.sh"
        appSettings.ntfyTopic = "from-standalone"
        try RemoteSettingsStore(profile: appProfile).save(appSettings)

        let dataDir = tmp.appendingPathComponent("Library/Application Support/Vitruvian/ToolData/dev.vitruvian.remote", isDirectory: true)
        let toolDir = tmp.appendingPathComponent("Library/Application Support/Vitruvian/Tools/dev.vitruvian.remote", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: toolDir.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let progPath = toolDir.appendingPathComponent("bin/tool").path
        FileManager.default.createFile(atPath: progPath, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])

        let controller = RemoteToolController.fromEnvironment(
            env: [
                "REMOTETOOL_HOME": tmp.path,
                "REMOTETOOL_DATA_FOLDER": dataDir.path,
                "REMOTETOOL_TOOL_FOLDER": toolDir.path,
                "REMOTETOOL_AGENT_COMMAND": "",
                "REMOTETOOL_FAKE_STATUS": "paired",
                "REMOTETOOL_TAILSCALE_ADDRESS": "100.124.228.116",
                "REMOTETOOL_STANDALONE_INSTALLED": "1",
            ],
            programPath: progPath
        )
        defer { controller.stop() }

        controller.start(programPath: progPath)
        // While unchosen and both installed, extension is .quietAsking with .attention status.
        XCTAssertEqual(controller.currentRole(), .quietAsking)
        XCTAssertEqual(RemotePages.statusMark(for: controller.currentState()).state, .attention)
        let askingIsland = controller.islandPage()
        XCTAssertTrue(treeContains(askingIsland, "Choose One Vitruvian Remote"))
        XCTAssertTrue(treeContains(askingIsland, "Phone paired"))

        // Step 1: tap chooseExtension -> shows confirmation toggles.
        XCTAssertTrue(treeContains(askingIsland, "\"chooseExtension\""))
        let confirmTree = try XCTUnwrap(treeFrom(controller.handleIslandEvent(
            PanelEvent(block: "chooseExtension", kind: .tap)
        )))
        XCTAssertTrue(treeContains(confirmTree, "\"confirmUseExtension\""))

        // Step 2: confirm -> copies standalone settings + token, sets chosen = .extension, becomes active.
        let activeTree = try XCTUnwrap(treeFrom(controller.handleIslandEvent(
            PanelEvent(block: "confirmUseExtension", kind: .tap)
        )))
        XCTAssertFalse(treeContains(activeTree, "Choose One Vitruvian Remote"))
        XCTAssertEqual(RemoteChoiceFile.read(at: controller.profile.choiceFileURL).chosen, .extension)

        let copiedSettings = RemoteSettingsStore(profile: controller.profile).load()
        XCTAssertEqual(copiedSettings.ntfyTopic, "from-standalone")
        let copiedToken = try String(contentsOf: controller.profile.tokenURL, encoding: .utf8)
        XCTAssertEqual(copiedToken.trimmingCharacters(in: .whitespacesAndNewlines), "standalone-bearer-token")

        // Step 3: switch to standalone app from Settings -> General -> sets chosen = .app and goes quiet.
        _ = controller.settingsPage()
        let quietTree = try XCTUnwrap(treeFrom(controller.handleSettingsEvent(
            PanelEvent(block: RemotePages.Block.switchToStandaloneApp, kind: .tap)
        )))
        XCTAssertTrue(treeContains(quietTree, "Standalone App in Use"))
        XCTAssertEqual(RemoteChoiceFile.read(at: controller.profile.choiceFileURL).chosen, .app)
        XCTAssertEqual(RemotePages.statusMark(for: controller.currentState()).state, .none)
    }
}
