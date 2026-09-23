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

/// A speaker that remembers its volume and every level it was set to.
final class FakeSpeaker: VolumeControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var _percent: Int
    private var _reported: Int
    private var _reportAt = Date.distantPast
    private var _sets: [Int] = []
    var online: Bool
    /// Seconds before a new level is REPORTED -- Google's lag.
    let lag: Double

    init(percent: Int, online: Bool = true, lag: Double = 0) {
        _percent = percent; _reported = percent; self.online = online; self.lag = lag
    }

    /// What the speaker is really at; setting it here is "someone changed it
    /// by hand", reported at once.
    var percent: Int {
        get { lock.withLock { _percent } }
        set { lock.withLock { _percent = newValue; _reported = newValue; _reportAt = .distantPast } }
    }
    var sets: [Int] { lock.withLock { _sets } }

    func volume(of target: SpeakerDevice, structureId: String) async throws -> SpeakerVolume {
        guard !target.isWholeHome else { throw VolumeError.wholeHome }
        let shown = lock.withLock { Date() >= _reportAt ? _percent : _reported }
        return SpeakerVolume(percent: shown, muted: false, online: online)
    }

    func setVolume(_ p: Int, on target: SpeakerDevice, structureId: String) async throws {
        lock.withLock {
            _reported = Date() >= _reportAt ? _percent : _reported
            _percent = p; _sets.append(p); _reportAt = Date().addingTimeInterval(lag)
        }
    }
}

private let office = SpeakerDevice(id: "device@l", type: "GoogleDisplayDevice", name: "Lake Office display")
private let wholeHome = SpeakerDevice(id: "structure@s", type: "Structure", name: "Whole Home")

@Suite struct SpeakerVolumeParsingTests {
    /// The shape `list_home_states` returned for James's speakers.
    static let payload: [String: Any] = ["states": [
        ["id": "device@l", "resourceConnectivityState": "ONLINE",
         "traits": ["Volume": ["state": ["currentVolumePercent": 40, "isMuted": false], "type": "SpeakerDevice"]]],
        ["id": "device@off", "resourceConnectivityState": "OFFLINE",
         "traits": ["Volume": ["state": ["currentVolumePercent": 40], "type": "SpeakerDevice"]]],
        ["id": "device@k", "resourceConnectivityState": "ONLINE", "traits": [:] as [String: Any]],
    ]]

    @Test func readsLevelMuteAndConnectivity() {
        #expect(GoogleHomeClient.parseVolume(Self.payload, deviceId: "device@l") == SpeakerVolume(percent: 40, muted: false, online: true))
    }

    @Test func anOfflineSpeakerIsMarkedOfflineNotTrusted() {
        let v = GoogleHomeClient.parseVolume(Self.payload, deviceId: "device@off")
        #expect(v?.online == false, "its 40 % is the last level it had, not a current one")
    }

    @Test func aSpeakerWithoutVolumeAndAnUnknownIdAreNil() {
        #expect(GoogleHomeClient.parseVolume(Self.payload, deviceId: "device@k") == nil, "Kitchen Home has no Volume trait")
        #expect(GoogleHomeClient.parseVolume(Self.payload, deviceId: "device@nope") == nil)
    }

    /// Regression: a refused action comes back inside an HTTP 200. Broadcast
    /// ignored it and logged the message as spoken.
    @Test func aRefusalInsideA200IsAnError() {
        let refused: [String: Any] = ["homeActionResponses": [["id": "device@l", "error": ["code": 3, "message": "Trait not supported."]]]]
        #expect(GoogleHomeClient.actionError(refused) == "Trait not supported. -- code 3")
        // Seen live: a refusal with no message. The reason code is the only clue.
        let silent: [String: Any] = ["homeActionResponses": [["id": "device@l", "error": [
            "code": 3, "details": [["@type": "type.googleapis.com/google.rpc.ErrorInfo", "reason": "EXECUTION_FAILURE"]],
        ] as [String: Any]]]]
        #expect(GoogleHomeClient.actionError(silent) == "EXECUTION_FAILURE -- code 3")
        #expect(GoogleHomeClient.actionError(["homeActionResponses": [["id": "device@l", "response": [:] as [String: Any]]]]) == nil)
    }

    @Test func configDefaultsAndClamps() {
        var c = SpeakerConfig()
        #expect(!c.effectiveAnnounceVolumeEnabled)
        #expect(c.effectiveAnnounceVolume == 60)
        c.effectiveAnnounceVolume = 150
        #expect(c.effectiveAnnounceVolume == 100)
    }

    @Test func aRestoreRequestSurvivesTheTripBetweenProcesses() {
        let b = VolumeBoost(target: office, structureId: "s", restoreTo: 40, announceLevel: 60)
        let decoded = VolumeRestoreRequest.decode(VolumeRestoreRequest.encode(b, after: 7.5))
        #expect(decoded?.0 == b)
        #expect(decoded?.1 == 7.5)
    }
}

@Suite struct AnnounceVolumeTests {
    @Test func raisesToTheLevelAndRemembersWhereItWas() async {
        let speaker = FakeSpeaker(percent: 40)
        let boost = await AnnounceVolume.prepare(level: 60, target: office, structureId: "s", client: speaker, canRestore: true)
        #expect(boost == VolumeBoost(target: office, structureId: "s", restoreTo: 40, announceLevel: 60))
        #expect(speaker.sets == [60])
    }

    @Test func neverRaisesWhatNothingWillLower() async {
        let speaker = FakeSpeaker(percent: 40)
        #expect(await AnnounceVolume.prepare(level: 60, target: office, structureId: "s", client: speaker, canRestore: false) == nil)
        #expect(speaker.sets.isEmpty, "the menu bar app is not running, so the volume must not change")
    }

