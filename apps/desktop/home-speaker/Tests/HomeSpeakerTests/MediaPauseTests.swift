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
    var mediaSiteTabs: Result<String, ScriptFailure> = .success("")
    var allTabs: Result<String, ScriptFailure> = .success("")
    var spotify: Result<String, ScriptFailure> = .success("")
    private let lock = NSLock()
    private var _ran: [String] = []
    var ran: [String] { lock.withLock { _ran } }

    func run(_ source: String) async -> Result<String, ScriptFailure> {
        lock.withLock { _ran.append(source) }
        if source.contains("{active tab of w}") || source.contains("{current tab of w}") { return activeTabs }
        if source.contains("URL of tabs of w") { return mediaSiteTabs }
        if source.contains("(tabs of w)") { return allTabs }
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
        runner.activeTabs = .success("7:42:www.youtube.com,")
        let c = make(runner, audio: ["com.google.Chrome.helper"])
        await c.pause(for: 0.3)
        #expect(c.isHolding)
        #expect(c.lastReport == "Paused Google Chrome (www.youtube.com).", "names the site, so a Test per service shows which one worked")
        try await Task.sleep(for: .milliseconds(700))
        #expect(!c.isHolding, "resumed once the hold ran out")
        #expect(runner.ran.last?.contains("tab id 42 of window id 7") == true, "resumes the tab it paused, not every tab")
    }

    @Test func aBurstOfAnnouncementsPausesOnceAndResumesOnce() async throws {
        let runner = FakeRunner()
        runner.activeTabs = .success("1:2:www.youtube.com,")
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
        runner.mediaSiteTabs = .success("")
        runner.allTabs = .success("3:9:example.org,")
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
        #expect(!runner.ran.contains { $0.contains("tabs of w") }, "a browser-wide refusal must not trigger the later passes")
    }

    /// A slow app must not hold up the others: Spotify is paused while
    /// Chrome is still working through its passes, not after.
    @Test func playersArePausedAtTheSameTime() async {
        final class SlowChrome: ScriptRunner, @unchecked Sendable {
            let lock = NSLock()
            var spotifyPausedAt: Date?
            var chromeDoneAt: Date?
            func run(_ source: String) async -> Result<String, ScriptFailure> {
                if source.contains("Google Chrome") {
                    try? await Task.sleep(for: .milliseconds(300))
                    lock.withLock { chromeDoneAt = Date() }
                    return .success("")
                }
                if source.contains("Spotify") && source.contains("pause") {
                    lock.withLock { spotifyPausedAt = Date() }
                    return .success("1")
                }
                return .success("")
            }
        }
        let runner = SlowChrome()
        let c = MediaPauseCoordinator(controller: MediaController(runner: runner),
                                      audio: { ["com.google.Chrome.helper", "com.spotify.client"] }, safariRunning: { false })
        await c.pause(for: 5)
        let (spotify, chrome) = runner.lock.withLock { (runner.spotifyPausedAt, runner.chromeDoneAt) }
        #expect(spotify != nil && chrome != nil)
        if let spotify, let chrome { #expect(spotify < chrome, "Spotify waited for Chrome") }
        #expect(c.isHolding)
        await c.resumeNow()
    }
}

@MainActor
@Suite(.serialized) struct MediaPauseBrowserTests {
    /// Netflix in a background tab: found by the media-site pass, so the
    /// slow every-tab pass never runs.
    @Test func aBackgroundStreamingTabIsFoundWithoutWalkingEveryTab() async {
        let runner = FakeRunner()
        runner.activeTabs = .success("")
        runner.mediaSiteTabs = .success("1:5:www.netflix.com,")
        let c = MediaPauseCoordinator(controller: MediaController(runner: runner),
                                      audio: { ["com.google.Chrome.helper"] }, safariRunning: { false })
        await c.pause(for: 30)
        #expect(c.isHolding)
        #expect(c.lastReport == "Paused Google Chrome (www.netflix.com).")
        #expect(!runner.ran.contains { $0.contains("(tabs of w)") }, "the every-tab pass is the last resort")
        await c.resumeNow()
        #expect(runner.ran.last?.contains("tab id 5 of window id 1") == true)
    }

    @Test func theMediaSitePassCoversJamessServices() {
        let script = MediaScripts.chromiumPause("Google Chrome", pass: .mediaSiteTabs)
        for site in ["youtube.com", "netflix.com", "primevideo.com", "amazon.com/gp/video"] {
            #expect(script.contains("u contains \"\(site)\""), "\(site) is not in the media-site pass")
        }
        #expect(script.contains("set urls to URL of tabs of w"), "URLs are read in one Apple Event per window")
    }

    @Test func pausedTabsParseIntoHandlesAndSites() async {
        let runner = FakeRunner()
        runner.activeTabs = .success("1:2:www.youtube.com,3:4:www.primevideo.com,3:9:www.youtube.com,")
        let outcome = await MediaController(runner: runner).pause(.chrome)
        #expect(outcome == .paused(PausedMedia(
            player: .chrome, handles: ["1:2", "3:4", "3:9"], sites: ["www.youtube.com", "www.primevideo.com"])))
    }

    /// The page script's own contract, as it is embedded.
    @Test func thePageScriptReachesShadowRootsAndFramesAndNeverAnswersEmptyAfterPausing() {
        #expect(MediaScripts.pauseJS.contains("e.shadowRoot"))
        #expect(MediaScripts.pauseJS.contains("e.contentDocument"))
        #expect(MediaScripts.pauseJS.contains("location.hostname||'this page'"),
                "a file:// page has no hostname; answering \"\" would mean never resumed")
        #expect(MediaScripts.resumeJS.contains("p.catch"), "a refused play() must not surface as an error")
    }
}

