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
import CoreAudio
import Foundation

// Pause whatever this Mac is playing while a speaker announcement plays, then
// resume exactly that.
//
// Why it is built this way -- each alternative was tried on macOS 27 first:
//
// - MediaRemote (the private framework behind Control Center's Now Playing)
//   accepts a pause command and returns success, and nothing pauses; it also
//   reports "not playing" while a player plays. Closed to ordinary apps.
// - The hardware Play/Pause media key, synthesised, did not pause QuickTime,
//   and is a TOGGLE: sent when nothing is playing, it STARTS playback.
//
// What works: CoreAudio says, with no permission prompt, which apps are
// producing sound right now; each of those is then paused through its own
// scripting interface, which can also tell us whether it was playing. So only
// what was actually playing is paused, and only that is resumed -- and only if
// it is still paused when the announcement ends, so a video the user restarted
// by hand is left alone.
//
// The pausing lives in the menu bar app, the one process that outlives an
// announcement. The Claude Code Stop hook and `--say` are short-lived and hand
// the request over with a distributed notification.

// MARK: - What is making sound

public enum AudioActivity {
    /// Bundle identifiers of every process currently sending audio to an
    /// output device. Chrome's shows as `com.google.Chrome.helper` (its audio
    /// service), Safari's as a WebKit process.
    public static func outputtingBundleIDs() -> Set<String> {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        var out: Set<String> = []
        for id in ids {
            var running: UInt32 = 0
            var rsize = UInt32(MemoryLayout<UInt32>.size)
            var raddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &raddr, 0, nil, &rsize, &running) == noErr, running != 0 else { continue }
            var baddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var bsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(id, &baddr, 0, nil, &bsize, &name) == noErr,
               let bundle = name?.takeRetainedValue() as String?, !bundle.isEmpty {
                out.insert(bundle)
            }
        }
        return out
    }
}

// MARK: - The players we know how to pause

/// One app HomeSpeaker can pause and resume through its scripting interface.
public enum MediaPlayer: String, CaseIterable, Sendable {
    case chrome = "Google Chrome"
    case brave = "Brave Browser"
    case edge = "Microsoft Edge"
    case arc = "Arc"
    case vivaldi = "Vivaldi"
    case safari = "Safari"
    case music = "Music"
    case spotify = "Spotify"
    case quickTime = "QuickTime Player"

    /// The app's own bundle identifier, for "is it running".
    public var bundleID: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .brave: return "com.brave.Browser"
        case .edge: return "com.microsoft.edgemac"
        case .arc: return "company.thebrowser.Browser"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        case .safari: return "com.apple.Safari"
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .quickTime: return "com.apple.QuickTimePlayerX"
        }
    }

    var isChromium: Bool { [.chrome, .brave, .edge, .arc, .vivaldi].contains(self) }

    /// Which players an audio-producing process belongs to. Browsers play
    /// through helper processes whose ids extend the app's; Safari's audio
    /// comes from a WebKit process shared with every WebKit app, so it counts
    /// only when Safari itself is running.
    public static func players(
        producing bundleIDs: Set<String>, safariRunning: Bool
    ) -> (players: [MediaPlayer], unsupported: [String]) {
        var found: [MediaPlayer] = []
        var unsupported: [String] = []
        for id in bundleIDs.sorted() {
            if let p = allCases.first(where: { !$0.isWebKitShared && (id == $0.bundleID || id.hasPrefix($0.bundleID + ".")) }) {
                if !found.contains(p) { found.append(p) }
            } else if id.hasPrefix("com.apple.WebKit.") {
                if safariRunning, !found.contains(.safari) { found.append(.safari) }
            } else if id != Bundle.main.bundleIdentifier {
                unsupported.append(id)
            }
        }
        return (found, unsupported)
    }

    private var isWebKitShared: Bool { self == .safari }
}

