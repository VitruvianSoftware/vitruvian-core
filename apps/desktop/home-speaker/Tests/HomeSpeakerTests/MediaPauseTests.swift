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

/// Stands in for osascript: answers each script by what it is, and records
/// every script it was asked to run.
final class FakeRunner: ScriptRunner, @unchecked Sendable {
    var activeTabs: Result<String, ScriptFailure> = .success("")
    var allTabs: Result<String, ScriptFailure> = .success("")
    var spotify: Result<String, ScriptFailure> = .success("")
    private let lock = NSLock()
    private var _ran: [String] = []
    var ran: [String] { lock.withLock { _ran } }

    func run(_ source: String) async -> Result<String, ScriptFailure> {
        lock.withLock { _ran.append(source) }
        if source.contains("{active tab of w}") { return activeTabs }
        if source.contains("tabs of w") { return allTabs }
        if source.contains("tell application \"Spotify\"") && source.contains("pause") { return spotify }
        return .success("")
    }
}

@Suite struct MediaPauseLogicTests {
    @Test func holdCoversTheChimeTheSpeechAndTheExtra() {
        #expect(AnnouncementTiming.seconds(for: "", extra: 0) == 3, "never shorter than the chime")
        let twentyFive = Array(repeating: "word", count: 25).joined(separator: " ")
        #expect(AnnouncementTiming.seconds(for: twentyFive, extra: 1) == 2.5 + 10 + 1)
        let huge = Array(repeating: "word", count: 5000).joined(separator: " ")
        #expect(AnnouncementTiming.seconds(for: huge, extra: 10) == 120, "a runaway estimate is capped")
    }

    @Test func audioProcessesMapToThePlayersThatOwnThem() {
        let ids: Set = ["com.google.Chrome.helper", "com.spotify.client", "com.apple.WebKit.GPU", "us.zoom.xos"]
        let off = MediaPlayer.players(producing: ids, safariRunning: false)
        #expect(off.players == [.chrome, .spotify])
        #expect(off.unsupported == ["us.zoom.xos"], "Zoom is reported, never guessed at")
        // WebKit audio is Safari's only when Safari is running; Mail uses WebKit too.
        #expect(MediaPlayer.players(producing: ids, safariRunning: true).players.contains(.safari))
    }

    @Test func pauseOutputParsesToHandlesOrTheAppsRefusal() throws {
        #expect(try MediaScripts.parse("1:2,3:4,", separator: ",").get() == ["1:2", "3:4"])
        let off = MediaScripts.parse("ERR:Executing JavaScript through AppleScript is turned off.", separator: ",")
        guard case .failure(let e) = off else { Issue.record("an ERR line must be a failure"); return }
        #expect(MediaPauseCoordinator.explain(e.message) == "turn on View › Developer › Allow JavaScript from Apple Events")
    }

    @Test func scriptsEscapeWhatTheyEmbed() {
        let s = MediaScripts.quickTimeResume(handles: ["my \"clip\".mov"])
        #expect(s.contains("document \"my \\\"clip\\\".mov\""), "a quote in a file name must not end the AppleScript string")
    }
}

@MainActor
@Suite(.serialized) struct MediaPauseCoordinatorTests {
    func make(_ runner: FakeRunner, audio: Set<String>) -> MediaPauseCoordinator {
        MediaPauseCoordinator(
            controller: MediaController(runner: runner),
            audio: { audio },
            safariRunning: { false })
    }

    @Test func nothingPlayingMeansNothingPausedOrResumed() async {
        let runner = FakeRunner()
        let c = make(runner, audio: [])
        await c.pause(for: 5)
        #expect(!c.isHolding)
        #expect(runner.ran.isEmpty, "no app is scripted when nothing makes sound")
    }

    @Test func pausesThePlayingTabAndResumesExactlyIt() async throws {
        let runner = FakeRunner()
        runner.activeTabs = .success("7:42,")
        let c = make(runner, audio: ["com.google.Chrome.helper"])
        await c.pause(for: 0.3)
        #expect(c.isHolding)
        #expect(c.lastReport == "Paused Google Chrome.")
        try await Task.sleep(for: .milliseconds(700))
        #expect(!c.isHolding, "resumed once the hold ran out")
        #expect(runner.ran.last?.contains("tab id 42 of window id 7") == true, "resumes the tab it paused, not every tab")
    }

