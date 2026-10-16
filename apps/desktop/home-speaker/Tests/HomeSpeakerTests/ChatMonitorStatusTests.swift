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

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-monitor-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Records what a request asks of the monitor.
@MainActor
private final class RecordingMonitor: ChatMonitorControlling {
    var isRunning = false
    var calls: [String] = []
    func start() { calls.append("start"); isRunning = true }
    func stop() { calls.append("stop"); isRunning = false }
}

// MARK: - The status file

@Suite struct ChatMonitorStatusFileTests {
    @Test func aStatusRoundTripsUnderSnakeCaseKeys() throws {
        let dir = try scratchDir()
        let file = ChatMonitorStatusFile(url: dir.appendingPathComponent(ChatMonitorStatusFile.fileName))
        let polled = Date(timeIntervalSince1970: 1_760_000_000)
        let status = ChatMonitorStatus(isRunning: true, lastPollDate: polled, lastError: "Slack: ratelimited",
                                       slackIdentity: "alice", activeGoogleChatBackend: "gws", pid: 4242)
        try file.write(status)
        #expect(file.read() == status)
        let text = try String(contentsOf: file.url, encoding: .utf8)
        for key in ["is_running", "last_poll_date", "last_error", "slack_identity", "active_google_chat_backend", "pid"] {
            #expect(text.contains("\"\(key)\""), "\(key) is written")
        }
        #expect(FileManager.default.fileExists(atPath: file.lockURL.path), "written under its own lock file")
    }

    @Test func aMissingOrBrokenFileReadsAsNothing() throws {
        let dir = try scratchDir()
        let file = ChatMonitorStatusFile(url: dir.appendingPathComponent("status.json"))
        #expect(file.read() == nil)
        try Data("{not json".utf8).write(to: file.url)
        #expect(file.read() == nil)
    }

    @Test func itLivesBesideTheSettingsFile() {
        let settings = URL(fileURLWithPath: "/tmp/somewhere/.gemini/speaker_broadcast.json")
        #expect(ChatMonitorStatusFile.url(beside: settings).path == "/tmp/somewhere/.gemini/speaker_monitor_status.json")
        #expect(ChatMonitorStatusFile.defaultURL().deletingLastPathComponent() == ConfigManager.defaultConfigURL().deletingLastPathComponent())
    }

    /// A crashed app leaves "running" behind: a reader that knows the app
    /// is gone must never believe it.
    @Test func aStatusFromAnAppThatIsNotRunningNeverReadsAsRunning() {
        let left = ChatMonitorStatus(isRunning: true, lastError: "Slack: boom", slackIdentity: "alice", pid: 7)
        let believed = left.believed(ownerRunning: false)
        #expect(!believed.isRunning)
        #expect(believed.lastError == nil)
        #expect(believed.slackIdentity == "alice")
        #expect(left.believed(ownerRunning: true) == left)
    }
}

// MARK: - The service writes it

@Suite @MainActor struct ChatMonitorServiceStatusTests {
    private func service(_ dir: URL, slack: Bool = false) -> (ChatMonitorService, ChatMonitorStatusFile) {
        let secrets = SecretStore(fileURL: dir.appendingPathComponent("s.json"))
        let manager = ConfigManager(configPath: dir.appendingPathComponent("c.json"),
                                    historyPath: dir.appendingPathComponent("h.json"), secrets: secrets)
        var monitor = manager.config.effectiveChatMonitor
        monitor.slackEnabled = slack
        monitor.googleChatEnabled = false
        manager.config.effectiveChatMonitor = monitor
        let file = ChatMonitorStatusFile(url: dir.appendingPathComponent(ChatMonitorStatusFile.fileName))
        return (ChatMonitorService(configManager: manager, secrets: secrets, statusFile: file), file)
    }

    @Test func aStartThatCannotRunWritesStopped() throws {
        let (service, file) = service(try scratchDir(), slack: true)
        service.start()
        defer { service.stop() }
        let status = try #require(file.read())
        #expect(!status.isRunning)
        #expect(status.lastError == nil, "a setup problem is the reader's to work out, not a runtime error")
        #expect(status.pid == ProcessInfo.processInfo.processIdentifier)
    }

    @Test func bothSourcesOffWritesStopped() throws {
        let (service, file) = service(try scratchDir())
        service.start()
        #expect(file.read()?.isRunning == false)
    }