/// Something HomeSpeaker paused, with what it needs to resume exactly that.
public struct PausedMedia: Equatable, Sendable {
    public var player: MediaPlayer
    /// Browser tabs as "windowID:tabID" (Safari: window ids); QuickTime
    /// document names; empty for Music and Spotify, which have one player.
    public var handles: [String]
    /// For browsers, the sites that were playing ("www.netflix.com"), so the
    /// Settings line can say what was paused -- one Test per service shows
    /// whether that service's player behaves.
    public var sites: [String] = []
}

/// The result of trying to pause one player.
public enum PauseOutcome: Equatable, Sendable {
    case paused(PausedMedia)
    case nothingPlaying
    /// The app refused, with its own words -- Chrome's "Executing JavaScript
    /// through AppleScript is turned off" is the one a person can fix.
    case blocked(String)
}

// MARK: - Scripts

enum MediaScripts {
    /// Walks the page, every shadow root and every same-origin iframe --
    /// players built as web components or embedded in a frame are invisible
    /// to a plain `document.querySelectorAll`. `%VISIT%` runs on each root.
    private static func deepWalk(_ visit: String, result: String) -> String {
        "(()=>{let n=0;const seen=new Set();const walk=r=>{if(!r||seen.has(r))return;seen.add(r);\(visit);"
            + "r.querySelectorAll('*').forEach(e=>{if(e.shadowRoot)walk(e.shadowRoot);"
            + "if(e.tagName==='IFRAME'){try{walk(e.contentDocument)}catch(_){}}})};walk(document);return \(result)})()"
    }

    /// Marks and pauses every playing media element and returns the site's
    /// host, or "" when nothing was playing. The mark is what makes resume
    /// exact: only elements WE paused are touched.
    static let pauseJS = deepWalk(
        "r.querySelectorAll('video,audio').forEach(m=>{if(!m.paused&&!m.ended){m.dataset.hsPaused='1';m.pause();n++}})",
        // Never "" after pausing: a file:// page has no hostname, and an
        // empty answer would mean "nothing paused" -- so never resumed.
        result: "n?(location.hostname||'this page'):''")
    /// Resumes elements we marked that are still paused, clearing the mark.
    /// play() is a promise that rejects when the page forbids it; swallowed.
    static let resumeJS = deepWalk(
        "r.querySelectorAll('[data-hs-paused]').forEach(m=>{delete m.dataset.hsPaused;if(m.paused){const p=m.play();if(p&&p.catch)p.catch(()=>{});n++}})",
        result: "n")

    /// Sites checked before walking every tab: a video in a background tab
    /// is nearly always on one of these, and a tab's URL costs nothing to
    /// read while running script in 200 tabs takes seconds. A hint only --
    /// the every-tab pass still catches anything else.
    static let mediaSites = [
        "youtube.com", "netflix.com", "primevideo.com", "amazon.com/gp/video", "twitch.tv",
        "vimeo.com", "disneyplus.com", "hulu.com", "max.com", "tv.apple.com", "spotify.com", "soundcloud.com",
    ]

    enum ChromiumPass: Equatable { case activeTabs, mediaSiteTabs, allTabs }

