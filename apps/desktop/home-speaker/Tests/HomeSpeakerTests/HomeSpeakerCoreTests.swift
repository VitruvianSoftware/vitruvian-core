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
import Testing
@testable import HomeSpeakerCore

// swift-testing (not XCTest): XCTest is absent from the Command Line Tools
// toolchain, so `swift test` only works here with the Testing framework.

@Suite struct SpeechCleaningTests {
    @Test func markdownIsStripped() {
        let input = "**Problem:** The build failed.\n\n```bash\nexit 1\n```\n**Fix:** We restarted `nginx`.\n- Point 1\n- Point 2"
        let output = GoogleHomeClient.cleanForSpeech(input)
        #expect(!output.contains("```"))
        #expect(!output.contains("`nginx`"))
        #expect(output.contains("nginx"))
        #expect(output.contains("Problem:"))
        #expect(output.contains("Fix:"))
    }
}

@Suite struct SpeakerConfigCodableTests {
    @Test func roundTrip() throws {
        var config = SpeakerConfig(enabled: true, defaultTarget: "lake_office_display")
        config.targets["lake_office_display"] = SpeakerDevice(
            id: "device@324ed736", type: "GoogleDisplayDevice", name: "Lake Office display", room: "Lake Office")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SpeakerConfig.self, from: data)
        #expect(decoded.enabled == true)
        #expect(decoded.defaultTarget == "lake_office_display")
        #expect(decoded.targets["lake_office_display"]?.name == "Lake Office display")
    }
}

@Suite struct AgentIntegrationTests {
    @Test func checksDoNotCrash() {
        let agent = AgentIntegration.shared
        _ = agent.isClaudeCodeHookInstalled()
        _ = agent.isLegacyLaunchAgentInstalled()
    }
}

// MARK: - Quiet Hours

private func at(_ hhmm: String) -> Date {
    let parts = hhmm.split(separator: ":").map { Int($0)! }
    var comps = DateComponents()
    comps.year = 2026; comps.month = 9; comps.day = 18
    comps.hour = parts[0]; comps.minute = parts[1]
    return Calendar(identifier: .gregorian).date(from: comps)!
}

private func quiet(enabled: Bool? = true, start: String? = "22:00", end: String? = "07:00") -> SpeakerConfig {
    SpeakerConfig(quietHoursEnabled: enabled, quietHoursStart: start, quietHoursEnd: end)
}

@Suite struct QuietHoursTests {
    @Test func overnightWindowCoversLateNightAndEarlyMorning() {
        let cfg = quiet()
        #expect(cfg.isInQuietHours(at: at("23:30")))
        #expect(cfg.isInQuietHours(at: at("03:00")))
        #expect(cfg.isInQuietHours(at: at("22:00")), "start boundary is inclusive")
        #expect(!cfg.isInQuietHours(at: at("07:00")), "end boundary is exclusive")
        #expect(!cfg.isInQuietHours(at: at("12:00")))
        #expect(!cfg.isInQuietHours(at: at("21:59")))
    }

    @Test func sameDayWindow() {
        let cfg = quiet(start: "13:00", end: "14:30")
        #expect(cfg.isInQuietHours(at: at("13:00")))
        #expect(cfg.isInQuietHours(at: at("14:29")))
        #expect(!cfg.isInQuietHours(at: at("14:30")))
        #expect(!cfg.isInQuietHours(at: at("12:59")))
        #expect(!cfg.isInQuietHours(at: at("23:00")))
    }

    @Test func disabledOrMissingIsNeverQuiet() {
        #expect(!quiet(enabled: false).isInQuietHours(at: at("23:30")))
        #expect(!quiet(enabled: nil).isInQuietHours(at: at("23:30")))
        #expect(!quiet(start: nil).isInQuietHours(at: at("23:30")))
        #expect(!quiet(end: nil).isInQuietHours(at: at("23:30")))
    }

    @Test func malformedTimesFailOpen() {
        #expect(!quiet(start: "ten pm").isInQuietHours(at: at("23:30")))
        #expect(!quiet(start: "25:00").isInQuietHours(at: at("23:30")))
        #expect(!quiet(end: "07:60").isInQuietHours(at: at("23:30")))
        #expect(!quiet(start: "22:00", end: "22:00").isInQuietHours(at: at("22:00")), "zero-length window is never quiet")
    }

    @Test func minutesSinceMidnightParser() {
        #expect(SpeakerConfig.minutesSinceMidnight("22:00") == 22 * 60)
        #expect(SpeakerConfig.minutesSinceMidnight("7:05") == 7 * 60 + 5)
        #expect(SpeakerConfig.minutesSinceMidnight(" 07:05 ") == 7 * 60 + 5)
        #expect(SpeakerConfig.minutesSinceMidnight("24:00") == nil)
        #expect(SpeakerConfig.minutesSinceMidnight("0700") == nil)
        #expect(SpeakerConfig.minutesSinceMidnight("") == nil)
    }

    @Test func gateSuppressesUnlessForced() {
        let cfg = quiet()
        #expect(GoogleHomeClient.isSuppressedByQuietHours(config: cfg, force: false, at: at("23:30")))
        #expect(!GoogleHomeClient.isSuppressedByQuietHours(config: cfg, force: true, at: at("23:30")))
        #expect(!GoogleHomeClient.isSuppressedByQuietHours(config: cfg, force: false, at: at("12:00")))
        #expect(!GoogleHomeClient.isSuppressedByQuietHours(config: nil, force: false, at: at("23:30")))
    }