// MARK: - Regressions: media paused but never resumed, or never paused

/// Answers the front-tab pass with each of `answers` in turn, after
/// `delay`, the way a busy browser keeps osascript waiting; records every
/// script, and whether the task running each resume had been cancelled.
final class SlowTabs: ScriptRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String]
    private let delay: Duration
    private var _ran: [String] = []
    private var _resumeCancelled: [Bool] = []
    var ran: [String] { lock.withLock { _ran } }
    var resumeCancelled: [Bool] { lock.withLock { _resumeCancelled } }
    var resumes: [String] { ran.filter(Self.isResume) }
    var frontTabPasses: Int { ran.filter { $0.contains("{active tab of w}") }.count }

    init(_ answers: [String], delay: Duration = .zero) {
        self.answers = answers
        self.delay = delay
    }

    static func isResume(_ s: String) -> Bool { s.contains("data-hs-paused") && s.contains("tab id") }

    func run(_ source: String) async -> Result<String, ScriptFailure> {
        lock.withLock { _ran.append(source) }
        if source.contains("{active tab of w}") {
            if delay > .zero { try? await Task.sleep(for: delay) }
            return .success(lock.withLock { answers.isEmpty ? "" : answers.removeFirst() })
        }
        if Self.isResume(source) {
            lock.withLock { _resumeCancelled.append(Task.isCancelled) }
            // A cancelled task's sleep ends at once: osascript's real wait
            // stands in here.
            try? await Task.sleep(for: .milliseconds(10))
        }
        return .success("")
    }
}

@MainActor
@Suite(.serialized) struct MediaPauseRaceTests {
    func make(_ runner: ScriptRunner) -> MediaPauseCoordinator {
        MediaPauseCoordinator(controller: MediaController(runner: runner),
                              audio: { ["com.google.Chrome.helper"] }, safariRunning: { false })
    }

    /// Two announcements a moment apart: the second used to start its own
    /// pause while the first's osascript still ran, and whichever finished
    /// last replaced what was held -- the other tab was never resumed.
    @Test func overlappingPausesNeverLoseWhatTheFirstPaused() async {
        let runner = SlowTabs(["1:2:www.youtube.com,", "3:4:music.example,"], delay: .milliseconds(300))
        let c = make(runner)
        async let first: Void = c.pause(for: 30)
        async let second: Void = c.pause(for: 30)
        _ = await (first, second)
        #expect(c.isHolding)
        #expect(runner.frontTabPasses == 1, "the second announcement extends the hold; it does not pause again")
        await c.resumeNow()
        #expect(runner.resumes.contains { $0.contains("tab id 2 of window id 1") }, "the first pause's tab is resumed")
        #expect(!c.isHolding)
    }

    /// The broadcast failed while the pause was still running: the resume
    /// used to find nothing held yet, and the pause then held the media
    /// for the whole hold.
    @Test func aResumeDuringAPauseResumesWhatThatPausePaused() async throws {
        let runner = SlowTabs(["1:2:www.youtube.com,"], delay: .milliseconds(300))
        let c = make(runner)
        let pausing = Task { await c.pause(for: 60) }
        try await Task.sleep(for: .milliseconds(50))
        await c.resumeNow()
        await pausing.value
        #expect(!c.isHolding, "left paused for the full minute")
        #expect(runner.resumes.contains { $0.contains("tab id 2 of window id 1") })
    }

    /// The timer's own resume cancelled the task it ran in.
    @Test func theHoldRunningOutResumesWithoutCancellingItself() async throws {
        let runner = SlowTabs(["1:2:www.youtube.com,"])
        let c = make(runner)
        await c.pause(for: 0.2)
        #expect(c.isHolding)
        for _ in 0..<40 where c.isHolding || runner.resumes.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!c.isHolding)
        #expect(runner.resumeCancelled == [false], "the resume ran in a cancelled task")
    }

    /// An extend arriving while the pause is still running is not dropped.
    @Test func anExtendDuringAPauseExtendsWhatItHolds() async throws {
        let runner = SlowTabs(["1:2:www.youtube.com,"], delay: .milliseconds(200))
        let c = make(runner)
        let pausing = Task { await c.pause(for: 0.3) }
        try await Task.sleep(for: .milliseconds(50))
        c.extend(for: 1.5)
        await pausing.value
        try await Task.sleep(for: .milliseconds(700))
        #expect(c.isHolding, "the extend was dropped and the hold ran out early")
        await c.resumeNow()
    }

    @Test func waitUntilReleasedReturnsWhenTheHoldEnds() async {
        let runner = SlowTabs(["1:2:www.youtube.com,"])
        let c = make(runner)
        await c.waitUntilReleased()   // nothing held: at once
        await c.pause(for: 0.2)
        let started = Date()
        await c.waitUntilReleased()
        #expect(!c.isHolding)
        #expect(Date().timeIntervalSince(started) >= 0.1)
        #expect(runner.resumes.count == 1)
    }
}

@MainActor
@Suite(.serialized) struct MediaPauseBrowserSearchTests {
    func make(_ runner: ScriptRunner, audio: Set<String> = ["com.google.Chrome.helper"]) -> MediaPauseCoordinator {
        MediaPauseCoordinator(controller: MediaController(runner: runner), audio: { audio }, safariRunning: { true })
    }

