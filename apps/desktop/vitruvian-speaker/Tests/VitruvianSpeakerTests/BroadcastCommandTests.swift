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

private func makeScratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vitruvian-speaker-broadcast-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeScratchProfile(in root: URL, name: String = "data") -> VitruvianSpeakerProfile {
    .extension(
        dataFolder: root.appendingPathComponent(name),
        toolFolder: nil,
        messagePrefix: "test.\(UUID().uuidString).vitruvian-speaker"
    )
}

private final class RecordedCalls<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func add(_ item: T) { lock.withLock { items.append(item) } }
    var all: [T] { lock.withLock { items } }
}

private struct RecordedHomeBroadcast: Equatable, Sendable {
    let text: String
    let targetKeyOrID: String
    let targetName: String
    let force: Bool
}

private final class FakeHomeBroadcaster: HomeBroadcasting, @unchecked Sendable {
    let calls = RecordedCalls<RecordedHomeBroadcast>()
    var failure: Error?

    func broadcast(
        text: String,
        target: SpeakerDevice,
        structureId: String,
        config: SpeakerConfig?,
        force: Bool,
        at date: Date
    ) async throws -> Bool {
        calls.add(RecordedHomeBroadcast(text: text, targetKeyOrID: target.id, targetName: target.name, force: force))
        if let failure { throw failure }
        return true
    }
}

private final class FakeLocalSpeaker: LocalSpeaking, @unchecked Sendable {
    let calls = RecordedCalls<String>()
    func speak(_ text: String, voiceID: String) async throws {
        calls.add(text)
    }
}

private struct SilentMediaPause: MediaPausing {
    func pause(seconds: Double) async {}
    func extend(seconds: Double) async {}
    func resumeNow() async {}
}

private struct SampleFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private func makeSampleConfig(
    enabled: Bool = true,
    defaultTarget: String = "office",
    quietEnabled: Bool = false,
    speakHome: Bool = true,
    speakLocal: Bool = false
) -> SpeakerConfig {
    var config = SpeakerConfig(
        enabled: enabled,
        defaultTarget: defaultTarget,
        structureId: "struct-1",
        targets: [
            "office": SpeakerDevice(id: "dev-office", type: "SPEAKER", name: "Office Speaker", room: "Home Office"),
            "kitchen_hub": SpeakerDevice(id: "dev-kitchen", type: "DISPLAY", name: "Kitchen Display", room: "Kitchen"),
            "bed": SpeakerDevice(id: "dev-bed", type: "SPEAKER", name: "Bedroom Mini", room: "Master Bedroom"),
            "office_alias": SpeakerDevice(id: "dev-office", type: "SPEAKER", name: "Office Speaker", room: "Home Office"),
        ],
        quietHoursEnabled: quietEnabled,
        quietHoursStart: "22:00",
        quietHoursEnd: "07:00"
    )
    config.effectiveSpeakHome = speakHome
    config.effectiveSpeakLocal = speakLocal
    config.pauseMedia = false
    return config
}

@Suite struct BroadcastCommandTests {
    // MARK: - argv[0] Detection & Argument Parsing

    @Test func detectsSpeakerBroadcastInvocationByBasename() {
        #expect(BroadcastCommand.isInvocation(argv0: "speaker-broadcast"))
        #expect(BroadcastCommand.isInvocation(argv0: "/Users/alice/.local/bin/speaker-broadcast"))
        #expect(BroadcastCommand.isInvocation(argv0: "./speaker-broadcast"))
        #expect(!BroadcastCommand.isInvocation(argv0: "/Applications/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker"))
        #expect(!BroadcastCommand.isInvocation(argv0: "/Users/alice/Library/Application Support/com.vitruviansoftware.atrium/Tools/dev.vitruvian.speaker/bin/tool"))
        #expect(!BroadcastCommand.isInvocation(argv0: ""))
        #expect(!BroadcastCommand.isInvocation(argv0: nil))
    }