    static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Chromium, in up to three passes: the active tab of every window (a
    /// video is almost always the tab being watched), then tabs on known
    /// media sites (URLs are read in one Apple Event per window), then every
    /// tab -- which on a 200-tab browser takes seconds and so runs last.
    /// Output: "w:t:host," per paused tab, or "ERR:<message>".
    static func chromiumPause(_ app: String, pass: ChromiumPass) -> String {
        let js = escaped(pauseJS)
        let attempt = """
                try
                  set r to execute t javascript "\(js)"
                  if r is not "" then set out to out & (id of w) & ":" & (id of t) & ":" & r & ","
                on error msg
                  if firstErr is "" then set firstErr to msg
                end try
        """
        let body: String
        switch pass {
        case .activeTabs:
            body = "repeat with t in {active tab of w}\n\(attempt)\nend repeat"
        case .allTabs:
            body = "repeat with t in (tabs of w)\n\(attempt)\nend repeat"
        case .mediaSiteTabs:
            let match = mediaSites.map { "u contains \"\($0)\"" }.joined(separator: " or ")
            body = """
            set urls to URL of tabs of w
            repeat with i from 1 to count of urls
              set u to item i of urls
              if \(match) then
                set t to tab i of w
            \(attempt)
              end if
            end repeat
            """
        }
        return """
        set out to ""
        set firstErr to ""
        tell application "\(app)"
          repeat with w in windows
        \(body)
          end repeat
        end tell
        if out is "" and firstErr is not "" then return "ERR:" & firstErr
        return out
        """
    }

    static func chromiumResume(_ app: String, handles: [String]) -> String {
        let lines = handles.compactMap { h -> String? in
            let parts = h.split(separator: ":")
            guard parts.count == 2 else { return nil }
            return "try\n execute (tab id \(parts[1]) of window id \(parts[0])) javascript \"\(escaped(resumeJS))\"\nend try"
        }
        return "tell application \"\(app)\"\n\(lines.joined(separator: "\n"))\nend tell"
    }

    static let safariPause = """
    set out to ""
    set firstErr to ""
    tell application "Safari"
      repeat with w in windows
        try
          set r to do JavaScript "\(escaped(pauseJS))" in current tab of w
          if r is not "" then set out to out & (id of w) & ":" & r & ","
        on error msg
          if firstErr is "" then set firstErr to msg
        end try
      end repeat
    end tell
    if out is "" and firstErr is not "" then return "ERR:" & firstErr
    return out
    """

    static func safariResume(handles: [String]) -> String {
        let lines = handles.map { "try\n do JavaScript \"\(escaped(resumeJS))\" in current tab of window id \($0)\nend try" }
        return "tell application \"Safari\"\n\(lines.joined(separator: "\n"))\nend tell"
    }

    /// Music and Spotify: one player with a readable state.
    static func singlePlayerPause(_ app: String) -> String {
        "tell application \"\(app)\"\nif player state is playing then\npause\nreturn \"1\"\nend if\nend tell\nreturn \"\""
    }

    static func singlePlayerResume(_ app: String) -> String {
        "tell application \"\(app)\"\nif player state is paused then play\nend tell"
    }

    static let quickTimePause = """
    set out to ""
    tell application "QuickTime Player"
      repeat with d in documents
        if playing of d then
          pause d
          set out to out & (name of d) & linefeed
        end if
      end repeat
    end tell
    return out
    """

    static func quickTimeResume(handles: [String]) -> String {
        let lines = handles.map { "try\nif not (playing of document \"\(escaped($0))\") then play document \"\(escaped($0))\"\nend try" }
        return "tell application \"QuickTime Player\"\n\(lines.joined(separator: "\n"))\nend tell"
    }

    /// Splits a pause script's output into handles, or the app's refusal.
    static func parse(_ output: String, separator: Character) -> Result<[String], ScriptFailure> {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ERR:") { return .failure(ScriptFailure(String(trimmed.dropFirst(4)))) }
        return .success(trimmed.split(separator: separator).map(String.init).filter { !$0.isEmpty })
    }
}

// MARK: - Running scripts

/// What a script run said when it failed, in the app's own words.
public struct ScriptFailure: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// Runs AppleScript. A protocol so tests can stand in for real players.
public protocol ScriptRunner: Sendable {
    func run(_ source: String) async -> Result<String, ScriptFailure>
}

/// `osascript` in a child process: off the main thread, so a slow browser
/// cannot stall the menu bar, and still attributed to HomeSpeaker for the
/// macOS Automation prompt ("HomeSpeaker wants to control Google Chrome").
public struct OSAScriptRunner: ScriptRunner {
    public init() {}
    public func run(_ source: String) async -> Result<String, ScriptFailure> {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", source]
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch {
                    cont.resume(returning: .failure(ScriptFailure(error.localizedDescription))); return
                }
                // A hung app must not hold the pause forever.
                let deadline = DispatchTime.now() + 8
                DispatchQueue.global().asyncAfter(deadline: deadline) { if p.isRunning { p.terminate() } }
                p.waitUntilExit()
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: p.terminationStatus == 0 ? .success(o) : .failure(ScriptFailure(e.trimmingCharacters(in: .whitespacesAndNewlines))))
            }
        }
    }
}