    @Test func aBurstOfAnnouncementsPausesOnceAndResumesOnce() async throws {
        let runner = FakeRunner()
        runner.activeTabs = .success("1:2,")
        let c = make(runner, audio: ["com.google.Chrome.helper"])
        await c.pause(for: 0.3)
        await c.pause(for: 0.9)   // a second message arrives mid-announcement
        try await Task.sleep(for: .milliseconds(500))
        #expect(c.isHolding, "the second announcement extended the hold")
        try await Task.sleep(for: .milliseconds(800))
        #expect(!c.isHolding)
        #expect(runner.ran.filter { $0.contains("{active tab of w}") }.count == 1, "paused once")
        #expect(runner.ran.filter { $0.contains("hsPaused") && $0.contains("tab id") }.count == 1, "resumed once")
    }

    @Test func aBackgroundTabIsFoundWhenTheActiveOnesAreSilent() async {
        let runner = FakeRunner()
        runner.activeTabs = .success("")
        runner.allTabs = .success("3:9,")
        let c = make(runner, audio: ["com.google.Chrome.helper"])
        await c.pause(for: 30)
        #expect(c.isHolding)
        await c.resumeNow()
    }

    @Test func chromeWithJavaScriptOffSaysHowToFixIt() async {
        let runner = FakeRunner()
        let off = ScriptFailure("Executing JavaScript through AppleScript is turned off.")
        runner.activeTabs = .success("ERR:" + off.message)
        runner.allTabs = .success("ERR:" + off.message)
        let c = make(runner, audio: ["com.google.Chrome.helper"])
        await c.pause(for: 5)
        #expect(!c.isHolding)
        #expect(c.lastReport?.contains("Allow JavaScript from Apple Events") == true)
    }

    @Test func aFailedAnnouncementResumesAtOnce() async {
        let runner = FakeRunner()
        runner.spotify = .success("1")
        let c = make(runner, audio: ["com.spotify.client"])
        await c.pause(for: 60)
        #expect(c.isHolding)
        await c.resumeNow()
        #expect(!c.isHolding)
        #expect(runner.ran.last?.contains("if player state is paused then play") == true)
    }
}

@MainActor
@Suite(.serialized) struct MediaPauseSpeedTests {
    /// With Chrome's JavaScript setting off every tab refuses; walking all
    /// 217 of James's tabs to collect that would take seconds.
    @Test func aBrowserThatRefusesIsNotWalkedTabByTab() async {
        let runner = FakeRunner()
        runner.activeTabs = .success("ERR:Executing JavaScript through AppleScript is turned off.")
        let c = MediaPauseCoordinator(controller: MediaController(runner: runner),
                                      audio: { ["com.google.Chrome.helper"] }, safariRunning: { false })
        await c.pause(for: 5)
        #expect(!runner.ran.contains { $0.contains("tabs of w") }, "a browser-wide refusal must not trigger the every-tab pass")
    }

    /// A slow app must not hold up the others.
    @Test func playersArePausedAtTheSameTime() async {
        final class SlowChrome: ScriptRunner, @unchecked Sendable {
            func run(_ source: String) async -> Result<String, ScriptFailure> {
                if source.contains("Google Chrome") { try? await Task.sleep(for: .milliseconds(600)); return .success("") }
                if source.contains("Spotify") && source.contains("pause") { return .success("1") }
                return .success("")
            }
        }
        let c = MediaPauseCoordinator(controller: MediaController(runner: SlowChrome()),
                                      audio: { ["com.google.Chrome.helper", "com.spotify.client"] }, safariRunning: { false })
        let start = Date()
        await c.pause(for: 5)
        // Two sequential Chrome passes would take 1.2 s before Spotify even started.
        #expect(Date().timeIntervalSince(start) < 1.5)
        #expect(c.isHolding)
        await c.resumeNow()
    }
}
