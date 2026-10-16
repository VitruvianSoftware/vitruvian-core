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
import Foundation
import Testing
@testable import HomeSpeakerCore

// Guards for the messages HomeSpeaker's processes send each other, and for
// "is anything alive to put the volume back". The app keeps today's names, so
// a hook or `--say` from an older install still reaches it. The extension
// sends every message under its own names, so a hook of the extension's
// never pauses the app's music or hands the app a volume to put back.
//
// Names are only compared here. Every message a test posts or listens for is
// under a prefix of its own (`test.<uuid>.homespeaker`), never under the
// app's or the extension's, so a HomeSpeaker running on this Mac hears none.

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("homespeaker-messages-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A message prefix no real app or extension on this Mac listens on.
private func testPrefix() -> String { "test.\(UUID().uuidString).homespeaker" }

private func testProfile(in root: URL) -> HomeSpeakerProfile {
    .extension(dataFolder: root.appendingPathComponent("data"), toolFolder: nil, messagePrefix: testPrefix())
}

/// The name each message type really posts and listens under for `profile`,
/// in the order of `HomeSpeakerMessage.allCases`.
private func namesUsed(by profile: HomeSpeakerProfile) -> [String] {
    [
        MediaPauseRequest.notificationName(for: profile),
        VolumeRestoreRequest.notificationName(for: profile),
        SignOutNotice.notificationName(for: profile),
        CredentialsChangedNotice.notificationName(for: profile),
        ChatMonitorControlNotice.notificationName(for: profile),
    ].map(\.rawValue)
}

/// This Mac's speech, made silent.
private struct SilentLocal: LocalSpeaking {
    func speak(_ text: String, voiceID: String) async throws {}
}

@Suite struct MessageNamesTests {
    @Test func theAppsNamesAreTodays() {
        let today = [
            "com.vitruviansoftware.homespeaker.media-pause",
            "com.vitruviansoftware.homespeaker.volume-restore",
            "com.vitruviansoftware.homespeaker.signed-out",
            "com.vitruviansoftware.homespeaker.credentials-changed",
            "com.vitruviansoftware.homespeaker.chat-monitor-control",
        ]
        let app = HomeSpeakerProfile.app()
        #expect(namesUsed(by: app) == today)
        #expect(HomeSpeakerMessage.allCases.map { app.messageName($0).rawValue } == today)
    }

    @Test func theExtensionNeverPostsUnderTheAppsNames() throws {
        let ext = HomeSpeakerProfile.extension(dataFolder: try scratchDir(), toolFolder: nil)
        let names = namesUsed(by: ext)
        #expect(names.count == HomeSpeakerMessage.allCases.count)
        for name in names {
            #expect(name.hasPrefix("dev.vitruvian.homespeaker."), "\(name) is not the extension's")
            #expect(!name.hasPrefix("com.vitruviansoftware.homespeaker"), "\(name) is the app's")
        }
        #expect(Set(names).count == names.count, "two messages share a name")
        #expect(Set(names).isDisjoint(with: namesUsed(by: .app())))

        // A test's own prefix is used for every message too.
        let test = testProfile(in: try scratchDir())
        for name in namesUsed(by: test) {
            #expect(name.hasPrefix(test.messagePrefix + "."), "\(name) ignores the profile")
        }
    }

    @Test func aHeldLockIsSeen() throws {
        let url = try scratchDir().appendingPathComponent("running.lock")
        #expect(!LiveLock.isHeld(at: url), "no file, no holder")
        let lock = try LiveLock.hold(at: url)
        #expect(LiveLock.isHeld(at: url))
        #expect(LiveLock.isHeld(at: url), "looking does not take it from the holder")
        #expect(throws: (any Error).self) { try LiveLock.hold(at: url) }
        lock.release()
    }

    @Test func aReleasedLockIsNot() throws {
        let url = try scratchDir().appendingPathComponent("running.lock")
        let lock = try LiveLock.hold(at: url)
        lock.release()
        #expect(!LiveLock.isHeld(at: url))
        #expect(!LiveLock.isHeld(at: url), "looking must let go again")
        // And it can be held again, by whoever starts next.
        let again = try LiveLock.hold(at: url)
        #expect(LiveLock.isHeld(at: url))
        again.release()
    }

    /// `isHeld` takes the lock for a moment to look. A process starting at
    /// that moment must still get it: `hold` waits a moment and tries again.
    /// No timer: the looker lets go the first time `hold` finds it busy, so
    /// the retry is certain to happen and certain to succeed.
    @Test func aProcessStartingWhileSomeoneLooksStillHoldsIt() throws {
        let url = try scratchDir().appendingPathComponent("running.lock")
        _ = try LiveLock.hold(at: url).release()
        // Someone looking: the lock taken on a file description of its own,
        // as `isHeld` takes it.
        let looker = open(url.path, O_RDONLY | O_CLOEXEC)
        try #require(looker >= 0)
        try #require(flock(looker, LOCK_EX | LOCK_NB) == 0)
        defer { close(looker) }
        var busyCalls = 0
        let lock = try LiveLock.hold(
            at: url, retries: LiveLock.retries, wait: LiveLock.retryWait,
            onBusy: { _ in
                busyCalls += 1
                if busyCalls == 1 { flock(looker, LOCK_UN) }
            })
        #expect(busyCalls == 1, "it found the lock taken once, let the look finish, and got it")
        #expect(LiveLock.isHeld(at: url))
        lock.release()
    }

    /// With no retries a lock taken for a look is a refusal: the failure
    /// the wait above exists to avoid.
    @Test func withNoRetriesALockTakenForALookRefusesAtOnce() throws {
        let url = try scratchDir().appendingPathComponent("running.lock")
        _ = try LiveLock.hold(at: url).release()
        let looker = open(url.path, O_RDONLY | O_CLOEXEC)
        try #require(looker >= 0)
        try #require(flock(looker, LOCK_EX | LOCK_NB) == 0)
        defer { close(looker) }
        var busyCalls = 0
        #expect(throws: POSIXError.self) {
            _ = try LiveLock.hold(
                at: url, retries: 0, wait: LiveLock.retryWait, onBusy: { _ in busyCalls += 1 })
        }
        #expect(busyCalls == 0, "no retry means no wait")
        do {
            _ = try LiveLock.hold(at: url, retries: 0, wait: 0, onBusy: { _ in })
            Issue.record("expected EWOULDBLOCK")
        } catch let error as POSIXError {
            #expect(error.code == .EWOULDBLOCK)
        }
    }

    /// The wait is short: a real holder still refuses a second one, soon.
    @Test func aRealHolderStillRefusesASecondOneSoon() throws {
        let url = try scratchDir().appendingPathComponent("running.lock")
        let holder = try LiveLock.hold(at: url)
        let started = Date()
        #expect(throws: (any Error).self) { try LiveLock.hold(at: url) }
        #expect(Date().timeIntervalSince(started) < 2, "a real holder is refused within moments")
        holder.release()
    }

    @Test func canRestoreAsksTheLockForTheExtension() async throws {
        let profile = testProfile(in: try scratchDir())
        let lockURL = try #require(profile.liveLockURL)
        let theApp: [HomeSpeakerProfile.RunningApp] = [(HomeSpeakerProfile.appBundleID, .accessory)]

        #expect(await VolumeRestoreRequest.canRestore(profile: profile, runningApps: { theApp }) == false,
                "the app running is no one to put the extension's volume back")
        let lock = try LiveLock.hold(at: lockURL)
        #expect(await VolumeRestoreRequest.canRestore(profile: profile, runningApps: { [] }) == true)
        lock.release()
        #expect(await VolumeRestoreRequest.canRestore(profile: profile, runningApps: { theApp }) == false)
    }

    @Test func canRestoreAsksTheRunningAppForTheApp() async throws {
        // Today's paths under a scratch home; no message is posted.
        let profile = HomeSpeakerProfile.app(home: try scratchDir())
        let theApp: [HomeSpeakerProfile.RunningApp] = [(HomeSpeakerProfile.appBundleID, .accessory)]
        #expect(await VolumeRestoreRequest.canRestore(profile: profile, runningApps: { theApp }))
        #expect(await VolumeRestoreRequest.canRestore(profile: profile, runningApps: { [] }) == false)
        #expect(profile.ownerRunning(runningApps: { theApp }))
        #expect(!profile.ownerRunning(runningApps: { [(HomeSpeakerProfile.appBundleID, .prohibited)] }),
                "a command-line run of the app is not the app")
    }

    @Test func theExtensionsOwnerIsItsLock() throws {
        let profile = testProfile(in: try scratchDir())
        let theApp: [HomeSpeakerProfile.RunningApp] = [(HomeSpeakerProfile.appBundleID, .accessory)]
        #expect(!profile.ownerRunning(runningApps: { theApp }))
        let lock = try LiveLock.hold(at: try #require(profile.liveLockURL))
        #expect(profile.ownerRunning(runningApps: { [] }))
        lock.release()
    }

    @Test func theProcessProfileIsTheAppsByDefault() {
        // Nothing in the tests sets it: only the app and the tool's program do.
        #expect(HomeSpeakerProfile.current == .app())
    }
}