// MARK: - Pausing one player

public struct MediaController: Sendable {
    let runner: ScriptRunner

    public init(runner: ScriptRunner = OSAScriptRunner()) { self.runner = runner }

    public func pause(_ player: MediaPlayer) async -> PauseOutcome {
        switch player {
        case .chrome, .brave, .edge, .arc, .vivaldi:
            // Only a clean miss is worth walking every tab. A refusal ("turned
            // off") is browser-wide, so walking 200 tabs would only collect
            // 200 refusals.
            for pass in [MediaScripts.ChromiumPass.activeTabs, .mediaSiteTabs, .allTabs] {
                let result = browserOutcome(player, await runner.run(MediaScripts.chromiumPause(player.rawValue, pass: pass)))
                guard case .nothingPlaying = result else { return result }
            }
            return .nothingPlaying
        case .safari:
            return browserOutcome(player, await runner.run(MediaScripts.safariPause))
        case .music, .spotify:
            switch await runner.run(MediaScripts.singlePlayerPause(player.rawValue)) {
            case .success(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                ? .paused(PausedMedia(player: player, handles: [])) : .nothingPlaying
            case .failure(let e): return .blocked(e.message)
            }
        case .quickTime:
            return outcome(player, await runner.run(MediaScripts.quickTimePause), separator: "\n")
        }
    }

    public func resume(_ media: PausedMedia) async {
        let script: String
        switch media.player {
        case .chrome, .brave, .edge, .arc, .vivaldi:
            script = MediaScripts.chromiumResume(media.player.rawValue, handles: media.handles)
        case .safari: script = MediaScripts.safariResume(handles: media.handles)
        case .music, .spotify: script = MediaScripts.singlePlayerResume(media.player.rawValue)
        case .quickTime: script = MediaScripts.quickTimeResume(handles: media.handles)
        }
        _ = await runner.run(script)
    }

    /// Browser scripts answer "handle:host," per paused tab; the host is the
    /// last field, everything before it is the handle to resume.
    private func browserOutcome(_ player: MediaPlayer, _ result: Result<String, ScriptFailure>) -> PauseOutcome {
        switch result {
        case .failure(let e): return .blocked(e.message)
        case .success(let out):
            switch MediaScripts.parse(out, separator: ",") {
            case .failure(let e): return .blocked(e.message)
            case .success(let entries):
                guard !entries.isEmpty else { return .nothingPlaying }
                var handles: [String] = [], sites: [String] = []
                for entry in entries {
                    var parts = entry.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
                    let site = parts.count > 1 ? parts.removeLast() : ""
                    handles.append(parts.joined(separator: ":"))
                    if !site.isEmpty, !sites.contains(site) { sites.append(site) }
                }
                return .paused(PausedMedia(player: player, handles: handles, sites: sites))
            }
        }
    }

    private func outcome(_ player: MediaPlayer, _ result: Result<String, ScriptFailure>, separator: Character) -> PauseOutcome {
        switch result {
        case .failure(let e): return .blocked(e.message)
        case .success(let out):
            switch MediaScripts.parse(out, separator: separator) {
            case .failure(let e): return .blocked(e.message)
            case .success(let handles): return handles.isEmpty ? .nothingPlaying : .paused(PausedMedia(player: player, handles: handles))
            }
        }
    }
}

// MARK: - How long to stay paused

public enum AnnouncementTiming {
    /// Seconds from sending an announcement until the speaker has finished it.
    ///
    /// The Home API returns when Google has ACCEPTED the broadcast; nothing
    /// reports when the speaker stops talking. So this estimates: the network
    /// and the broadcast chime (~2.5 s), speech at ~2.5 words a second
    /// (Assistant's broadcast voice is unhurried), then `extra` seconds the
    /// user can adjust. Clamped so a runaway estimate never holds media for
    /// minutes.
    public static func seconds(for spoken: String, extra: Double) -> Double {
        let words = spoken.split(whereSeparator: { $0.isWhitespace }).count
        return min(max(2.5 + Double(words) / 2.5 + max(extra, 0), 3), 120)
    }
}

// MARK: - The coordinator (menu bar app only)

/// Holds media paused across overlapping announcements: a burst of Slack
/// messages pauses once, keeps extending, and resumes once after the last.
@MainActor
public final class MediaPauseCoordinator: ObservableObject {
    public static let shared = MediaPauseCoordinator()

