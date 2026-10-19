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

// The Mac app's Settings › Chats › Beeper network switches: which rows
// show (`BeeperNetworkList`, shared with the extension's pages) and what a
// switch saves (`ConfigManager.setBeeperNetwork`), which must never
// restart the monitor: each poll reads the mutes fresh, and a restart
// would drop what arrived meanwhile.

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("homespeaker-settings-networks-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Suite @MainActor struct SettingsViewNetworkTests {
    /// Records what is asked of the monitor.
    private final class Monitor: ChatMonitorControlling {
        var isRunning = true
        var calls: [String] = []
        func start() { calls.append("start"); isRunning = true }
        func stop() { calls.append("stop"); isRunning = false }
    }

    private func manager() throws -> (ConfigManager, URL) {
        let dir = try scratchDir()
        let url = dir.appendingPathComponent("c.json")
        let manager = ConfigManager(configPath: url, historyPath: dir.appendingPathComponent("h.json"),
                                    secrets: SecretStore(fileURL: dir.appendingPathComponent("s.json")))
        return (manager, url)
    }

    private func saved(_ url: URL) throws -> [String] {
        try JSONDecoder().decode(SpeakerConfig.self, from: Data(contentsOf: url)).effectiveChatMonitor.beeperMutedNetworks
    }

    @Test func aNetworkSwitchSavesTheMuteWithoutRestartingTheMonitor() throws {
        let (manager, url) = try manager()
        #expect(manager.setChatSource(\.beeperEnabled, true))
        let monitor = Monitor()
        manager.chatMonitor = monitor

        #expect(manager.setBeeperNetwork("whatsapp", reading: false))
        #expect(manager.config.effectiveChatMonitor.beeperMutedNetworks == ["whatsapp"])
        #expect(try saved(url) == ["whatsapp"])
        #expect(manager.setBeeperNetwork("telegram", reading: false))
        #expect(try saved(url) == ["whatsapp", "telegram"])
        #expect(manager.setBeeperNetwork("whatsapp", reading: true))
        #expect(try saved(url) == ["telegram"])
        #expect(!manager.setBeeperNetwork("whatsapp", reading: true), "already read: nothing to write")
        #expect(!manager.setBeeperNetwork("telegram", reading: false), "already muted: nothing to write")
        #expect(monitor.calls.isEmpty, "the monitor reads the mutes at its next poll; no restart")
        #expect(monitor.isRunning)
    }

    /// Muting a network already muted, not the last one saved, is no
    /// change: nothing written, and the saved order kept.
    @Test func mutingAMutedNetworkAgainChangesNothing() throws {
        let (manager, url) = try manager()
        #expect(manager.setBeeperNetwork("whatsapp", reading: false))
        #expect(manager.setBeeperNetwork("telegram", reading: false))
        let written = try Data(contentsOf: url)
        #expect(!manager.setBeeperNetwork("whatsapp", reading: false))
        #expect(manager.config.effectiveChatMonitor.beeperMutedNetworks == ["whatsapp", "telegram"])
        #expect(try Data(contentsOf: url) == written)

        var config = ChatMonitorConfig(beeperMutedNetworks: ["whatsapp", "telegram"])
        config.setBeeperNetwork("whatsapp", reading: false)
        #expect(config.beeperMutedNetworks == ["whatsapp", "telegram"])
        config.setBeeperNetwork("signal", reading: true)
        #expect(config.beeperMutedNetworks == ["whatsapp", "telegram"])
    }

    @Test func aFileThatWillNotTakeTheMuteChangesNothing() throws {
        let (manager, url) = try manager()
        try Data("not json".utf8).write(to: url)
        manager.loadConfig()
        #expect(!manager.setBeeperNetwork("whatsapp", reading: false))
        #expect(manager.config.effectiveChatMonitor.beeperMutedNetworks.isEmpty, "put back as it was")
    }

    @Test func theRowsFollowTheSavedMutesNotTheLastPoll() {
        let list = BeeperNetworkList(
            listed: [BeeperNetworkState(key: "whatsapp", name: "WhatsApp", state: .reading),
                     BeeperNetworkState(key: "telegram", name: "Telegram", state: .muted),
                     BeeperNetworkState(key: "slackgo", name: "Slack", state: .skipped)],
            muted: ["whatsapp", "slackgo", "signal"])
        #expect(list.rows == [
            BeeperNetworkState(key: "signal", name: "signal", state: .muted),
            BeeperNetworkState(key: "slackgo", name: "Slack", state: .skipped),
            BeeperNetworkState(key: "telegram", name: "Telegram", state: .reading),
            BeeperNetworkState(key: "whatsapp", name: "WhatsApp", state: .muted),
        ])
        #expect(list.isListed)
        #expect(list.shows(beeperEnabled: true))
    }

    @Test func notYetReadTheSavedMutesShowWithWhereTheOthersWillShow() {
        let unread = BeeperNetworkList(listed: nil, muted: ["telegram"])
        #expect(unread.rows == [BeeperNetworkState(key: "telegram", name: "telegram", state: .muted)])
        #expect(!unread.isListed)
        #expect(unread.shows(beeperEnabled: true))
        #expect(BeeperNetworkList.othersLater == "Other networks show here once Beeper is being read.")

        // Nothing saved and nothing read: shown while Beeper is on, so the
        // window says where the networks will show.
        #expect(BeeperNetworkList(listed: nil, muted: []).shows(beeperEnabled: true))
        #expect(!BeeperNetworkList(listed: nil, muted: []).shows(beeperEnabled: false))
        // Listed and empty: nothing to show.
        #expect(!BeeperNetworkList(listed: [], muted: []).shows(beeperEnabled: true))
    }
}
