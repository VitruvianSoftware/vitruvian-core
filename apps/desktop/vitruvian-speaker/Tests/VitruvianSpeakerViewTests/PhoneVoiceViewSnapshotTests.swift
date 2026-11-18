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

import AppKit
import SwiftUI
import XCTest
@testable import VitruvianSpeaker
@testable import VitruvianSpeakerCore

@MainActor
final class PhoneVoiceViewSnapshotTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-speaker-view-phone-voice-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    private func makeFixture(
        phoneVoiceEngine: PhoneVoiceEngine? = nil,
        hasGeminiKey: Bool = false
    ) throws -> (
        configManager: ConfigManager,
        monitor: ChatMonitorService,
        door: AppDoor,
        switcher: AppSwitch
    ) {
        let settingsURL = tempRoot.appendingPathComponent("settings.json")
        let historyURL = tempRoot.appendingPathComponent("history.json")
        let secretsURL = tempRoot.appendingPathComponent("secrets.json")
        let queueURL = tempRoot.appendingPathComponent("snooze_queue.json")
        let doorURL = tempRoot.appendingPathComponent("door.json")

        var config = SpeakerConfig(
            enabled: true,
            defaultTarget: "kitchen",
            structureId: "s1",
            structureName: "Home",
            targets: [
                "kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen", room: "Kitchen"),
            ],
            quietHoursEnabled: false
        )
        config.effectiveSpeakHome = false
        config.effectiveSpeakLocal = false
        config.effectiveSpeakPhone = true
        config.phoneVoiceEngine = phoneVoiceEngine
        try SpeakerConfigFile(url: settingsURL).write(config)

        let secrets = SecretStore(fileURL: secretsURL)
        if hasGeminiKey {
            try secrets.save(Secrets(geminiApiKey: "test-gemini-key")) // gitleaks:allow
        }
        let queue = SnoozeQueue(fileURL: queueURL)
        let configManager = ConfigManager(
            configPath: settingsURL,
            history: BroadcastHistory(fileURL: historyURL),
            secrets: secrets,
            snoozeQueue: queue
        )
        configManager.isConnectedToGoogle = true
        configManager.googleEmail = "alex@example.com"

        let monitor = ChatMonitorService(
            configManager: configManager,
            secrets: secrets
        )

        let profile = VitruvianSpeakerProfile(
            door: .app,
            settingsURL: settingsURL,
            historyURL: historyURL,
            secretsURL: secretsURL,
            messagePrefix: "test.\(UUID().uuidString).vitruvian-speaker",
            liveLockURL: nil,
            toolFolder: nil
        )
        let check = DoorCheck(
            file: DoorFile(url: doorURL),
            appInstalled: { true },
            fileExists: { _ in false }
        )
        let door = AppDoor(
            check: check,
            bundlePath: { "/Applications/Vitruvian Speaker.app" },
            monitor: monitor,
            effects: AppDoor.Effects(
                repairHooks: { _ in },
                startMonitorIfConfigured: {},
                stopMonitor: {},
                startListening: {},
                stopListening: {}
            ),
            extensionReadsChat: { _ in false },
            later: { _ in }
        )
        let switcher = AppSwitch(
            door: door,
            parts: AppSwitch.Parts(
                appProfile: profile,
                home: tempRoot,
                now: Date.init,
                copy: { _, _ in throw DoorCopyError.unreadableSecrets(path: "") },
                credentialsChangedIn: { _ in },
                turnOffLoginItem: {},
                moveToTrash: {},
                quit: {},
                openVitruvian: { false }
            )
        )

        return (configManager, monitor, door, switcher)
    }

    private func expectSensible(_ sizes: [NSSize], minWidth: CGFloat, _ name: String) {
        XCTAssertEqual(sizes.count, 2, name)
        for size in sizes {
            XCTAssertGreaterThanOrEqual(size.width, minWidth, name)
            XCTAssertGreaterThan(size.height, 120, name)
            XCTAssertLessThan(size.height, 2000, name)
        }
    }

    func testSettingsYourPhoneVoicePickerAndMenuBar() throws {
        let defaultFx = try makeFixture(phoneVoiceEngine: nil, hasGeminiKey: false)
        let defaultVM = SettingsViewModel()
        let defaultView = SettingsView(
            configManager: defaultFx.configManager,
            monitorService: defaultFx.monitor,
            viewModel: defaultVM,
            door: defaultFx.door,
            switcher: defaultFx.switcher
        )
        expectSensible(try Snapshot.render("settings-your-phone-voice", width: 540) {
            defaultView.speakersTab
        }, minWidth: 540, "settings-your-phone-voice")

        expectSensible(try Snapshot.render("menubar-your-phone-voice", width: 340) {
            MenuBarView(
                configManager: defaultFx.configManager,
                monitorService: defaultFx.monitor,
                viewModel: MenuBarViewModel(),
                door: defaultFx.door,
                switcher: defaultFx.switcher
            )
        }, minWidth: 340, "menubar-your-phone-voice")

        let noKeyGeminiFx = try makeFixture(phoneVoiceEngine: .gemini, hasGeminiKey: false)
        let noKeyGeminiView = SettingsView(
            configManager: noKeyGeminiFx.configManager,
            monitorService: noKeyGeminiFx.monitor,
            viewModel: SettingsViewModel(),
            door: noKeyGeminiFx.door,
            switcher: noKeyGeminiFx.switcher
        )
        expectSensible(try Snapshot.render("settings-your-phone-voice-gemini-no-key", width: 540) {
            noKeyGeminiView.speakersTab
        }, minWidth: 540, "settings-your-phone-voice-gemini-no-key")
    }
}
