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
import XCTest

final class RemoteMenuCoreTests: XCTestCase {
    // Captured from a live agent (v1.8.0) on 2026-09-26.
    let healthJSON = #"{"agent_version":"1.8.0","notify":{"configured":true,"enabled":false,"topic":"vitruvian-remote"},"ok":true,"paired":true,"read_only":false,"sample_age_ms":553,"sampled_at":"2026-09-26T17:43:08.54898-07:00"}"#
    let noPhoneJSON = #"{"connected":false,"device":null,"since":null,"tools":[],"trust_until":null}"#
    let phoneJSON = #"{"connected":true,"device":{"model":"Pixel Fold","android":"16"},"since":"2026-09-26T17:02:00.123-07:00","tools":["sms.list"],"trust_until":null}"#

    func decode<T: Decodable>(_ s: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(s.utf8))
    }

    func testDecodesLiveHealth() throws {
        let h: AgentHealth = try decode(healthJSON)
        XCTAssertTrue(h.ok)
        XCTAssertTrue(h.paired)
        XCTAssertEqual(h.agentVersion, "1.8.0")
        XCTAssertEqual(h.notify, .init(configured: true, enabled: false))
    }

    func testClassify() {
        let ok = AgentHealth(ok: true, agentVersion: "1.8.0", paired: true)
        let stale = AgentHealth(ok: false, agentVersion: "1.8.0", paired: true)
        XCTAssertEqual(StatusSnapshot.classify(installed: false, status: nil, health: nil), .notInstalled)
        XCTAssertEqual(StatusSnapshot.classify(installed: true, status: nil, health: nil), .down)
        XCTAssertEqual(StatusSnapshot.classify(installed: true, status: 200, health: ok), .running(version: "1.8.0"))
        // /healthz answers 503 with a body while readings are old.
        XCTAssertEqual(StatusSnapshot.classify(installed: true, status: 503, health: stale), .stale(version: "1.8.0"))
        // An answer we can't parse is alive but not healthy, never "running".
        XCTAssertEqual(StatusSnapshot.classify(installed: true, status: 200, health: nil), .stale(version: nil))
    }

    func testAgentLine() {
        XCTAssertEqual(StatusSnapshot(state: .running(version: "1.8.0")).agentLine, "Agent running · v1.8.0")
        XCTAssertEqual(StatusSnapshot(state: .running(version: nil)).agentLine, "Agent running")
        XCTAssertEqual(StatusSnapshot(state: .down).agentLine, "Agent not responding")
        XCTAssertEqual(StatusSnapshot(state: .notInstalled).agentLine, "Agent not installed")
    }

    func testPhoneLine() throws {
        let health: AgentHealth = try decode(healthJSON)
        let running = AgentState.running(version: "1.8.0")

        XCTAssertEqual(StatusSnapshot(state: running, health: health, phone: try decode(noPhoneJSON)).phoneLine(),
                       "Phone paired, not connected")

        var unpaired = health
        unpaired.paired = false
        XCTAssertEqual(StatusSnapshot(state: running, health: unpaired, phone: try decode(noPhoneJSON)).phoneLine(),
                       "No phone paired")

        let linked = try XCTUnwrap(StatusSnapshot(state: running, health: health, phone: try decode(phoneJSON)).phoneLine())
        XCTAssertTrue(linked.hasPrefix("Pixel Fold connected since "), linked)

        // Nothing is claimed about a phone while the agent can't be asked.
        XCTAssertNil(StatusSnapshot(state: .down, health: health, phone: try decode(phoneJSON)).phoneLine())
    }

    func testNotificationsLine() {
        func line(_ n: AgentHealth.Notify?) -> String? {
            StatusSnapshot(state: .running(version: nil), health: AgentHealth(ok: true, paired: true, notify: n)).notificationsLine
        }
        XCTAssertEqual(line(.init(configured: true, enabled: true)), "Push notifications on")
        XCTAssertEqual(line(.init(configured: true, enabled: false)), "Push notifications off")
        XCTAssertEqual(line(.init(configured: false, enabled: false)), "Push notifications not set up")
        XCTAssertNil(line(nil))
    }

    func testPairCode() {
        XCTAssertEqual(PairCode.normalize("482917"), "482917")
        XCTAssertEqual(PairCode.normalize(" 482 917 "), "482917")
        XCTAssertEqual(PairCode.normalize("482-917"), "482917")
        XCTAssertNil(PairCode.normalize("48291"))
        XCTAssertNil(PairCode.normalize("4829177"))
        XCTAssertNil(PairCode.normalize("48291a"))
        XCTAssertNil(PairCode.normalize("٤٨٢٩١٧")) // non-ASCII digits: the agent rejects these
    }

    // The other half of this check, that install.sh still writes these same
    // paths, is paths_match_installer_test.sh.
    func testPaths() {
        let p = AgentPaths(home: URL(fileURLWithPath: "/Users/x"))
        XCTAssertEqual(p.binary.path, "/Users/x/.local/bin/vitruvian-remote-agent")
        XCTAssertEqual(p.log.path, "/Users/x/Library/Logs/vitruvian-remote-agent.log")
        XCTAssertEqual(AgentPaths.label, "com.vitruvian.remote-agent")
        XCTAssertEqual(AgentPaths.restartArguments(uid: 501), ["kickstart", "-k", "gui/501/com.vitruvian.remote-agent"])
    }

    func testQRPageURL() {
        XCTAssertEqual(QRPairing.pageURL(address: "100.124.228.116", code: "482917")?.absoluteString,
                       "http://100.124.228.116:7411/pair?code=482917")
        // Only a Tailscale address and a clean six-digit code make a QR.
        XCTAssertNil(QRPairing.pageURL(address: "192.168.1.5", code: "482917"))
        XCTAssertNil(QRPairing.pageURL(address: "100.124.228.116", code: "48291"))
        XCTAssertNil(QRPairing.pageURL(address: "100.124.228.116", code: "482 917"))
    }

    func testTailscaleRange() {
        XCTAssertTrue(QRPairing.isTailscaleIPv4("100.64.0.1"))
        XCTAssertTrue(QRPairing.isTailscaleIPv4("100.127.255.254"))
        XCTAssertFalse(QRPairing.isTailscaleIPv4("100.63.255.255"))
        XCTAssertFalse(QRPairing.isTailscaleIPv4("100.128.0.1"))
        XCTAssertFalse(QRPairing.isTailscaleIPv4("10.0.0.1"))
        XCTAssertFalse(QRPairing.isTailscaleIPv4("100.64.0"))
        XCTAssertFalse(QRPairing.isTailscaleIPv4("100.64.0.256"))
    }

    func testNewCodeIsSixDigits() {
        for _ in 0..<200 {
            XCTAssertNotNil(PairCode.normalize(QRPairing.newCode()))
        }
    }

    func testTailnetLineOnlyWhenBroken() {
        XCTAssertNil(StatusSnapshot(state: .running(version: nil), tailnetReachable: true).tailnetLine)
        XCTAssertNil(StatusSnapshot(state: .running(version: nil), tailnetReachable: nil).tailnetLine)
        XCTAssertEqual(StatusSnapshot(state: .running(version: nil), tailnetReachable: false).tailnetLine,
                       "Phone can't reach it over Tailscale")
    }

    func testExtensionFoldersResolveFromToolBinaryPath() throws {
        let bin = URL(fileURLWithPath: "/Users/x/Library/Application Support/Vitruvian/Tools/dev.vitruvian.remote/bin/tool")
        let folders = try XCTUnwrap(RemoteProfile.extensionFolders(program: bin))
        XCTAssertEqual(folders.tool.path, "/Users/x/Library/Application Support/Vitruvian/Tools/dev.vitruvian.remote")
        XCTAssertEqual(folders.data.path, "/Users/x/Library/Application Support/Vitruvian/ToolData/dev.vitruvian.remote")

        let prof = RemoteProfile.extension(dataFolder: folders.data, toolFolder: folders.tool, home: URL(fileURLWithPath: "/Users/x"))
        XCTAssertEqual(prof.settingsURL.path, "/Users/x/Library/Application Support/Vitruvian/ToolData/dev.vitruvian.remote/settings.json")
        XCTAssertEqual(prof.configDirURL.path, "/Users/x/Library/Application Support/Vitruvian/ToolData/dev.vitruvian.remote/config")
        XCTAssertEqual(prof.agentBinaryURL.path, "/Users/x/Library/Application Support/Vitruvian/Tools/dev.vitruvian.remote/bin/vitruvian-remote-agent")
        // Quotes paths with spaces in hookCommandLine and mcpAddCommand.
        XCTAssertEqual(
            prof.hookCommandLine(home: URL(fileURLWithPath: "/Users/x")),
            "'/Users/x/Library/Application Support/Vitruvian/Tools/dev.vitruvian.remote/bin/vitruvian-remote-agent' permission-hook --config-dir '/Users/x/Library/Application Support/Vitruvian/ToolData/dev.vitruvian.remote/config'"
        )
        XCTAssertTrue(prof.mcpAddCommand.contains("'/Users/x/Library/Application Support/Vitruvian/ToolData/dev.vitruvian.remote/config/mcp-token'"))
    }

    func testSettingsParseLaunchAgentPlistAndBuildAgentArgsWithSafetyGuards() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("remote-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let plistURL = tmp.appendingPathComponent("com.vitruvian.remote-agent.plist")
        let plist: [String: Any] = [
            "Label": "com.vitruvian.remote-agent",
            "ProgramArguments": [
                "/Users/x/.local/bin/vitruvian-remote-agent",
                "--tailscale=false",
                "--interval", "5s",
                "--kubeconfig", "/Users/x/.kube/config",
                "--kube-context", "homelab",
                "--prometheus-url", "https://prometheus.example.com",
                "--ntfy-url", "https://ntfy.example.com",
                "--ntfy-topic", "my-topic",
                "--gh-extra-repos", "org/one,org/two",
                "--exec-dir", tmp.path,
                "--permission-wait", "90s",
            ],
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: plistURL)

        let imported = try XCTUnwrap(RemoteSettings.importFromLaunchAgentPlist(at: plistURL)).settings
        XCTAssertFalse(imported.tailscale)
        XCTAssertEqual(imported.intervalSeconds, 5)
        XCTAssertEqual(imported.kubeconfig, "/Users/x/.kube/config")
        XCTAssertEqual(imported.kubeContext, "homelab")
        XCTAssertEqual(imported.prometheusURL, "https://prometheus.example.com")
        XCTAssertEqual(imported.ntfyURL, "https://ntfy.example.com")
        XCTAssertEqual(imported.ntfyTopic, "my-topic")
        XCTAssertEqual(imported.ghExtraRepos, "org/one,org/two")
        XCTAssertEqual(imported.execDir, tmp.path)
        XCTAssertEqual(imported.permissionWaitSeconds, 90)

        let extProfile = RemoteProfile.extension(
            dataFolder: tmp.appendingPathComponent("data", isDirectory: true),
            toolFolder: tmp.appendingPathComponent("tool", isDirectory: true),
            home: tmp
        )
        try FileManager.default.createDirectory(at: extProfile.configDirURL, withIntermediateDirectories: true)

        // Without token files on disk, --ntfy-token-file and --prometheus-token-file are omitted.
        let argsWithoutTokens = imported.agentArguments(for: extProfile, home: tmp)
        XCTAssertTrue(argsWithoutTokens.contains("--config-dir"))
        XCTAssertTrue(argsWithoutTokens.contains("--ntfy-url"))
        XCTAssertTrue(argsWithoutTokens.contains("--ntfy-topic"))
        XCTAssertFalse(argsWithoutTokens.contains("--ntfy-token-file"))
        XCTAssertFalse(argsWithoutTokens.contains("--prometheus-token-file"))

        // When only ntfyURL is set without ntfyTopic, neither flag is passed so the agent does not exit(2).
        var halfNtfy = imported
        halfNtfy.ntfyTopic = ""
        let halfArgs = halfNtfy.agentArguments(for: extProfile, home: tmp)
        XCTAssertFalse(halfArgs.contains("--ntfy-url"))
        XCTAssertFalse(halfArgs.contains("--ntfy-topic"))

        // When execDir does not exist, --exec-dir is omitted so the agent does not exit(2).
        var missingExec = imported
        missingExec.execDir = tmp.appendingPathComponent("does-not-exist").path
        XCTAssertFalse(missingExec.agentArguments(for: extProfile, home: tmp).contains("--exec-dir"))
    }

    func testCoexistenceRoleAndDataCopyPreserveSecrets() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("remote-coexist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let appProfile = RemoteProfile.app(home: tmp)
        let extData = tmp.appendingPathComponent("Library/Application Support/Vitruvian/ToolData/dev.vitruvian.remote", isDirectory: true)
        let extTool = tmp.appendingPathComponent("Library/Application Support/Vitruvian/Tools/dev.vitruvian.remote", isDirectory: true)
        let extProfile = RemoteProfile.extension(dataFolder: extData, toolFolder: extTool, home: tmp)

        // Alone initially when only one side is installed.
        let emptyChoice = RemoteChoiceFile.read(at: extProfile.choiceFileURL)
        XCTAssertEqual(RemoteRole.resolve(for: .extension, choice: emptyChoice, appInstalled: false, extensionInstalled: true), .activeAlone)

        // Create standalone paired token + ntfy token + settings.
        try FileManager.default.createDirectory(at: appProfile.configDirURL, withIntermediateDirectories: true)
        try Data("secret-bearer-token\n".utf8).write(to: appProfile.configDirURL.appendingPathComponent("token"))
        try Data("2026-10-15T12:00:00Z\n".utf8).write(to: appProfile.configDirURL.appendingPathComponent("paired"))
        try Data("ntfy-secret\n".utf8).write(to: appProfile.configDirURL.appendingPathComponent("ntfy-token"))

        let appStore = RemoteSettingsStore(profile: appProfile)
        var appSettings = RemoteSettings()
        appSettings.ntfyURL = "https://ntfy.sh"
        appSettings.ntfyTopic = "remote-alerts"
        appSettings.kubeContext = "homelab"
        try appStore.save(appSettings)

        // Record extension presence; with standalone installed and no choice made:
        // standalone is .activeAsking, extension is .quietAsking.
        let unchosen = try RemoteChoiceFile.recordExtension(
            program: extTool.appendingPathComponent("bin/tool").path,
            dataFolder: extData.path,
            at: extProfile.choiceFileURL
        )
        XCTAssertEqual(RemoteRole.resolve(for: .app, choice: unchosen, appInstalled: true, extensionInstalled: true), .activeAsking)
        XCTAssertEqual(RemoteRole.resolve(for: .extension, choice: unchosen, appInstalled: true, extensionInstalled: true), .quietAsking)

        // Choose extension and copy standalone data across.
        try RemoteDataCopy.copy(from: appProfile, to: extProfile, home: tmp)
        let chosenExt = try RemoteChoiceFile.choose(.extension, at: extProfile.choiceFileURL)
        XCTAssertEqual(RemoteRole.resolve(for: .extension, choice: chosenExt, appInstalled: true, extensionInstalled: true), .activeChosen)
        XCTAssertEqual(RemoteRole.resolve(for: .app, choice: chosenExt, appInstalled: true, extensionInstalled: true), .quietChosen)

        let extSummary = RemoteSideSummary.inspect(extProfile)
        XCTAssertTrue(extSummary.isPaired)
        XCTAssertEqual(extSummary.ntfyTopic, "remote-alerts")
        XCTAssertEqual(extSummary.kubeContext, "homelab")
        let copiedToken = try String(contentsOf: extProfile.configDirURL.appendingPathComponent("token"), encoding: .utf8)
        XCTAssertEqual(copiedToken.trimmingCharacters(in: .whitespacesAndNewlines), "secret-bearer-token")
        let extStore = RemoteSettingsStore(profile: extProfile)
        XCTAssertTrue(extStore.hasNtfyToken)
    }

    func testClaudeHookInspectorDetectsHook() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("remote-hook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let claudeDir = tmp.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settingsFile = claudeDir.appendingPathComponent("settings.json")
        let json = """
        {
          "hooks": {
            "PermissionRequest": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/Users/x/Library/Application Support/Vitruvian/Tools/dev.vitruvian.remote/bin/vitruvian-remote-agent' permission-hook --config-dir '/Users/x/Library/Application Support/Vitruvian/ToolData/dev.vitruvian.remote/config'"
                  }
                ]
              }
            ]
          }
        }
        """
        try Data(json.utf8).write(to: settingsFile)
        XCTAssertTrue(ClaudeHookInspector.isInstalled(at: settingsFile))
    }

    func testQRPairingGeneratesPNGDataURL() {
        let url = "http://100.124.228.116:7411/pair?code=482917"
        let dataURL = QRPairing.pngDataURL(for: url)
        XCTAssertNotNil(dataURL)
        XCTAssertTrue(dataURL?.hasPrefix("data:image/png;base64,") == true)
    }
}