    @Test func thePageScriptPausesOnlyWhatIsAudible() {
        #expect(MediaScripts.pauseJS.contains("!m.paused&&!m.ended&&!m.muted&&m.volume>0"),
                "a muted autoplay preview in the front tab must not count as what was playing")
        #expect(MediaScripts.resumeJS.contains("try{const p=m.play()"), "one element's throw must not stop the rest resuming")
    }

    /// The front tab and a background media tab both playing: both paused,
    /// both resumed. The search used to stop at the front tab.
    @Test func aFrontTabDoesNotHideABackgroundMediaTab() async {
        let runner = FakeRunner()
        runner.activeTabs = .success("1:2:docs.example,")
        runner.mediaSiteTabs = .success("1:9:www.youtube.com,")
        let c = make(runner)
        await c.pause(for: 30)
        #expect(c.lastReport == "Paused Google Chrome (docs.example, www.youtube.com).")
        #expect(!runner.ran.contains { $0.contains("(tabs of w)") }, "something was found: no every-tab walk")
        await c.resumeNow()
        let resume = runner.ran.last ?? ""
        #expect(resume.contains("tab id 2 of window id 1") && resume.contains("tab id 9 of window id 1"))
    }

    /// One tab's error (a chrome:// page in front) used to read as Chrome
    /// refusing, and stopped the search for the tab that was playing.
    @Test func oneTabsErrorDoesNotStopTheSearch() async {
        let runner = FakeRunner()
        runner.activeTabs = .success("ERR:Can't get the JavaScript result.")
        runner.mediaSiteTabs = .success("2:5:www.youtube.com,")
        let c = make(runner)
        await c.pause(for: 30)
        #expect(c.isHolding)
        #expect(c.lastReport == "Paused Google Chrome (www.youtube.com).")
        #expect(!c.lastPauseHadProblems)
        await c.resumeNow()
    }

    @Test func aTabThatAnswersMissingValueIsNotAPause() {
        for script in [MediaScripts.chromiumPause("Google Chrome", pass: .activeTabs), MediaScripts.safariPause(pass: .allTabs)] {
            #expect(script.contains("if r is not missing value then"),
                    "a sleeping tab's `missing value` read as paused and ended the search")
        }
        #expect(MediaScripts.chromiumPause("Google Chrome", pass: .mediaSiteTabs).contains("if u is not missing value then"))
    }

    /// Arc's window and tab ids are UUIDs: unquoted, the resume script did
    /// not compile, so Arc never resumed.
    @Test func arcsTextIdsAreQuotedAndResumed() async {
        let w = "8F3A1B2C-0D4E-4F5A-9B6C-7D8E9F0A1B2C", t = "1A2B3C4D-AAAA-BBBB-CCCC-DDDDEEEEFFFF"
        let runner = FakeRunner()
        runner.activeTabs = .success("\(w):\(t):www.youtube.com,")
        let c = make(runner, audio: ["company.thebrowser.Browser.helper"])
        await c.pause(for: 30)
        #expect(c.lastReport == "Paused Arc (www.youtube.com).")
        await c.resumeNow()
        let resume = runner.ran.last ?? ""
        #expect(resume.contains("tell application \"Arc\""))
        #expect(resume.contains("tab id \"\(t)\" of window id \"\(w)\""))
    }

    @Test func aResumeFindsATabDraggedToAnotherWindow() {
        let script = MediaScripts.chromiumResume("Google Chrome", handles: ["7:42"])
        #expect(script.contains("execute (tab id 42 of window id 7)"))
        #expect(script.contains("repeat with w in windows") && script.contains("execute (tab id 42 of w)"),
                "no look in the other windows when the tab moved")
    }

    @Test func anOddHandleNeverBecomesScript() {
        #expect(MediaScripts.idLiteral("42") == "42")
        #expect(MediaScripts.idLiteral("ab-12_C") == "\"ab-12_C\"")
        #expect(MediaScripts.idLiteral("1\" & (do shell script \"x\") & \"") == nil)
        #expect(MediaScripts.idLiteral("") == nil)
        let script = MediaScripts.chromiumResume("Google Chrome", handles: ["1:2\" & do shell script \"say hi"])
        #expect(!script.contains("do shell script"))
    }

    /// Safari used to look only at the front tab of each window.
    @Test func safariFindsABackgroundTabAndResumesIt() async {
        let runner = FakeRunner()
        runner.activeTabs = .success("")
        runner.mediaSiteTabs = .success("")
        runner.allTabs = .success("12:3:www.example.org,")
        let c = make(runner, audio: ["com.apple.WebKit.GPU"])
        await c.pause(for: 30)
        #expect(c.lastReport == "Paused Safari (www.example.org).")
        #expect(runner.ran.contains { $0.contains("tell application \"Safari\"") && $0.contains("(tabs of w)") })
        await c.resumeNow()
        #expect(runner.ran.last?.contains("in tab 3 of window id 12") == true)
    }

    @Test func safariPassesLookPastTheFrontTab() {
        #expect(MediaScripts.safariPause(pass: .activeTabs).contains("{current tab of w}"))
        #expect(MediaScripts.safariPause(pass: .mediaSiteTabs).contains("set urls to URL of tabs of w"))
        #expect(MediaScripts.safariPause(pass: .allTabs).contains("repeat with t in (tabs of w)"))
        #expect(MediaScripts.safariPause(pass: .allTabs).contains("(index of t)"), "a Safari tab is window id and index")
    }

    /// The person switched tabs during the announcement: the resume tries
    /// the paused tab, then every tab of that window, then every window.
    @Test func safariResumesEvenAfterTheFrontTabChanged() {
        let script = MediaScripts.safariResume(handles: ["12:3"])
        #expect(script.contains("do JavaScript"))
        #expect(script.contains("in tab 3 of window id 12"))
        #expect(script.contains("set ts to tabs of window id 12"), "no sweep of the window when the tab moved")
        #expect(script.contains("repeat with w in windows"), "no sweep of every window when the window closed")
        #expect(!script.contains("current tab"), "resuming whatever tab is in front now resumes the wrong one")
        #expect(MediaScripts.resumeJS.contains("[data-hs-paused]"), "only what we paused is played")
    }
}