    @Test func parsesSupportedFlagsAndMessages() {
        #expect(BroadcastCommand.parse([]) == .success(.showDefaultStatus))
        #expect(BroadcastCommand.parse(["-h"]) == .success(.help))
        #expect(BroadcastCommand.parse(["--help"]) == .success(.help))
        #expect(BroadcastCommand.parse(["--status"]) == .success(.status))
        #expect(BroadcastCommand.parse(["-l"]) == .success(.list))
        #expect(BroadcastCommand.parse(["--list"]) == .success(.list))
        #expect(BroadcastCommand.parse(["--on"]) == .success(.setEnabled(.on)))
        #expect(BroadcastCommand.parse(["--off"]) == .success(.setEnabled(.off)))
        #expect(BroadcastCommand.parse(["--toggle"]) == .success(.setEnabled(.toggle)))
        #expect(BroadcastCommand.parse(["-s", "kitchen"]) == .success(.setTarget("kitchen")))
        #expect(BroadcastCommand.parse(["--set-target", "Home Office"]) == .success(.setTarget("Home Office")))
        #expect(BroadcastCommand.parse(["--set-target=bed"]) == .success(.setTarget("bed")))

        #expect(BroadcastCommand.parse(["hello", "world"]) == .success(.speak(message: "hello world", target: nil, force: false)))
        #expect(BroadcastCommand.parse(["--force", "-t", "kitchen", "Dinner", "is", "ready"]) == .success(.speak(message: "Dinner is ready", target: "kitchen", force: true)))
        #expect(BroadcastCommand.parse(["--target=office", "Build", "passed"]) == .success(.speak(message: "Build passed", target: "office", force: false)))
        #expect(BroadcastCommand.parse(["--", "-dash", "word"]) == .success(.speak(message: "-dash word", target: nil, force: false)))
        #expect(BroadcastCommand.parse(["Build", "done", "-", "green"]) == .success(.speak(message: "Build done - green", target: nil, force: false)))
    }

    @Test func rejectsInvalidOrConflictingArguments() {
        #expect({ if case .failure = BroadcastCommand.parse(["--unknown"]) { return true }; return false }())
        #expect({ if case .failure = BroadcastCommand.parse(["-x"]) { return true }; return false }())
        #expect({ if case .failure = BroadcastCommand.parse(["-t"]) { return true }; return false }())
        #expect({ if case .failure = BroadcastCommand.parse(["--set-target"]) { return true }; return false }())
        #expect({ if case .failure = BroadcastCommand.parse(["--on", "--off"]) { return true }; return false }())
        #expect({ if case .failure = BroadcastCommand.parse(["--status", "--list"]) { return true }; return false }())
        #expect({ if case .failure = BroadcastCommand.parse(["--on", "hello"]) { return true }; return false }())
        #expect({ if case .failure = BroadcastCommand.parse(["--force"]) { return true }; return false }())
        #expect({ if case .failure = BroadcastCommand.parse(["-t", "kitchen"]) { return true }; return false }())
        #expect({ if case .failure = BroadcastCommand.parse(["   "]) { return true }; return false }())
    }

    // MARK: - Loose Target Resolution