    /// One line for Settings: what the last announcement paused, or why it
    /// could not -- the Chrome setting, most likely.
    @Published public private(set) var lastReport: String?
    @Published public private(set) var isHolding = false

    private let controller: MediaController
    private let audio: @Sendable () -> Set<String>
    private let safariRunning: @MainActor () -> Bool
    private var held: [PausedMedia] = []
    private var resumeAt: Date?
    private var resumeTask: Task<Void, Never>?

    public init(
        controller: MediaController = MediaController(),
        audio: @escaping @Sendable () -> Set<String> = { AudioActivity.outputtingBundleIDs() },
        safariRunning: @escaping @MainActor () -> Bool = {
            !NSRunningApplication.runningApplications(withBundleIdentifier: MediaPlayer.safari.bundleID).isEmpty
        }
    ) {
        self.controller = controller
        self.audio = audio
        self.safariRunning = safariRunning
    }

    /// Pauses what is playing for `seconds`, or extends an existing hold.
    public func pause(for seconds: Double) async {
        if let current = resumeAt {
            resumeAt = max(current, Date().addingTimeInterval(seconds))
            schedule()
            return
        }
        let (players, unsupported) = MediaPlayer.players(producing: audio(), safariRunning: safariRunning())
        guard !players.isEmpty else {
            lastReport = unsupported.isEmpty ? nil : "Could not pause \(unsupported.joined(separator: ", ")) -- HomeSpeaker does not know how to control it."
            return
        }
        // All at once: one slow or refusing app must not delay the others
        // past the start of the announcement.
        let controller = self.controller
        let outcomes = await withTaskGroup(of: (MediaPlayer, PauseOutcome).self) { group in
            for p in players { group.addTask { (p, await controller.pause(p)) } }
            var all: [(MediaPlayer, PauseOutcome)] = []
            for await r in group { all.append(r) }
            return all.sorted { a, b in players.firstIndex(of: a.0)! < players.firstIndex(of: b.0)! }
        }
        var paused: [PausedMedia] = []
        var problems: [String] = []
        for (p, outcome) in outcomes {
            switch outcome {
            case .paused(let m): paused.append(m)
            case .nothingPlaying: break
            case .blocked(let why): problems.append("\(p.rawValue): \(Self.explain(why))")
            }
        }
        if !paused.isEmpty {
            held = paused
            // Counted from when the pause landed: in the app the announcement
            // is sent only after this returns, so that is when speech starts.
            resumeAt = Date().addingTimeInterval(seconds)
            isHolding = true
            schedule()
        }
        lastReport = Self.report(paused: paused, problems: problems)
    }

    /// Keeps what is already paused paused for at least `seconds` more.
    /// Unlike `pause(for:)` it never pauses anything new: when this Mac
    /// finishes speaking after the hold ran out, whatever the user started
    /// since must be left alone.
    public func extend(for seconds: Double) {
        guard let current = resumeAt else { return }
        resumeAt = max(current, Date().addingTimeInterval(seconds))
        schedule()
    }