// MARK: - Frozen tabs

/// A suspended tab (Workona, a discarded background tab) never answers an
/// Apple Event. AppleScript waited 120 seconds, the runner killed osascript
/// at 8, and the stdout that named the tab ALREADY paused was lost: the
/// video stayed paused for good and the report read "Could not pause
/// Google Chrome: ."
@MainActor
@Suite(.serialized) struct MediaPauseFrozenTabTests {
    static let pauseScripts = MediaScripts.TabPass.allCases.flatMap { pass in
        [MediaScripts.chromiumPause("Google Chrome", pass: pass), MediaScripts.safariPause(pass: pass)]
    }
    static let resumeScripts = [
        MediaScripts.chromiumResume("Google Chrome", handles: ["1:2"]),
        MediaScripts.safariResume(handles: ["1:2"]),
        MediaScripts.safariResume(handles: ["1"]),
        MediaScripts.safariResume(handles: ["gone"]),
    ]

    private func count(_ needle: String, in s: String) -> Int { s.components(separatedBy: needle).count - 1 }

    @Test func everyPageScriptCallWaitsOneSecondAtMost() {
        for script in Self.pauseScripts + Self.resumeScripts {
            let calls = count("javascript \"", in: script) + count("do JavaScript \"", in: script)
            #expect(calls > 0)
            #expect(count("with timeout of 1 second", in: script) == calls,
                    "a call outside a 1-second timeout waits 120 seconds on a frozen tab")
            #expect(count("end timeout", in: script) == calls)
        }
    }

    @Test func aTabThatTimesOutIsNotAnError() {
        for script in Self.pauseScripts {
            #expect(script.contains("on error msg number errNum"))
            #expect(script.contains("if errNum is not -1712 and firstErr is \"\" then set firstErr to msg"),
                    "a frozen tab must not read as the browser refusing")
        }
    }

    @Test func eachPauseIsLoggedTheMomentItHappens() {
        #expect(MediaScripts.chromiumPause("Google Chrome", pass: .allTabs)
            .contains("log \"PAUSED:\" & (id of w) & \":\" & (id of t) & \":\" & r"))
        #expect(MediaScripts.safariPause(pass: .allTabs)
            .contains("log \"PAUSED:\" & (id of w) & \":\" & (index of t) & \":\" & r"))
    }

    @Test func pausedTabsLoggedBeforeTheDeadlineAreKept() {
        let stderr = "PAUSED:1:2:www.youtube.com\nPAUSED:3:4:www.netflix.com\n"
        // Killed at the deadline: SIGTERM, nothing on stdout.
        #expect(OSAScriptRunner.result(status: 15, timedOut: true, stdout: "", stderr: stderr)
            == .success("1:2:www.youtube.com,3:4:www.netflix.com,"))
        // Failed for another reason after pausing.
        #expect(OSAScriptRunner.result(status: 1, timedOut: false, stdout: "",
                                       stderr: "PAUSED:1:2:www.youtube.com\nexecution error: boom (-1)")
            == .success("1:2:www.youtube.com,"))
        // Finished normally: stdout is the answer.
        #expect(OSAScriptRunner.result(status: 0, timedOut: false, stdout: "1:2:www.youtube.com,\n", stderr: stderr)
            == .success("1:2:www.youtube.com,\n"))
        // Finished with nothing on stdout but tabs logged.
        #expect(OSAScriptRunner.result(status: 0, timedOut: false, stdout: "", stderr: stderr)
            == .success("1:2:www.youtube.com,3:4:www.netflix.com,"))
    }

    @Test func aFailureAlwaysHasAReason() {
        let killed = OSAScriptRunner.result(status: 15, timedOut: true, stdout: "", stderr: "")
        #expect(killed == .failure(ScriptFailure("it did not answer within 8 seconds")))
        let silent = OSAScriptRunner.result(status: 1, timedOut: false, stdout: "", stderr: "  \n")
        guard case .failure(let e) = silent else { Issue.record("a silent failure read as success"); return }
        #expect(!e.message.isEmpty)
        #expect(OSAScriptRunner.result(status: 1, timedOut: false, stdout: "", stderr: "execution error: nope (-1)\n")
            == .failure(ScriptFailure("execution error: nope (-1)")))
    }

    /// The real thing: osascript logs a pause, then hangs as a frozen tab
    /// does, and is killed at the deadline. The paused tab still comes back.
    @Test func aKilledScriptStillAnswersTheTabsItPaused() async {
        let script = """
        set out to "1:2:www.youtube.com,"
        log "PAUSED:1:2:www.youtube.com"
        delay 30
        return out
        """
        let started = Date()
        let result = await OSAScriptRunner(deadline: 1).run(script)
        #expect(result == .success("1:2:www.youtube.com,"))
        #expect(Date().timeIntervalSince(started) < 10, "the deadline must stop the hang")
    }

    @Test func aKilledScriptThatPausedNothingSaysWhy() async {
        let result = await OSAScriptRunner(deadline: 1).run("delay 30")
        #expect(result == .failure(ScriptFailure("it did not answer within 1 seconds")))
    }

    @Test func aRecoveredPauseIsHeldAndResumed() async {
        let runner = FakeRunner()
        runner.activeTabs = OSAScriptRunner.result(
            status: 15, timedOut: true, stdout: "", stderr: "PAUSED:1:2:www.youtube.com\n")
        let c = MediaPauseCoordinator(controller: MediaController(runner: runner),
                                      audio: { ["com.google.Chrome.helper"] }, safariRunning: { true })
        await c.pause(for: 30)
        #expect(c.lastReport == "Paused Google Chrome (www.youtube.com).")
        await c.resumeNow()
        #expect((runner.ran.last ?? "").contains("tab id 2 of window id 1"))
    }
}