    @Test func theSnapshotSaysWhatTheMonitorIsDoingAndStopWritesStopped() throws {
        let (service, file) = service(try scratchDir())
        let polled = Date(timeIntervalSince1970: 1_760_000_000)
        service.isRunning = true
        service.lastPollTime = polled
        service.slackUser = "alice"
        service.googleChatVia = "api"
        let snapshot = service.statusSnapshot
        #expect(snapshot.isRunning)
        #expect(snapshot.lastPollDate == polled)
        #expect(snapshot.slackIdentity == "alice")
        #expect(snapshot.activeGoogleChatBackend == "api")
        #expect(snapshot.lastError == nil)
        service.stop()
        let written = try #require(file.read())
        #expect(!written.isRunning)
        #expect(written.lastPollDate == polled)
    }

    @Test func aMonitorWithNoFileWritesNothing() throws {
        let dir = try scratchDir()
        let secrets = SecretStore(fileURL: dir.appendingPathComponent("s.json"))
        let manager = ConfigManager(configPath: dir.appendingPathComponent("c.json"),
                                    historyPath: dir.appendingPathComponent("h.json"), secrets: secrets)
        let service = ChatMonitorService(configManager: manager, secrets: secrets)
        service.start()
        service.stop()
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(ChatMonitorStatusFile.fileName).path))
    }
}

// MARK: - Start and stop from another process

@Suite struct ChatMonitorControlTests {
    @Test func theFlagParses() {
        #expect(ChatMonitorControlNotice.parse(["--chat-monitor", "start"]) == .success(.start))
        #expect(ChatMonitorControlNotice.parse(["--chat-monitor", "stop"]) == .success(.stop))
        #expect(ChatMonitorControlNotice.parse(["--say", "--chat-monitor", "start"]) == nil, "only as the first argument")
        #expect(ChatMonitorControlNotice.parse([]) == nil)
        guard case .failure(let missing)? = ChatMonitorControlNotice.parse(["--chat-monitor"]) else {
            Issue.record("no action is a usage error")
            return
        }
        #expect(missing.message.contains("start or stop"))
        guard case .failure(let wrong)? = ChatMonitorControlNotice.parse(["--chat-monitor", "pause"]) else {
            Issue.record("an unknown action is a usage error")
            return
        }
        #expect(wrong.message.contains("\"pause\""))
        if case .success? = ChatMonitorControlNotice.parse(["--chat-monitor", "start", "now"]) {
            Issue.record("one action only")
        }
    }

    @Test @MainActor func aRequestDoesWhatTheSettingsButtonsDo() {
        let monitor = RecordingMonitor()
        ChatMonitorControlNotice.apply(.start, monitor: monitor)
        ChatMonitorControlNotice.apply(.stop, monitor: monitor)
        #expect(monitor.calls == ["start", "stop"])
        #expect(ChatMonitorControlNotice.askedLine(.start) == "asked a running HomeSpeaker to start the chat monitor")
    }
}

// MARK: - Heard here, not on the speaker

@Suite struct PartialBroadcastTests {
    @Test func heardOnThisMacWithTheHomeSpeakerFailedSaysBoth() {
        let outcome = AnnounceOutcome.announced(home: .failed("speaker offline"), local: .spoken)
        #expect(outcome.spokenLines(homeName: "Kitchen") == ["Spoke on this Mac (Home speaker failed: speaker offline)"])
        #expect(AnnounceOutcome.spokeLocallyHomeFailed("x") == "Spoke on this Mac (Home speaker failed: x)")
    }

    @Test func everyOtherOutcomePrintsAsBefore() {
        #expect(AnnounceOutcome.announced(home: .spoken, local: .spoken).spokenLines(homeName: "Kitchen")
                == ["sent to Kitchen", "spoke on this Mac"])
        #expect(AnnounceOutcome.announced(home: .spoken, local: .off).spokenLines(homeName: "Kitchen") == ["sent to Kitchen"])
        #expect(AnnounceOutcome.announced(home: .off, local: .spoken).spokenLines(homeName: "Kitchen") == ["spoke on this Mac"])
        #expect(AnnounceOutcome.announced(home: .spoken, local: .failed("no voice")).spokenLines(homeName: "Kitchen")
                == ["sent to Kitchen"])
        #expect(AnnounceOutcome.announced(home: .failed("a"), local: .failed("b")).spokenLines(homeName: "Kitchen").isEmpty)
        #expect(AnnounceOutcome.quietHours(until: "07:00").spokenLines(homeName: "Kitchen").isEmpty)
    }
}