    @Test func leavesWholeHomeAndOfflineSpeakersAlone() async {
        let speaker = FakeSpeaker(percent: 40, online: false)
        #expect(await AnnounceVolume.prepare(level: 60, target: office, structureId: "s", client: speaker, canRestore: true) == nil)
        #expect(await AnnounceVolume.prepare(level: 60, target: wholeHome, structureId: "s", client: speaker, canRestore: true) == nil)
        #expect(speaker.sets.isEmpty)
    }

    @Test func alreadyAtTheLevelSetsNothingButStillReports() async {
        let speaker = FakeSpeaker(percent: 60)
        let boost = await AnnounceVolume.prepare(level: 60, target: office, structureId: "s", client: speaker, canRestore: true)
        #expect(speaker.sets.isEmpty)
        #expect(boost?.restoreTo == 60, "reported so a pending restore from a burst is extended")
    }
}

/// Waits for an outcome rather than a fixed time: a slow CI Mac finishes
/// later than a laptop, and a fixed sleep read the result before it existed.
@MainActor
func eventually(within seconds: Double = 5, _ done: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !done(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
}

@MainActor
@Suite(.serialized) struct VolumeRestoreTests {
    @Test func putsTheSpeakerBackAfterTheAnnouncement() async throws {
        let speaker = FakeSpeaker(percent: 60)
        let c = VolumeRestoreCoordinator(client: speaker, confirmTimeout: 0.3, minimumHold: 0.1)
        c.schedule(VolumeBoost(target: office, structureId: "s", restoreTo: 40, announceLevel: 60), after: 0.2)
        #expect(c.isHolding)
        try await eventually { c.lastReport != nil }
        #expect(speaker.percent == 40)
        #expect(!c.isHolding)
    }

    @Test func aVolumeChangedByHandDuringTheAnnouncementIsLeftAlone() async throws {
        let speaker = FakeSpeaker(percent: 60)
        let c = VolumeRestoreCoordinator(client: speaker, confirmTimeout: 0.3, minimumHold: 0.1)
        c.schedule(VolumeBoost(target: office, structureId: "s", restoreTo: 40, announceLevel: 60), after: 0.2)
        speaker.percent = 25   // someone turned it down mid-announcement
        try await eventually { c.lastReport != nil }
        #expect(speaker.percent == 25)
        #expect(speaker.sets.isEmpty)
        #expect(c.lastReport?.contains("changed during the announcement") == true)
    }

    /// A burst: the second announcement read the RAISED level. Restoring to
    /// that would leave the speaker loud; the first level must win.
    @Test func aBurstRestoresTheOriginalLevelOnceAfterTheLast() async throws {
        let speaker = FakeSpeaker(percent: 60)
        let c = VolumeRestoreCoordinator(client: speaker, confirmTimeout: 0.3, minimumHold: 0.1)
        c.schedule(VolumeBoost(target: office, structureId: "s", restoreTo: 40, announceLevel: 60), after: 0.3)
        c.schedule(VolumeBoost(target: office, structureId: "s", restoreTo: 60, announceLevel: 60), after: 0.8)
        try await Task.sleep(for: .milliseconds(500))
        #expect(speaker.percent == 60, "still announcing: not restored at the first deadline")
        try await eventually { c.lastReport != nil }
        #expect(speaker.percent == 40)
        #expect(speaker.sets == [40], "restored exactly once")
    }

    @Test func nothingToRestoreWhenTheSpeakerWasAlreadyAtTheLevel() async {
        let c = VolumeRestoreCoordinator(client: FakeSpeaker(percent: 60), confirmTimeout: 0.3, minimumHold: 0.1)
        c.schedule(VolumeBoost(target: office, structureId: "s", restoreTo: 60, announceLevel: 60), after: 0.1)
        #expect(!c.isHolding)
    }

    /// Regression (measured live): Google reports a new level ~3 s late. A
    /// restore that checked once would see the OLD level, decide someone had
    /// changed it by hand, and leave the speaker at the announcement volume.
    @Test func aLaggingReportDoesNotLeaveTheSpeakerLoud() async throws {
        let speaker = FakeSpeaker(percent: 40, lag: 0.6)
        let boost = await AnnounceVolume.prepare(level: 60, target: office, structureId: "s", client: speaker, canRestore: true)
        let c = VolumeRestoreCoordinator(client: speaker, confirmTimeout: 1.5, minimumHold: 0.1)
        c.schedule(try #require(boost), after: 0.1)   // checked while the report still says 40
        try await eventually { c.lastReport != nil }
        #expect(speaker.sets == [60, 40], "raised, then put back despite the stale first reading")
    }

    /// An announcement straight after a restore reads the raised level (the
    /// report lags) and would take it as the speaker's own volume.
    @Test func anAnnouncementJustAfterARestoreRemembersTheRealLevel() async throws {
        let speaker = FakeSpeaker(percent: 60)
        let c = VolumeRestoreCoordinator(client: speaker, confirmTimeout: 0.3, minimumHold: 0.1)
        c.schedule(VolumeBoost(target: office, structureId: "s", restoreTo: 40, announceLevel: 60), after: 0.1)
        try await eventually { c.lastReport != nil }
        #expect(speaker.percent == 40)
        speaker.percent = 60   // raised again for the next announcement
        // ...whose prepare read a stale 60 as the "own" level:
        c.schedule(VolumeBoost(target: office, structureId: "s", restoreTo: 60, announceLevel: 60), after: 0.1)
        #expect(c.isHolding, "not dropped as 'nothing to restore'")
        try await eventually { speaker.sets.count == 2 }
        #expect(speaker.sets == [40, 40])
        #expect(speaker.percent == 40)
    }
}