/// The engine's coordinators and notices, on a test prefix of their own.
@MainActor
@Suite struct EngineMessagesTests {
    private func engine() throws -> HomeSpeakerEngine {
        HomeSpeakerEngine(
            profile: testProfile(in: try scratchDir()),
            session: URLSession(configuration: .ephemeral), local: SilentLocal())
    }

    @Test func theEngineSpeaksUnderItsOwnNames() throws {
        let engine = try engine()
        let media = try #require(engine.announcer.media as? SharedMediaPause)
        #expect(media.profile == engine.profile, "the announcer would pause under another's names")
        #expect(engine.home.messages == engine.profile, "the speakers would pause under another's names")
        #expect(HomeSpeakerEngine.app.home.messages == nil, "the app's speakers follow the process")
    }

    @Test func listenStartsBothCoordinatorsOnTheProfile() async throws {
        let engine = try engine()
        #expect(MediaPauseRequest.inProcess(for: engine.profile) == nil)
        #expect(await VolumeRestoreRequest.canRestore(profile: engine.profile, runningApps: { [] }) == false)

        let tokens = engine.listen()
        defer { tokens.forEach(DistributedNotificationCenter.default().removeObserver) }
        #expect(tokens.count == 2)
        #expect(MediaPauseRequest.inProcess(for: engine.profile) === engine.mediaPause)
        #expect(VolumeRestoreRequest.inProcess(for: engine.profile) === engine.volumeRestore)
        #expect(await VolumeRestoreRequest.canRestore(profile: engine.profile, runningApps: { [] }),
                "this process puts the volume back itself")
        // The app's side is not touched.
        #expect(MediaPauseRequest.inProcess(for: .app()) !== engine.mediaPause)
        #expect(VolumeRestoreRequest.inProcess(for: .app()) !== engine.volumeRestore)
    }

    @Test func noticesReachTheMonitorOnTheProfilesNames() async throws {
        let engine = try engine()
        let monitor = FakeChatMonitor(running: true)
        let tokens = engine.listenForNotices(monitor: monitor)
        defer { tokens.forEach(DistributedNotificationCenter.default().removeObserver) }
        #expect(tokens.count == 2)

        SignOutNotice.post(chatOnly: false, name: SignOutNotice.notificationName(for: engine.profile))
        for _ in 0..<100 where monitor.calls.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        #expect(monitor.calls == ["stop"])

        engine.config.config.chatMonitor = ChatMonitorConfig(slackEnabled: true)
        CredentialsChangedNotice.post(name: CredentialsChangedNotice.notificationName(for: engine.profile))
        for _ in 0..<100 where monitor.calls.count < 2 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(monitor.calls == ["stop", "start"])
    }
}