    @Test func resolvesExactNormalizedAndSubstringTargets() {
        var config = makeSampleConfig()
        config.targets["living_room_tv"] = SpeakerDevice(id: "dev-lr-tv", type: "TV", name: "Living Room TV", room: "Living Room")
        config.targets["living_room_mini"] = SpeakerDevice(id: "dev-lr-mini", type: "SPEAKER", name: "Living Room Mini", room: "Living Room")

        // Exact key
        #expect({
            if case .matched(let key, _) = BroadcastCommand.resolveTarget("kitchen_hub", in: config) {
                return key == "kitchen_hub"
            }
            return false
        }())

        // Normalized lowercase + spaces -> underscores matching room/name/key
        #expect({
            if case .matched(let key, _) = BroadcastCommand.resolveTarget("Master Bedroom", in: config) {
                return key == "bed"
            }
            return false
        }())
        #expect({
            if case .matched(let key, _) = BroadcastCommand.resolveTarget("Kitchen Hub", in: config) {
                return key == "kitchen_hub"
            }
            return false
        }())

        // Substring match
        #expect({
            if case .matched(let key, _) = BroadcastCommand.resolveTarget("kitchen", in: config) {
                return key == "kitchen_hub"
            }
            return false
        }())

        // Duplicate aliases pointing at same device.id collapse cleanly (default wins)
        #expect({
            if case .matched(let key, _) = BroadcastCommand.resolveTarget("office", in: config) {
                return key == "office"
            }
            return false
        }())

        // Multiple distinct physical devices matching substring report ambiguity
        #expect({
            if case .ambiguous(let matches) = BroadcastCommand.resolveTarget("living room", in: config) {
                return matches.count == 2
            }
            return false
        }())

        // Not found
        #expect({
            if case .notFound = BroadcastCommand.resolveTarget("garage", in: config) { return true }
            return false
        }())
    }

    // MARK: - Execution & Settings / Subagent / Target Safety

    @MainActor
    @Test func helpListStatusAndZeroArgsFormatExpectedLines() throws {
        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = makeScratchProfile(in: root)
        let config = makeSampleConfig(quietEnabled: true, speakHome: true, speakLocal: true)
        try SpeakerConfigFile(url: profile.settingsURL).write(config)

        let engine = VitruvianSpeakerEngine(profile: profile, local: FakeLocalSpeaker())
        let parts = VitruvianSpeakerCommandLine.Parts.app()
        let voices = [LocalVoice(id: config.effectiveLocalVoice, name: "Ava", language: "en-US", quality: .premium)]

        // --help
        if case .now(let out) = BroadcastCommand.action(for: ["--help"], engine: engine, parts: parts, systemVoices: { voices }) {
            #expect(out.exitCode == 0)
            let joined = out.stdout.joined(separator: "\n")
            #expect(joined.contains("--set-target"))
            #expect(joined.contains("--toggle"))
            #expect(joined.contains("--force"))
            #expect(joined.contains("--status"))
        } else {
            Issue.record("expected .now output for --help")
        }

        // --list
        if case .now(let out) = BroadcastCommand.action(for: ["-l"], engine: engine, parts: parts, systemVoices: { voices }) {
            #expect(out.exitCode == 0)
            #expect(out.stdout.contains { $0.contains("* office") && $0.contains("Home Office") })
            #expect(out.stdout.contains { $0.contains("  kitchen_hub") && $0.contains("Kitchen Display") })
        } else {
            Issue.record("expected .now output for -l")
        }

        // --status during quiet hours vs outside quiet hours
        let midnight = Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: Date())!
        if case .now(let out) = BroadcastCommand.action(for: ["--status"], engine: engine, parts: parts, systemVoices: { voices }, now: midnight) {
            #expect(out.exitCode == 0)
            let text = out.stdout.joined(separator: "\n")
            #expect(text.contains("Speaker Broadcast Status: ENABLED"))
            #expect(text.contains("Active Target: office (Office Speaker, Room: Home Office)"))
            #expect(text.contains("Home Speakers: ON"))
            #expect(text.contains("This Mac: ON (voice: Ava (en-US) · Premium)"))
            #expect(text.contains("Speaks On: Office Speaker (home speaker) + This Mac (voice: Ava (en-US) · Premium)"))
            #expect(text.contains("Quiet Hours: ACTIVE (22:00 - 07:00)"))
        } else {
            Issue.record("expected .now output for --status")
        }

        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        if case .now(let out) = BroadcastCommand.action(for: [], engine: engine, parts: parts, systemVoices: { voices }, now: noon) {
            #expect(out.exitCode == 0)
            let text = out.stdout.joined(separator: "\n")
            #expect(text.contains("Quiet Hours: CONFIGURED (22:00 - 07:00)"))
            #expect(text.contains("Use --help for usage details."))
        } else {
            Issue.record("expected .now output for zero arguments")
        }
    }

    @MainActor
    @Test func toggleAndSetTargetPersistThroughSettingsActionsAndRespectInUseDoor() throws {
        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let standbyProfile = makeScratchProfile(in: root, name: "app")
        let activeProfile = makeScratchProfile(in: root, name: "ext")
        try SpeakerConfigFile(url: activeProfile.settingsURL).write(makeSampleConfig(enabled: true, defaultTarget: "office"))

        let standbyEngine = VitruvianSpeakerEngine(profile: standbyProfile, local: FakeLocalSpeaker())
        let activeEngine = VitruvianSpeakerEngine(profile: activeProfile, local: FakeLocalSpeaker())
        let parts = VitruvianSpeakerCommandLine.Parts.app(
            standsAside: { true },
            inUseSettings: {
                if case .loaded(let cfg) = SpeakerConfigFile(url: activeProfile.settingsURL).read() { return cfg }
                return nil
            },
            inUseEngine: { activeEngine }
        )

        // --off writes to active profile, not standby
        if case .now(let out) = BroadcastCommand.action(for: ["--off"], engine: standbyEngine, parts: parts) {
            #expect(out.exitCode == 0)
            #expect(out.stdout == ["Speaker Broadcast has been DISABLED."])
        } else {
            Issue.record("expected .now output for --off")
        }
        guard case .loaded(let afterOff) = SpeakerConfigFile(url: activeProfile.settingsURL).read() else {
            Issue.record("active config missing after --off")
            return
        }
        #expect(afterOff.enabled == false)
        #expect({
            if case .missing = SpeakerConfigFile(url: standbyProfile.settingsURL).read() { return true }
            return false
        }())

        // --toggle turns it back on
        if case .now(let out) = BroadcastCommand.action(for: ["--toggle"], engine: standbyEngine, parts: parts) {
            #expect(out.exitCode == 0)
            #expect(out.stdout == ["Speaker Broadcast has been ENABLED."])
        } else {
            Issue.record("expected .now output for --toggle")
        }

        // --set-target with loose match updates active config
        if case .now(let out) = BroadcastCommand.action(for: ["--set-target", "kitchen"], engine: standbyEngine, parts: parts) {
            #expect(out.exitCode == 0)
            #expect(out.stdout == ["Default broadcast target set to: kitchen_hub (Kitchen Display)"])
        } else {
            Issue.record("expected .now output for --set-target")
        }
        guard case .loaded(let afterTarget) = SpeakerConfigFile(url: activeProfile.settingsURL).read() else {
            Issue.record("active config missing after --set-target")
            return
        }
        #expect(afterTarget.defaultTarget == "kitchen_hub")

        // Unknown --set-target exits 1 and leaves default unchanged
        if case .now(let out) = BroadcastCommand.action(for: ["-s", "nonexistent"], engine: standbyEngine, parts: parts) {
            #expect(out.exitCode == 1)
            #expect(out.stderr.first?.contains("not found") == true)
        } else {
            Issue.record("expected .now error for unknown --set-target")
        }
    }

    @MainActor
    @Test func speakingRespectsDisabledQuietHoursForceSubagentsAndOneOffTarget() async throws {
        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = makeScratchProfile(in: root)
        let configFile = SpeakerConfigFile(url: profile.settingsURL)

        let homeBroadcaster = FakeHomeBroadcaster()
        let localSpeaker = FakeLocalSpeaker()
        let announcer = Announcer(home: homeBroadcaster, local: localSpeaker, media: SilentMediaPause(), speechLockURL: profile.speechLockURL)
        let engine = VitruvianSpeakerEngine(profile: profile, local: localSpeaker)
        let parts = VitruvianSpeakerCommandLine.Parts.app()

        // 1. Broadcasts disabled -> exit 1 "broadcasting is switched off"
        try configFile.write(makeSampleConfig(enabled: false))
        guard case .headless(_, _, let disabledBody) = BroadcastCommand.action(
            for: ["Tests finished"], engine: engine, parts: parts, announcerOverride: announcer
        ) else {
            Issue.record("expected .headless action when speaking")
            return
        }
        let disabledOut = await disabledBody()
        #expect(disabledOut.exitCode == 1)
        #expect(disabledOut.stderr == ["broadcasting is switched off"])
        #expect(homeBroadcaster.calls.all.isEmpty)

        // 2. Quiet hours holds unless --force
        try configFile.write(makeSampleConfig(enabled: true, quietEnabled: true))
        let lateEvening = Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: Date())!
        guard case .headless(_, _, let quietBody) = BroadcastCommand.action(
            for: ["Quiet test"], engine: engine, parts: parts, announcerOverride: announcer, now: lateEvening
        ) else {
            Issue.record("expected .headless action in quiet hours")
            return
        }
        let quietOut = await quietBody()
        #expect(quietOut.exitCode == 0)
        #expect(quietOut.stderr.contains { $0.contains("Quiet hours active") })
        #expect(homeBroadcaster.calls.all.isEmpty)

        guard case .headless(_, _, let forcedBody) = BroadcastCommand.action(
            for: ["--force", "Urgent alert"], engine: engine, parts: parts, announcerOverride: announcer, now: lateEvening
        ) else {
            Issue.record("expected .headless action with --force")
            return
        }
        let forcedOut = await forcedBody()
        #expect(forcedOut.exitCode == 0)
        #expect(homeBroadcaster.calls.all.last?.text == "Urgent alert")
        #expect(homeBroadcaster.calls.all.last?.force == true)

        // 3. One-off -t/--target speaks on chosen device AND leaves default_target unchanged even on failure
        try configFile.write(makeSampleConfig(enabled: true, defaultTarget: "office", quietEnabled: false))
        homeBroadcaster.failure = SampleFailure("simulated speaker offline")
        guard case .headless(_, _, let oneOffBody) = BroadcastCommand.action(
            for: ["-t", "kitchen", "Oven timer done"], engine: engine, parts: parts, announcerOverride: announcer
        ) else {
            Issue.record("expected .headless action with -t")
            return
        }
        let oneOffOut = await oneOffBody()
        #expect(oneOffOut.exitCode == 1)
        #expect(homeBroadcaster.calls.all.last?.targetKeyOrID == "dev-kitchen")
        #expect(homeBroadcaster.calls.all.last?.targetName == "Kitchen Display")
        guard case .loaded(let persistedAfterFailure) = configFile.read() else {
            Issue.record("config missing after failed -t speak")
            return
        }
        #expect(persistedAfterFailure.defaultTarget == "office")
        homeBroadcaster.failure = nil

        // 4. Subagent suppression (Claude env + Antigravity marker)
        for env in [
            ["CLAUDE_CODE_CHILD_SESSION": "1"],
            ["CLAUDE_CODE_SESSION_ATTENDED": "0"],
            ["CLAUDE_CODE_ENTRYPOINT": "sdk-cli"],
        ] {
            if case .now(let out) = BroadcastCommand.action(
                for: ["Should not speak"], engine: engine, parts: parts, environment: env, announcerOverride: announcer
            ) {
                #expect(out.exitCode == 0)
                #expect(out.stderr == [SubagentDetection.suppressedMessage])
            } else {
                Issue.record("expected immediate .now suppression for \(env)")
            }
        }

        let fakeAppData = root.appendingPathComponent("antigravity-app-data")
        let subagentConv = "sub-conv-123"
        let subagentMarker = fakeAppData
            .appendingPathComponent("brain/parent-conv/.system_generated/subagents/\(subagentConv).json")
        try FileManager.default.createDirectory(at: subagentMarker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: subagentMarker, atomically: true, encoding: .utf8)

        if case .now(let out) = BroadcastCommand.action(
            for: ["Antigravity subagent"],
            engine: engine,
            parts: parts,
            environment: [
                "ANTIGRAVITY_CONVERSATION_ID": subagentConv,
                "ANTIGRAVITY_APP_DATA_DIR": fakeAppData.path,
            ],
            announcerOverride: announcer
        ) {
            #expect(out.exitCode == 0)
            #expect(out.stderr == [SubagentDetection.suppressedMessage])
        } else {
            Issue.record("expected immediate .now suppression for Antigravity subagent")
        }
    }

    // MARK: - Symlink Installer Decisions & Execution

    @Test func symlinkInstallerDecidesCreateReplaceCurrentAndLeaveAloneSafely() throws {
        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let binDir = root.appendingPathComponent(".local/bin", isDirectory: true)
        let extTarget = root.appendingPathComponent("Atrium/Tools/dev.vitruvian.speaker/bin/tool")
        let legacyExtTarget = root.appendingPathComponent("Vitruvian/Tools/dev.vitruvian.homespeaker/bin/tool")
        let appTarget = root.appendingPathComponent("Applications/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker")
        let legacyAppTarget = root.appendingPathComponent("Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        let unrelatedTarget = root.appendingPathComponent("custom/bin/my-speaker-script")

        // Decision unit tests
        #expect(BroadcastCommandLink.decide(existing: .missing, targetPath: extTarget.path, linkDirectory: binDir) == .create)
        #expect(BroadcastCommandLink.decide(existing: .otherFile, targetPath: extTarget.path, linkDirectory: binDir)
            == .leaveAlone(reason: "~/.local/bin/speaker-broadcast exists and is not a symlink"))
        #expect(BroadcastCommandLink.decide(existing: .symlink(destination: extTarget.path, targetExists: true), targetPath: extTarget.path, linkDirectory: binDir)
            == .alreadyCurrent)
        #expect({
            if case .replace = BroadcastCommandLink.decide(existing: .symlink(destination: "/gone/speaker", targetExists: false), targetPath: extTarget.path, linkDirectory: binDir) {
                return true
            }
            return false
        }())
        for previousSpeaker in [legacyExtTarget.path, appTarget.path, legacyAppTarget.path] {
            #expect({
                if case .replace = BroadcastCommandLink.decide(existing: .symlink(destination: previousSpeaker, targetExists: true), targetPath: extTarget.path, linkDirectory: binDir) {
                    return true
                }
                return false
            }(), "expected replacement for previous Speaker target \(previousSpeaker)")
        }
        #expect({
            if case .leaveAlone = BroadcastCommandLink.decide(existing: .symlink(destination: unrelatedTarget.path, targetExists: true), targetPath: extTarget.path, linkDirectory: binDir) {
                return true
            }
            return false
        }())

        // Filesystem integration in scratch home
        for file in [extTarget, appTarget, unrelatedTarget] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\n".write(to: file, atomically: true, encoding: .utf8)
        }
        let logs = RecordedCalls<String>()

        // 1. Creates ~/.local/bin and symlink when missing
        #expect(BroadcastCommandLink.ensureInstalled(home: root, targetPath: appTarget.path, log: { logs.add($0) }) == .create)
        let linkPath = BroadcastCommandLink.linkURL(home: root).path
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)) == appTarget.path)

        // 2. Switching active door replaces Speaker app link with extension tool link
        let switchDecision = BroadcastCommandLink.ensureInstalled(home: root, targetPath: extTarget.path, log: { logs.add($0) })
        #expect({ if case .replace = switchDecision { return true }; return false }())
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)) == extTarget.path)

        // 3. Running again when already pointing to us is a no-op
        #expect(BroadcastCommandLink.ensureInstalled(home: root, targetPath: extTarget.path, log: { logs.add($0) }) == .alreadyCurrent)

        // 4. Dangling symlink gets replaced
        try FileManager.default.removeItem(atPath: linkPath)
        try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: root.appendingPathComponent("missing-target").path)
        let danglingDecision = BroadcastCommandLink.ensureInstalled(home: root, targetPath: extTarget.path, log: { logs.add($0) })
        #expect({ if case .replace = danglingDecision { return true }; return false }())
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)) == extTarget.path)

        // 5. Unrelated symlink is NEVER replaced and logs one explanation line
        try FileManager.default.removeItem(atPath: linkPath)
        try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: unrelatedTarget.path)
        let unrelatedLogsBefore = logs.all.count
        let leaveSymlinkDecision = BroadcastCommandLink.ensureInstalled(home: root, targetPath: extTarget.path, log: { logs.add($0) })
        #expect({ if case .leaveAlone = leaveSymlinkDecision { return true }; return false }())
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)) == unrelatedTarget.path)
        #expect(logs.all.count == unrelatedLogsBefore + 1)

        // 6. Regular file is NEVER replaced and logs one explanation line
        try FileManager.default.removeItem(atPath: linkPath)
        try "custom user file\n".write(toFile: linkPath, atomically: true, encoding: .utf8)
        let fileLogsBefore = logs.all.count
        let leaveFileDecision = BroadcastCommandLink.ensureInstalled(home: root, targetPath: extTarget.path, log: { logs.add($0) })
        #expect({ if case .leaveAlone = leaveFileDecision { return true }; return false }())
        #expect((try? String(contentsOfFile: linkPath, encoding: .utf8)) == "custom user file\n")
        #expect(logs.all.count == fileLogsBefore + 1)

        // 7. Targets inside Trash or DMG volumes are ignored
        #expect(BroadcastCommandLink.ensureInstalled(home: root, targetPath: "/Users/alice/.Trash/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker") == nil)
        #expect(BroadcastCommandLink.ensureInstalled(home: root, targetPath: "/Volumes/Vitruvian Speaker/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker") == nil)
    }

    // MARK: - Instruction Text & Legacy Migration

    @Test func instructionTextAndLegacyMigration() throws {
        #expect(!CodingAgent.broadcastInstruction.contains("vitruvian-speaker-broadcast"))
        #expect(!CodingAgent.broadcastInstruction.contains("home-speaker-broadcast"))
        #expect(!CodingAgent.broadcastInstruction.contains("speaker_broadcast.json"))
        #expect(CodingAgent.broadcastInstruction.contains("speaker-broadcast \"<summary>\""))
        #expect(CodingAgent.broadcastInstruction.contains("speaker-broadcast --on"))
        #expect(CodingAgent.broadcastInstruction.contains("--off"))
        #expect(CodingAgent.broadcastInstruction.contains("--set-target <room>"))
        #expect(CodingAgent.broadcastInstruction.contains("speaker-broadcast --help"))

        // Existing legacy detections still match
        let oldVitruvianLine = "- Follow the `vitruvian-speaker-broadcast` skill: Accompany top-level conversational responses to the user with a concise spoken broadcast (1-2 sentences) by executing the CLI tool `speaker-broadcast \"<summary>\"` (never run `speaker-broadcast` from a background subagent or a delegated `claude -p` helper call). Always use the CLI rather than manual `home_mcp` calls with device IDs, because `speaker-broadcast` dynamically resolves the live `default_target` from `~/.gemini/speaker_broadcast.json`, checks quiet hours, and verifies enabled status on every execution without caching state. When the user asks to turn speaker broadcasts on/off or change the target room, update `~/.gemini/speaker_broadcast.json` (or run `speaker-broadcast --set-target <room>`) and confirm."
        let oldHomeSpeakerLine = "- Follow the `home-speaker-broadcast` skill: Always run `speaker-broadcast` and update `~/.gemini/speaker_broadcast.json` to change the room."

        #expect(AgentIntegration.mentionsBroadcastInstruction(oldVitruvianLine))
        #expect(AgentIntegration.mentionsBroadcastInstruction(oldHomeSpeakerLine))
        #expect(AgentIntegration.mentionsBroadcastInstruction(CodingAgent.broadcastInstruction))

        // Mixed/duplicate old wording block is replaced once with no duplicate left behind
        let mixedOldBlock = "# Header\n\(oldVitruvianLine)\n\(oldHomeSpeakerLine)\n# Footer\n"
        let migratedOnce = try #require(AgentIntegration.migratingBroadcastInstruction(in: mixedOldBlock))
        #expect(migratedOnce == "# Header\n\(CodingAgent.broadcastInstruction)\n# Footer\n")
        #expect(!migratedOnce.contains("vitruvian-speaker-broadcast"))
        #expect(!migratedOnce.contains("speaker_broadcast.json"))
        #expect(migratedOnce.components(separatedBy: CodingAgent.broadcastInstruction).count == 2)
        #expect(AgentIntegration.migratingBroadcastInstruction(in: migratedOnce) == nil, "already current: idempotent")

        let root = try makeScratchDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let integration = AgentIntegration(home: root, executablePath: "/Applications/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker")

        // addBroadcastInstruction replaces old wording in-place without adding a second copy
        let geminiAgents = root.appendingPathComponent(".gemini/AGENTS.md")
        try FileManager.default.createDirectory(at: geminiAgents.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Header\n\(oldVitruvianLine)\n# Footer\n".write(to: geminiAgents, atomically: true, encoding: .utf8)

        try integration.addBroadcastInstruction(for: .antigravity)
        let afterAdd = try String(contentsOf: geminiAgents, encoding: .utf8)
        #expect(afterAdd.hasPrefix("# Header\n"))
        #expect(afterAdd.hasSuffix("\n# Footer\n"))
        #expect(!afterAdd.contains("speaker_broadcast.json"))
        #expect(!afterAdd.contains("vitruvian-speaker-broadcast"))
        #expect(afterAdd.components(separatedBy: CodingAgent.broadcastInstruction).count == 2)

        // migrateBroadcastInstructions removes managed instruction lines (legacy + standalone) for
        // plugin-backed agents and preserves custom user-written wording.
        let claudeMd = root.appendingPathComponent(".claude/CLAUDE.md")
        try FileManager.default.createDirectory(at: claudeMd.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Personal\n\(oldHomeSpeakerLine)\n\(CodingAgent.broadcastInstruction)\nKeep this note.\n"
            .write(to: claudeMd, atomically: true, encoding: .utf8)

        let geminiMd = root.appendingPathComponent(".gemini/GEMINI.md")
        try "\(oldVitruvianLine)\n".write(to: geminiMd, atomically: true, encoding: .utf8)

        let openCodeMd = root.appendingPathComponent(".config/opencode/AGENTS.md")
        try FileManager.default.createDirectory(at: openCodeMd.deletingLastPathComponent(), withIntermediateDirectories: true)
        let customInstruction = "Always announce milestones with speaker-broadcast directly."
        try "\(customInstruction)\n".write(to: openCodeMd, atomically: true, encoding: .utf8)

        integration.migrateBroadcastInstructions()

        #expect(try String(contentsOf: claudeMd, encoding: .utf8) == "# Personal\nKeep this note.\n")
        #expect(try String(contentsOf: geminiMd, encoding: .utf8) == "")
        #expect(try String(contentsOf: geminiAgents, encoding: .utf8) == "# Header\n# Footer\n")
        #expect(try String(contentsOf: openCodeMd, encoding: .utf8) == "\(customInstruction)\n")
    }

    // MARK: - SpeakerSkill Parity & Invocation Routing

    @Test func speakerSkillCommandsMatchOptionTableAndExamplesParse() throws {
        let generated = SpeakerSkill.commandsAndOptionsSection()
        let helpText = BroadcastCommand.helpLines().joined(separator: "\n")

        for spec in BroadcastCommand.optionSpecs {
            let expectedToken = spec.isPositional ? "speaker-broadcast \(spec.syntax)" : spec.syntax
            #expect(generated.contains("`\(expectedToken)`"), "skill section missing \(expectedToken)")
            #expect(helpText.contains(spec.syntax), "help text missing \(spec.syntax)")
        }

        // Extract every `speaker-broadcast ...` invocation inside fenced ```sh blocks in SKILL.md
        let markdown = SpeakerSkill.markdown()
        #expect(markdown.contains(generated))
        let lines = markdown.components(separatedBy: "\n")
        var inShellFence = false
        var commandLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```sh") {
                inShellFence = true
                continue
            }
            if inShellFence && trimmed.hasPrefix("```") {
                inShellFence = false
                continue
            }
            if inShellFence && trimmed.hasPrefix("speaker-broadcast") {
                commandLines.append(trimmed)
            }
        }
        #expect(commandLines.count >= 9)
        for line in commandLines {
            let tokens = Self.tokenizeShellWords(line)
            let args = Array(tokens.dropFirst())
            switch BroadcastCommand.parse(args) {
            case .failure(let err):
                Issue.record("Skill example '\(line)' failed to parse: \(err)")
            case .success:
                break
            }
        }
    }

    @Test func invocationArgumentsAndShortForceFlagWork() throws {
        #expect(BroadcastCommand.invocationArguments(argv: ["/Users/a/.local/bin/speaker-broadcast", "--status"]) == ["--status"])
        #expect(BroadcastCommand.invocationArguments(argv: ["/Applications/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker", "--broadcast-cli", "-f", "Hello"]) == ["-f", "Hello"])
        #expect(BroadcastCommand.invocationArguments(argv: ["/Applications/Vitruvian Speaker.app/Contents/MacOS/VitruvianSpeaker", "--help"]) == nil)
        #expect(BroadcastCommand.invocationArguments(argv: ["/Users/a/Library/Application Support/Vitruvian/Tools/dev.vitruvian.speaker/bin/tool"]) == nil)

        #expect(try BroadcastCommand.parse(["-f", "Urgent", "alert"]).get()
            == .speak(message: "Urgent alert", target: nil, force: true))
    }

    private static func tokenizeShellWords(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inDoubleQuote = false
        for ch in line {
            if ch == "\"" {
                inDoubleQuote.toggle()
            } else if ch == " " && !inDoubleQuote {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}