    @Test func broadcastThrowsQuietHoursBeforeTouchingCredentials() async throws {
        // Suppression must be decided before any token or network I/O.
        let target = SpeakerDevice(id: "device@x", type: "SpeakerDevice", name: "Test")
        await #expect(throws: BroadcastError.quietHours(until: "07:00")) {
            _ = try await GoogleHomeClient.shared.broadcast(
                text: "hello", target: target, structureId: "s", config: quiet(), force: false, at: at("23:30"))
        }
    }
}

// MARK: - Target de-duplication

private func sampleTargets() -> [String: SpeakerDevice] {
    let lake = SpeakerDevice(id: "device@lake", type: "GoogleDisplayDevice", name: "Lake Office display", room: "Lake Office")
    return [
        "lake_office": lake,
        "lake_office_display": lake,
        "kitchen": SpeakerDevice(id: "device@kitchen", type: "SpeakerDevice", name: "Kitchen Home", room: "Kitchen"),
        "all": SpeakerDevice(id: "structure@s", type: "Structure", name: "Whole Home (All Speakers)", room: "All"),
    ]
}

@Suite struct TargetDedupTests {
    @Test func duplicateDeviceIdsCollapseToOneEntry() {
        let unique = SpeakerConfig(defaultTarget: "kitchen", targets: sampleTargets()).uniqueTargets()
        #expect(unique.count == 3)
        #expect(Set(unique.map { $0.device.id }).count == 3)
    }

    @Test func defaultTargetKeyIsKeptSoPickerSelectionStaysValid() {
        let keys = SpeakerConfig(defaultTarget: "lake_office_display", targets: sampleTargets()).uniqueTargets().map { $0.key }
        #expect(keys.contains("lake_office_display"))
        #expect(!keys.contains("lake_office"))
    }

    @Test func shortestAliasWinsWhenNeitherIsDefault() {
        let keys = SpeakerConfig(defaultTarget: "kitchen", targets: sampleTargets()).uniqueTargets().map { $0.key }
        #expect(keys.contains("lake_office"))
        #expect(!keys.contains("lake_office_display"))
    }

    @Test func sortedByDisplayName() {
        let names = SpeakerConfig(defaultTarget: "kitchen", targets: sampleTargets()).uniqueTargets().map { $0.device.name }
        #expect(names == names.sorted())
    }

    @Test func displayLineIsSingleLineAndSkipsRedundantRoom() {
        #expect(SpeakerDevice(id: "a", type: "SpeakerDevice", name: "Kitchen Home", room: "Kitchen").displayLine == "Kitchen Home")
        #expect(SpeakerDevice(id: "a", type: "SpeakerDevice", name: "Mini pair", room: "Master Bedroom").displayLine == "Mini pair · Master Bedroom")
        #expect(SpeakerDevice(id: "a", type: "SpeakerDevice", name: "Solo").displayLine == "Solo")
        #expect(!SpeakerDevice(id: "a", type: "SpeakerDevice", name: "X", room: "Y").displayLine.contains("\n"))
    }
}

// MARK: - Chat monitor config wiring

@Suite struct ChatMonitorConfigTests {
    @Test func legacyConfigWithoutChatMonitorKeyDecodesWithDefaults() throws {
        let legacy = Data("""
        {"enabled": true, "default_target": "kitchen", "structure_id": "s", "targets": {}}
        """.utf8)
        let cfg = try JSONDecoder().decode(SpeakerConfig.self, from: legacy)
        #expect(cfg.chatMonitor == nil)
        #expect(cfg.effectiveChatMonitor == ChatMonitorConfig())
        #expect(!cfg.effectiveChatMonitor.slackEnabled, "monitoring is opt-in")
        #expect(!cfg.effectiveChatMonitor.googleChatEnabled)
        #expect(cfg.effectiveChatMonitor.pollIntervalSeconds == 15)
    }

    @Test func roundTripsInSnakeCaseWithoutSecrets() throws {
        var cfg = SpeakerConfig()
        cfg.chatMonitor = ChatMonitorConfig(slackEnabled: false, googleChatEnabled: true, pollIntervalSeconds: 30)
        let data = try JSONEncoder().encode(cfg)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let monitor = try #require(json["chat_monitor"] as? [String: Any])
        #expect(monitor["slack_enabled"] as? Bool == false)
        #expect(monitor["google_chat_enabled"] as? Bool == true)
        #expect(monitor["poll_interval_seconds"] as? Int == 30)
        #expect(monitor["slack_token"] == nil, "secrets are never persisted to the config file")
        #expect(try JSONDecoder().decode(SpeakerConfig.self, from: data).chatMonitor == cfg.chatMonitor)
    }

    @Test func anySourceEnabledFollowsTheToggles() {
        #expect(!ChatMonitorConfig().anySourceEnabled)
        #expect(ChatMonitorConfig(slackEnabled: false, googleChatEnabled: true).anySourceEnabled)
        #expect(ChatMonitorConfig(slackEnabled: true, googleChatEnabled: false).anySourceEnabled)
    }

    @Test func pollIntervalIsClamped() {
        #expect(ChatMonitorConfig(pollIntervalSeconds: 1).clampedPollInterval == 5)
        #expect(ChatMonitorConfig(pollIntervalSeconds: 9999).clampedPollInterval == 300)
    }
}