// MARK: - The system's Now Playing

/// Stands in for MediaRemote: pauses what it was told is playing, and
/// records every resume.
final class FakeNowPlaying: NowPlayingRunner, @unchecked Sendable {
    var playing: [NowPlayingSession] = []
    var failure: ScriptFailure?
    private let lock = NSLock()
    private var _pauses = 0
    private var _resumed: [[NowPlayingSession]] = []
    var pauses: Int { lock.withLock { _pauses } }
    var resumed: [[NowPlayingSession]] { lock.withLock { _resumed } }

    init(_ playing: [NowPlayingSession] = []) { self.playing = playing }

    func pausePlaying() async -> Result<[NowPlayingSession], ScriptFailure> {
        lock.withLock { _pauses += 1 }
        if let failure { return .failure(failure) }
        return .success(playing)
    }

    func resume(_ sessions: [NowPlayingSession]) async {
        lock.withLock { _resumed.append(sessions) }
    }
}

@MainActor
@Suite(.serialized) struct MediaPauseNowPlayingTests {
    static let chrome = NowPlayingSession(pid: 1373, bundleID: "com.google.Chrome", name: "Google Chrome",
                                          title: "Water Cribs", item: "A")
    static let vlc = NowPlayingSession(pid: 4242, bundleID: "org.videolan.vlc", name: "VLC")
    static let firefox = NowPlayingSession(pid: 777, bundleID: "org.mozilla.firefox", name: "Firefox", title: "Lo-fi")

    func make(_ runner: FakeRunner, _ np: FakeNowPlaying, audio: Set<String>, safari: Bool = false) -> MediaPauseCoordinator {
        MediaPauseCoordinator(controller: MediaController(runner: runner, nowPlaying: np),
                              audio: { audio }, safariRunning: { safari })
    }

    @Test func nowPlayingPausesChromeWithoutAnyScript() async {
        let runner = FakeRunner(), np = FakeNowPlaying([Self.chrome])
        let c = make(runner, np, audio: ["com.google.Chrome.helper"])
        await c.pause(for: 30)
        #expect(c.isHolding)
        #expect(runner.ran.isEmpty, "Chrome's helper is Chrome's: Now Playing paused it, so no AppleScript runs")
        #expect(c.lastReport == "Paused Google Chrome (Water Cribs).")
        #expect(!c.lastPauseHadProblems)
        await c.resumeNow()
        #expect(np.resumed == [[Self.chrome]])
        #expect(runner.ran.isEmpty, "and none on resume either")
    }

    @Test func appsHomeSpeakerCannotScriptArePausedAndResumed() async {
        let runner = FakeRunner(), np = FakeNowPlaying([Self.vlc, Self.firefox])
        let c = make(runner, np, audio: ["org.videolan.vlc", "org.mozilla.firefox"])
        await c.pause(for: 30)
        #expect(c.isHolding)
        #expect(c.lastReport == "Paused VLC, Firefox (Lo-fi).", "not 'HomeSpeaker does not know how to control it'")
        #expect(!c.lastPauseHadProblems)
        #expect(runner.ran.isEmpty)
        await c.resumeNow()
        #expect(np.resumed == [[Self.vlc, Self.firefox]])
        #expect(!c.isHolding)
    }

    @Test func aPlayerNowPlayingMissedFallsBackToItsScript() async {
        // Spotify owns Now Playing; Chrome is sounding but did not register.
        let spotify = NowPlayingSession(pid: 9, bundleID: "com.spotify.client", name: "Spotify")
        let runner = FakeRunner(), np = FakeNowPlaying([spotify])
        runner.activeTabs = .success("7:42:www.youtube.com,")
        let c = make(runner, np, audio: ["com.spotify.client", "com.google.Chrome.helper"])
        await c.pause(for: 30)
        #expect(c.lastReport == "Paused Spotify, Google Chrome (www.youtube.com).")
        #expect(!runner.ran.contains { $0.contains("tell application \"Spotify\"") }, "Spotify was paused by Now Playing")
        #expect(runner.ran.contains { $0.contains("{active tab of w}") }, "Chrome by its script")
        await c.resumeNow()
        #expect(np.resumed == [[spotify]])
        #expect(runner.ran.last?.contains("tab id 42 of window id 7") == true)
    }

    @Test func whenNowPlayingFailsTheScriptsDoEverything() async {
        let runner = FakeRunner(), np = FakeNowPlaying()
        np.failure = ScriptFailure("cannot load")
        runner.spotify = .success("1")
        let c = make(runner, np, audio: ["com.spotify.client"])
        await c.pause(for: 30)
        #expect(c.lastReport == "Paused Spotify.")
        #expect(c.mediaRemoteProblem == "cannot load")
        await c.resumeNow()
        #expect(np.resumed.isEmpty, "nothing was paused through Now Playing, so nothing resumes through it")
    }

    @Test func anUnconfirmedPauseIsHeldButTheScriptStillTries() async {
        var late = Self.chrome
        late.confirmed = false
        let runner = FakeRunner(), np = FakeNowPlaying([late])
        runner.activeTabs = .success("")
        let c = make(runner, np, audio: ["com.google.Chrome.helper"])
        await c.pause(for: 30)
        #expect(runner.ran.contains { $0.contains("{active tab of w}") }, "not seen to stop, so Chrome's script runs")
        #expect(c.isHolding, "held anyway: a pause that lands late must still be resumed")
        await c.resumeNow()
        #expect(np.resumed == [[late]])
    }