    /// Resumes now: the announcement failed, or the app is quitting.
    public func resumeNow() async {
        resumeTask?.cancel()
        resumeTask = nil
        let toResume = held
        held = []
        resumeAt = nil
        isHolding = false
        for m in toResume { await controller.resume(m) }
    }

    private func schedule() {
        resumeTask?.cancel()
        guard let at = resumeAt else { return }
        resumeTask = Task { [weak self] in
            let wait = max(at.timeIntervalSinceNow, 0)
            try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
            guard !Task.isCancelled else { return }
            await self?.resumeNow()
        }
    }

    /// Chrome's refusal is long and mentions a menu path; say only that.
    nonisolated static func explain(_ why: String) -> String {
        if why.localizedCaseInsensitiveContains("JavaScript through AppleScript is turned off") {
            return "turn on View › Developer › Allow JavaScript from Apple Events"
        }
        if why.localizedCaseInsensitiveContains("Allow JavaScript from Apple Events") {
            return "turn on Settings › Developer › Allow JavaScript from Apple Events"
        }
        if why.contains("-1743") || why.localizedCaseInsensitiveContains("not authorized") {
            return "allow HomeSpeaker under System Settings › Privacy & Security › Automation"
        }
        return why
    }

    nonisolated static func report(paused: [PausedMedia], problems: [String]) -> String? {
        var parts: [String] = []
        if !paused.isEmpty {
            parts.append("Paused " + paused.map { m in
                m.sites.isEmpty ? m.player.rawValue : "\(m.player.rawValue) (\(m.sites.joined(separator: ", ")))"
            }.joined(separator: ", ") + ".")
        }
        if !problems.isEmpty { parts.append("Could not pause " + problems.joined(separator: "; ") + ".") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: - Asking for a pause from any process

public enum MediaPauseRequest {
    public static let notificationName = Notification.Name("com.vitruviansoftware.homespeaker.media-pause")

    /// Set by the menu bar app at launch. When nil (the Stop hook, `--say`),
    /// requests go to the app as a distributed notification instead.
    @MainActor public static var inProcess: MediaPauseCoordinator?

    /// Pause media for `seconds`. A no-op when the app is not running: the
    /// feature lives in the menu bar app, which is a login item.
    public static func pause(seconds: Double) async {
        if let coordinator = await MainActor.run(body: { inProcess }) {
            await coordinator.pause(for: seconds)
        } else {
            post(["action": "pause", "seconds": seconds])
            // Give the app a moment to pause before the chime starts.
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    /// Keep media paused `seconds` longer, if anything is paused.
    public static func extend(seconds: Double) async {
        if let coordinator = await MainActor.run(body: { inProcess }) {
            await coordinator.extend(for: seconds)
        } else {
            post(["action": "extend", "seconds": seconds])
        }
    }

    public static func resumeNow() async {
        if let coordinator = await MainActor.run(body: { inProcess }) {
            await coordinator.resumeNow()
        } else {
            post(["action": "resume"])
        }
    }

    private static func post(_ info: [String: Any]) {
        DistributedNotificationCenter.default().postNotificationName(
            notificationName, object: nil, userInfo: info, deliverImmediately: true)
    }

    /// The app's side: listen for other HomeSpeaker processes asking.
    @MainActor public static func listen(with coordinator: MediaPauseCoordinator) -> NSObjectProtocol {
        inProcess = coordinator
        return DistributedNotificationCenter.default().addObserver(
            forName: notificationName, object: nil, queue: .main
        ) { note in
            let action = note.userInfo?["action"] as? String
            let seconds = (note.userInfo?["seconds"] as? Double) ?? 0
            Task { @MainActor in
                if action == "resume" { await coordinator.resumeNow() }
                else if action == "extend" { coordinator.extend(for: min(seconds, 120)) }
                else if seconds > 0 { await coordinator.pause(for: min(seconds, 120)) }
            }
        }
    }
}
