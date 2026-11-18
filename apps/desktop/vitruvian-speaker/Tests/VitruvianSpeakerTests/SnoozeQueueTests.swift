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
@testable import VitruvianSpeakerCore

@Suite("Snooze Options & Queue")
struct SnoozeQueueTests {
    private final class RecordedCalls<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [T] = []
        func add(_ item: T) { lock.withLock { items.append(item) } }
        var all: [T] { lock.withLock { items } }
    }

    private final class FakeHome: HomeBroadcasting, @unchecked Sendable {
        let calls = RecordedCalls<String>()
        func speakerHoldSeconds(for text: String) -> TimeInterval { 0 }
        func broadcast(
            text: String,
            target: SpeakerDevice,
            structureId: String,
            config: SpeakerConfig?,
            force: Bool,
            at date: Date
        ) async throws -> Bool {
            calls.add(text)
            return true
        }
    }

    private final class FakeLocal: LocalSpeaking, @unchecked Sendable {
        let calls = RecordedCalls<String>()
        func speak(_ text: String, voiceID: String) async throws {
            calls.add(text)
        }
    }

    private struct NoMediaPause: MediaPausing {
        func pause(seconds: Double) async {}
        func extend(seconds: Double) async {}
        func resumeNow() async {}
    }

    private func makeScratchDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-speaker-snooze-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeProfile(in root: URL) -> VitruvianSpeakerProfile {
        .extension(
            dataFolder: root.appendingPathComponent("data", isDirectory: true),
            toolFolder: nil,
            messagePrefix: "test.\(UUID().uuidString).vitruvian-speaker"
        )
    }

    @Test("Legacy configs without snooze_default_minutes or snooze_queue decode safely and new keys round-trip")
    func configBackwardCompatibilityAndRoundTrip() throws {
        let legacyJSON = """
        {
          "enabled": true,
          "default_target": "kitchen",
          "structure_id": "struct-1",
          "targets": {
            "kitchen": {
              "id": "dev-1",
              "type": "SPEAKER",
              "name": "Kitchen"
            }
          }
        }
        """
        let legacy = try JSONDecoder().decode(SpeakerConfig.self, from: Data(legacyJSON.utf8))
        #expect(legacy.snoozeDefaultMinutes == nil)
        #expect(legacy.effectiveSnoozeDefaultMinutes == 30)
        #expect(legacy.snoozeQueue == nil)
        #expect(legacy.effectiveSnoozeQueue == false)

        var configured = legacy
        configured.snoozeDefaultMinutes = 45
        configured.snoozeQueue = true
        let data = try JSONEncoder().encode(configured)
        let decoded = try JSONDecoder().decode(SpeakerConfig.self, from: data)
        #expect(decoded.snoozeDefaultMinutes == 45)
        #expect(decoded.effectiveSnoozeDefaultMinutes == 45)
        #expect(decoded.snoozeQueue == true)
        #expect(decoded.effectiveSnoozeQueue == true)
    }

    @MainActor
    @Test("CLI snooze/resume flags, queued line, and non-flushing CLI behavior")
    func cliSnoozeResumeAndQueuedBehavior() async throws {
        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = makeProfile(in: root)
        let configFile = SpeakerConfigFile(url: profile.settingsURL)

        var config = SpeakerConfig(
            enabled: true,
            defaultTarget: "kitchen",
            structureId: "struct-1",
            targets: ["kitchen": SpeakerDevice(id: "dev-1", type: "SPEAKER", name: "Kitchen")],
            quietHoursEnabled: false,
            snoozeDefaultMinutes: 45,
            snoozeQueue: true
        )
        config.effectiveSpeakHome = true
        config.pauseMedia = false
        try configFile.write(config)

        let fakeHome = FakeHome()
        let fakeLocal = FakeLocal()
        let announcer = Announcer(
            home: fakeHome,
            local: fakeLocal,
            media: NoMediaPause(),
            speechLockURL: profile.speechLockURL,
            snoozeQueue: SnoozeQueue(fileURL: profile.snoozeQueueURL)
        )
        let engine = VitruvianSpeakerEngine(profile: profile, local: fakeLocal)
        let parts = VitruvianSpeakerCommandLine.Parts.app()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        // `--snooze` without minutes uses `snooze_default_minutes` (45).
        guard case .now(let snoozeOut) = BroadcastCommand.action(
            for: ["--snooze"],
            engine: engine,
            parts: parts,
            now: now
        ) else {
            Issue.record("Expected .now for --snooze")
            return
        }
        #expect(snoozeOut.exitCode == 0)
        let expectedUntil = now.addingTimeInterval(45 * 60)
        #expect(snoozeOut.stdout.first?.contains(SpeakerConfig.snoozedUntilLine(expectedUntil)) == true)
        if case .loaded(let afterSnooze) = configFile.read() {
            #expect(afterSnooze.snoozeUntil == expectedUntil)
        } else {
            Issue.record("Missing config after --snooze")
        }

        // `--snooze 120` and `--snooze=60` parse cleanly; invalid bounds exit 2.
        guard case .now(let explicitOut) = BroadcastCommand.action(
            for: ["--snooze=60"],
            engine: engine,
            parts: parts,
            now: now
        ) else {
            Issue.record("Expected .now for --snooze=60")
            return
        }
        #expect(explicitOut.exitCode == 0)
        if case .loaded(let afterExplicit) = configFile.read() {
            #expect(afterExplicit.snoozeUntil == now.addingTimeInterval(60 * 60))
        }
        for bad in [["--snooze", "0"], ["--snooze", "241"], ["--snooze=nope"]] {
            guard case .now(let badOut) = BroadcastCommand.action(for: bad, engine: engine, parts: parts, now: now) else {
                Issue.record("Expected usage error for \(bad)")
                continue
            }
            #expect(badOut.exitCode == 2)
        }

        // Speaking via CLI while snoozed + snooze_queue ON writes queued line and persists item without flushing.
        guard case .headless(_, _, let speakBody) = BroadcastCommand.action(
            for: ["Build finished"],
            engine: engine,
            parts: parts,
            announcerOverride: announcer,
            now: now
        ) else {
            Issue.record("Expected .headless for speaking")
            return
        }
        let speakOut = await speakBody()
        #expect(speakOut.exitCode == 0)
        let hhmm = SpeakerConfig.localTimeHHmm(now.addingTimeInterval(60 * 60))
        #expect(speakOut.stderr == ["Snoozed until \(hhmm). Queued — it will be spoken when snooze ends."])
        #expect(fakeHome.calls.all.isEmpty)
        #expect(engine.snoozeQueue.count() == 1)

        // Detached `--announce` also queues instead of flushing when snooze_queue is ON.
        var reloadedForAnnounce = config
        reloadedForAnnounce.snoozeUntil = now.addingTimeInterval(3600)
        let announceOut = await VitruvianSpeakerCommandLine.announce(
            "Agent reply",
            for: .claudeCode,
            config: reloadedForAnnounce,
            announcer: announcer,
            history: engine.history,
            standsAside: false,
            at: now
        )
        #expect(announceOut.exitCode == 0)
        #expect(announceOut.stderr == ["Snoozed until \(hhmm). Queued — it will be spoken when snooze ends."])
        #expect(engine.snoozeQueue.count() == 2)

        // `--status` includes the queued count while snoozed.
        guard case .now(let statusOut) = BroadcastCommand.action(for: ["--status"], engine: engine, parts: parts, now: now) else {
            Issue.record("Expected .now for --status")
            return
        }
        #expect(statusOut.stdout.contains { $0.contains("Snoozed: until \(hhmm) · 2 queued") })

        // `--resume` clears snoozeUntil and leaves queue items for the running app/extension to drain.
        guard case .now(let resumeOut) = BroadcastCommand.action(for: ["--resume"], engine: engine, parts: parts, now: now) else {
            Issue.record("Expected .now for --resume")
            return
        }
        #expect(resumeOut.exitCode == 0)
        #expect(resumeOut.stdout.first?.contains("2 queued") == true)
        if case .loaded(let afterResume) = configFile.read() {
            #expect(afterResume.snoozeUntil == nil)
        }
        #expect(engine.snoozeQueue.count() == 2, "CLI never flushes the queue")
        #expect(fakeHome.calls.all.isEmpty)
    }

    @MainActor
    @Test("SnoozeQueueCoordinator drains queued items once snooze clears and records history")
    func coordinatorDrainsWhenSnoozeClearsOrExpires() async throws {
        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = makeProfile(in: root)
        let queue = SnoozeQueue(fileURL: profile.snoozeQueueURL)
        let history = BroadcastHistory(fileURL: profile.historyURL)
        let fakeHome = FakeHome()
        let announcer = Announcer(home: fakeHome, local: FakeLocal(), media: NoMediaPause(), snoozeQueue: queue)

        final class ClockBox: @unchecked Sendable {
            private let lock = NSLock()
            private var current = Date(timeIntervalSince1970: 1_800_000_000)
            var now: Date {
                get { lock.withLock { current } }
                set { lock.withLock { current = newValue } }
            }
        }
        let clock = ClockBox()
        var config = SpeakerConfig(
            enabled: true,
            defaultTarget: "kitchen",
            structureId: "struct-1",
            targets: ["kitchen": SpeakerDevice(id: "dev-1", type: "SPEAKER", name: "Kitchen")],
            quietHoursEnabled: false,
            snoozeUntil: clock.now.addingTimeInterval(600),
            snoozeQueue: true
        )
        config.effectiveSpeakHome = true
        config.pauseMedia = false

        _ = await announcer.announce("First notice", config: config, force: false, source: "Slack", at: clock.now)
        _ = await announcer.announce("Second notice", config: config, force: false, source: "CLI", at: clock.now.addingTimeInterval(5))
        #expect(queue.count() == 2)

        final class FlagBox: @unchecked Sendable {
            var deliveredCount = 0
            var queueChanges = 0
        }
        let boxes = FlagBox()
        let coordinator = SnoozeQueueCoordinator(
            snoozeQueue: queue,
            announcer: announcer,
            history: history,
            configProvider: { config },
            onQueueChanged: { boxes.queueChanges += 1 },
            onDeliveredLog: { _ in boxes.deliveredCount += 1 },
            now: { clock.now }
        )

        coordinator.start()
        defer { coordinator.stop() }
        // Still snoozed -> nothing spoken.
        try await Task.sleep(for: .milliseconds(50))
        #expect(fakeHome.calls.all.isEmpty)
        #expect(queue.count() == 2)

        // Advance past snoozeUntil and poke -> drains FIFO with single lead-in.
        clock.now = clock.now.addingTimeInterval(601)
        coordinator.poke()
        for _ in 0..<50 where queue.count() > 0 || boxes.deliveredCount < 2 || history.load().count < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(queue.count() == 0)
        #expect(fakeHome.calls.all == ["While you were snoozed: First notice", "Second notice"])
        #expect(boxes.deliveredCount == 2)
        #expect(history.load().count == 2)
    }
}