    @Test func onlyWhatIsStillUnknownIsReportedUnsupported() async {
        let runner = FakeRunner(), np = FakeNowPlaying([Self.vlc])
        let c = make(runner, np, audio: ["org.videolan.vlc", "us.zoom.xos"])
        await c.pause(for: 30)
        #expect(c.lastReport == "Paused VLC. Could not pause us.zoom.xos -- HomeSpeaker does not know how to control it.")
        #expect(c.lastPauseHadProblems)
        await c.resumeNow()
    }

    @Test func theHoldRunningOutResumesNowPlayingToo() async throws {
        let runner = FakeRunner(), np = FakeNowPlaying([Self.vlc])
        let c = make(runner, np, audio: ["org.videolan.vlc"])
        await c.pause(for: 0.3)
        try await Task.sleep(for: .milliseconds(700))
        #expect(!c.isHolding)
        #expect(np.resumed == [[Self.vlc]])
    }

    @Test func aBurstPausesNowPlayingOnce() async {
        let runner = FakeRunner(), np = FakeNowPlaying([Self.vlc])
        let c = make(runner, np, audio: ["org.videolan.vlc"])
        await c.pause(for: 30)
        await c.pause(for: 30)
        #expect(np.pauses == 1, "the second announcement extends the hold")
        await c.resumeNow()
        #expect(np.resumed.count == 1)
    }

    @Test func aStandInScriptRunnerNeverReachesTheRealNowPlaying() {
        #expect(MediaController(runner: FakeRunner()).nowPlaying is NoNowPlaying)
        #expect(MediaController().nowPlaying is PerlNowPlayingRunner)
    }

    @Test func pauseLinesParseIntoSessionsEachOnce() {
        let lines = PerlNowPlayingRunner.lines(Data("""
        {"paused":{"pid":1373,"bundleID":"com.google.Chrome","name":"Google Chrome","title":"T","item":"A"}}
        not json
        {"unconfirmed":{"pid":9,"bundleID":"com.spotify.client","name":""}}
        {"paused":{"pid":1373,"bundleID":"com.google.Chrome","name":"Google Chrome"}}
        {"paused":{"pid":0,"bundleID":"x"}}
        {"done":true,"playing":2}
        """.utf8))
        let s = PerlNowPlayingRunner.paused(lines)
        #expect(s == [
            NowPlayingSession(pid: 1373, bundleID: "com.google.Chrome", name: "Google Chrome", title: "T", item: "A"),
            NowPlayingSession(pid: 9, bundleID: "com.spotify.client", name: "com.spotify.client", confirmed: false),
        ])
    }

    @Test func resumeCarriesThePidsAndTitlesAndPerlGetsNoCodeFromTheEnvironment() throws {
        setenv("PERL5OPT", "-Mevil", 1)
        defer { unsetenv("PERL5OPT") }
        let env = PerlNowPlayingRunner.environment(action: "resume", sessions: [Self.chrome, Self.vlc])
        #expect(env["HOMESPEAKER_MR_ACTION"] == "resume")
        #expect(env["HOMESPEAKER_MR_PIDS"] == "1373,4242")
        let titles = try JSONSerialization.jsonObject(with: Data(try #require(env["HOMESPEAKER_MR_TITLES"]).utf8))
        #expect(titles as? [String: String] == ["1373": "Water Cribs"])
        #expect(env["PERL5OPT"] == nil)
    }

    @Test func aSessionOwnsItsHelpersAudio() {
        #expect(Self.chrome.owns("com.google.Chrome.helper"))
        #expect(Self.chrome.owns("com.google.Chrome"))
        #expect(!Self.chrome.owns("com.google.ChromeX"))
        let webContent = NowPlayingSession(pid: 5, bundleID: "com.apple.WebKit.WebContent",
                                           parentBundleID: "com.apple.Safari", name: "Safari")
        #expect(webContent.owns("com.apple.Safari"))
    }

    /// The real thing, read only: perl loads THIS test bundle (found with
    /// dladdr), calls the entry and MediaRemote answers. Lists; never
    /// pauses what the Mac running the tests is playing.
    @Test func perlLoadsThisImageAndMediaRemoteAnswers() async throws {
        let image = try #require(NowPlayingRemote.imagePath(), "dladdr must find the image holding the entry")
        #expect(FileManager.default.fileExists(atPath: image))
        let runner = PerlNowPlayingRunner()
        switch await runner.list() {
        case .failure(let e): Issue.record("perl + MediaRemote failed: \(e.message)")
        case .success(let clients):
            for c in clients {
                #expect((c["pid"] as? NSNumber)?.int32Value ?? 0 > 0)
                #expect(c["bundleID"] is String)
                #expect(c["playing"] is Bool)
            }
        }
        // A resume of a process that is not there touches nothing and says so.
        let lines = try await runner.run(action: "resume", sessions: [
            NowPlayingSession(pid: Int32.max, bundleID: "none", name: "none")]).get()
        #expect(lines.last?["done"] as? Bool == true)
        #expect((lines.last?["resumed"] as? [Any])?.isEmpty == true)
    }

    @Test func noImageIsAFailureNotAHang() async {
        let r = PerlNowPlayingRunner(deadline: 3, image: nil)
        guard case .failure = await r.pausePlaying() else { Issue.record("no image must fail"); return }
    }

    @Test func aHungOrBrokenPerlFailsWithAReason() async {
        let r = PerlNowPlayingRunner(deadline: 3, image: "/nonexistent/HomeSpeaker")
        guard case .failure(let e) = await r.pausePlaying() else { Issue.record("must fail"); return }
        #expect(e.message.contains("cannot load"))
    }
}

// MARK: - Who holds the pause

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-route-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func testProfile(_ root: URL) -> HomeSpeakerProfile {
    .extension(dataFolder: root.appendingPathComponent("data"), toolFolder: nil,
               messagePrefix: "test.\(UUID().uuidString).homespeaker")
}

private func extensionChosen(dataFolder: URL) -> DoorRecord {
    DoorRecord(chosen: .extension, installedExtension: .init(
        program: "/Applications/Vitruvian.app/Tools/dev.vitruvian.homespeaker/bin/tool",
        dataFolder: dataFolder.path, version: "1.22.0", door: DoorRecord.ExtensionEntry.runsAlone))
}

@MainActor
@Suite(.serialized) struct MediaPauseRoutingTests {
    /// `speaker-broadcast` runs the app's `--say`. With the extension
    /// chosen, the app is quiet: its pause must go to the extension.
    @Test func theAppsSayGoesToTheExtensionWhileItIsChosen() throws {
        let home = try scratch()
        let app = HomeSpeakerProfile.app(home: home)
        let data = home.appendingPathComponent("ToolData/dev.vitruvian.homespeaker")
        let chosen = RequestRoute.candidates(for: app, record: extensionChosen(dataFolder: data), fileExists: { _ in true })
        #expect(chosen.map(\.door) == [.extension], "the quiet app does not listen")
        #expect(chosen.first?.messagePrefix == HomeSpeakerProfile.extensionMessagePrefix)
        #expect(chosen.first?.settingsURL == data.appendingPathComponent("settings.json"))

        var undecided = extensionChosen(dataFolder: data)
        undecided.chosen = nil
        #expect(RequestRoute.candidates(for: app, record: undecided, fileExists: { _ in true }).map(\.door) == [.app, .extension])
        #expect(RequestRoute.candidates(for: app, record: nil, fileExists: { _ in true }).map(\.door) == [.app])
        // The extension removed: the app runs and listens again.
        #expect(RequestRoute.candidates(for: app, record: extensionChosen(dataFolder: data), fileExists: { _ in false })
            .map(\.door) == [.app, .extension])
    }

    @Test func theExtensionsSayGoesToTheAppWhileItIsChosen() throws {
        let ext = HomeSpeakerProfile.extension(dataFolder: try scratch(), toolFolder: nil)
        #expect(RequestRoute.candidates(for: ext, record: DoorRecord(chosen: .app), fileExists: { _ in true }).map(\.door) == [.app, .extension])
        #expect(RequestRoute.candidates(for: ext, record: DoorRecord(chosen: .extension), fileExists: { _ in true }).map(\.door) == [.extension])
    }

    @Test func aTestsOwnNamesNeverReachARealHomeSpeaker() throws {
        let mine = testProfile(try scratch())
        #expect(RequestRoute.candidates(for: mine, record: DoorRecord(chosen: .app), fileExists: { _ in true }) == [mine])
    }

    @Test func aRequestGoesToTheFirstOneAlive() throws {
        let me = testProfile(try scratch()), other = testProfile(try scratch())
        let route = RequestRoute(candidates: { _ in [me, other] }, alive: { $0 == other })
        guard case .post(let to) = MediaPauseRequest.destination(for: me, route: route) else {
            Issue.record("posted nowhere"); return
        }
        #expect(to == other, "posted under the names of a HomeSpeaker nobody runs")
    }

    /// Nobody alive (neither the app nor Vitruvian running): `--say` pauses
    /// itself and waits out the hold, so the media is resumed before exit.
    @Test func withNobodyAliveThisProcessHoldsAndWaits() async throws {
        let me = testProfile(try scratch())
        let nobody = RequestRoute(candidates: { [$0] }, alive: { _ in false })
        let runner = SlowTabs(["1:2:www.youtube.com,"])
        let own = MediaPauseCoordinator(controller: MediaController(runner: runner),
                                        audio: { ["com.google.Chrome.helper"] }, safariRunning: { false })
        await MediaPauseRequest.pause(seconds: 0.3, profile: me, route: nobody, makeOwn: { own })
        #expect(own.isHolding, "nobody paused the media")
        await MediaPauseRequest.extend(seconds: 0.4, profile: me, route: nobody)
        await MediaPauseRequest.waitForOwnHold(profile: me)
        #expect(!own.isHolding)
        #expect(runner.resumes.count == 1, "exited with the media still paused")
    }

    @Test func aFailedBroadcastResumesWhereThePauseWent() async throws {
        let me = testProfile(try scratch())
        let nobody = RequestRoute(candidates: { [$0] }, alive: { _ in false })
        let runner = SlowTabs(["1:2:www.youtube.com,"], delay: .milliseconds(200))
        let own = MediaPauseCoordinator(controller: MediaController(runner: runner),
                                        audio: { ["com.google.Chrome.helper"] }, safariRunning: { false })
        await MediaPauseRequest.pause(seconds: 60, profile: me, route: nobody, makeOwn: { own })
        await MediaPauseRequest.resumeNow(profile: me, route: nobody)
        #expect(!own.isHolding)
        await MediaPauseRequest.waitForOwnHold(profile: me)
    }

    @Test func aVolumeRestoreCountsOnTheOneInUse() async throws {
        let me = testProfile(try scratch()), other = testProfile(try scratch())
        let inUse = RequestRoute(candidates: { _ in [other] }, alive: { $0 == other })
        #expect(await VolumeRestoreRequest.canRestore(profile: me, route: inUse),
                "the extension in use puts the speaker back for the app's --say")
        let nobody = RequestRoute(candidates: { _ in [other] }, alive: { _ in false })
        #expect(await VolumeRestoreRequest.canRestore(profile: me, route: nobody) == false,
                "never raise a speaker nothing will lower again")
    }
}

// MARK: - The hold is counted from when the speaker starts

/// Google Home's MCP endpoint, answering after `delay` seconds.
private final class SlowGoogle: URLProtocol {
    nonisolated(unsafe) static var delay: Double = 0
    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SlowGoogle.self]
        return URLSession(configuration: configuration)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) { [self] in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

@MainActor
@Suite(.serialized) struct BroadcastHoldTests {
    /// The network took 2 s before the speaker started; the 3 s hold,
    /// counted from before it, ran out a second into the speech.
    @Test func theHoldIsExtendedOnceTheBroadcastIsAccepted() async throws {
        let root = try scratch()
        let profile = testProfile(root)
        let runner = SlowTabs(["1:2:www.youtube.com,"])
        let coordinator = MediaPauseCoordinator(controller: MediaController(runner: runner),
                                                audio: { ["com.google.Chrome.helper"] }, safariRunning: { false })
        let token = MediaPauseRequest.listen(with: coordinator, profile: profile)
        defer { DistributedNotificationCenter.default().removeObserver(token) }

        let id = UUID().uuidString
        let store = SecretStore(fileURL: profile.secretsURL)
        try store.save(Secrets(google: GoogleCredentials(
            clientId: "made-up.apps.googleusercontent.test", clientSecret: "made-up-\(id)", // gitleaks:allow (made-up test token)
            accessToken: "ya29.made-up-\(id)", refreshToken: "1//made-up-\(id)", // gitleaks:allow (made-up test token)
            expiry: Date().addingTimeInterval(3600), scopes: [GoogleAuth.homeScope])))
        let client = GoogleHomeClient(auth: GoogleAuth(store: store, session: SlowGoogle.session),
                                      session: SlowGoogle.session, messages: profile)
        var config = SpeakerConfig(enabled: true, defaultTarget: "lake", structureId: "structure@s",
                                   targets: ["lake": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Lake")])
        config.pauseMedia = true
        config.pauseMediaExtraSeconds = 0
        SlowGoogle.delay = 2
        let started = Date()
        let sent = try await client.broadcast(
            text: "hi", target: config.defaultDevice!, structureId: config.structureId, config: config)
        #expect(sent)
        #expect(Date().timeIntervalSince(started) >= 1.9)
        // 3 s from the pause would end at ~3 s; from the broadcast, ~5 s.
        try await Task.sleep(until: .now + .seconds(max(0, 4 - Date().timeIntervalSince(started))), clock: .continuous)
        #expect(coordinator.isHolding, "the media came back while the speaker was still talking")
        await coordinator.resumeNow()
    }
}

@Suite struct AnnounceTimeoutTests {
    @Test func aLoneSayHasTimeToWaitOutTheHold() {
        var config = SpeakerConfig()
        config.pauseMedia = false
        let without = HomeSpeakerCommandLine.announceTimeout("hello there", config: config)
        config.pauseMedia = true
        config.pauseMediaExtraSeconds = 1
        let with = HomeSpeakerCommandLine.announceTimeout("hello there", config: config)
        #expect(abs((with - without) - AnnouncementTiming.seconds(for: "hello there", extra: 1)) < 0.001)
    }
}

// MARK: - The announcer and `--say`

private final class MediaLog: MediaPausing, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    var events: [String] { lock.withLock { _events } }
    private func add(_ e: String) { lock.withLock { _events.append(e) } }
    func pause(seconds: Double) async { add("pause") }
    func extend(seconds: Double) async { add("extend(\(seconds))") }
    func resumeNow() async { add("resume") }
    func waitUntilReleased() async { add("wait") }
}

private struct AcceptingHome: HomeBroadcasting {
    func broadcast(text: String, target: SpeakerDevice, structureId: String,
                   config: SpeakerConfig?, force: Bool, at date: Date) async throws -> Bool { true }
}

private struct QuietMac: LocalSpeaking {
    func speak(_ text: String, voiceID: String) async throws {}
}

@Suite struct AnnouncerHoldTests {
    private func config() -> SpeakerConfig {
        var c = SpeakerConfig(enabled: true, defaultTarget: "lake", structureId: "structure@s",
                              targets: ["lake": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Lake")])
        c.speakHome = true
        c.speakLocal = true
        c.pauseMedia = true
        c.pauseMediaExtraSeconds = 1
        return c
    }

    @Test func bothOutputsHoldTheHomeTimeFromWhenGoogleAccepts() async {
        let media = MediaLog()
        _ = await Announcer(home: AcceptingHome(), local: QuietMac(), media: media)
            .announce("hello there", config: config(), force: true)
        let homeHold = AnnouncementTiming.seconds(for: "hello there", extra: 1)
        #expect(media.events.contains("extend(\(homeHold))"), "the home estimate ran from before the network calls")
    }

    @Test func sayWaitsForAHoldItHoldsItself() async throws {
        let media = MediaLog()
        let history = BroadcastHistory(fileURL: try scratch().appendingPathComponent("history.json"))
        _ = await HomeSpeakerCommandLine.say(
            "hello there", config: config(), announcer: Announcer(home: AcceptingHome(), local: QuietMac(), media: media),
            history: history, standsAside: false, door: .app)
        #expect(media.events.first == "pause")
        #expect(media.events.last == "wait", "--say exits without waiting for media it paused itself")
    }
}
