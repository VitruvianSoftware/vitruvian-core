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
// The pausing lives in the long-lived process (the menu bar app, or the
// extension's), which outlives an announcement. The Claude Code Stop hook and
// `--say` are short-lived and hand the request over with a distributed
// notification, to whichever HomeSpeaker is in use (`RequestRoute`). With
// none alive, the short-lived process pauses itself and waits out the hold
// before it exits.

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

    /// This and `other` (the same player) together, each handle and site once.
    func merging(_ other: PausedMedia) -> PausedMedia {
        var out = self
        for h in other.handles where !out.handles.contains(h) { out.handles.append(h) }
        for s in other.sites where !out.sites.contains(s) { out.sites.append(s) }
        return out
    }
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

    /// Marks and pauses every AUDIBLE playing media element and returns the
    /// site's host, or "" when nothing audible was playing. The mark is what
    /// makes resume exact: only elements WE paused are touched.
    ///
    /// Muted or zero-volume elements are skipped: GitHub, X, Reddit and
    /// YouTube's own previews loop silent autoplay videos in the tab in
    /// front. Pausing one answered "paused", and that answer stopped the
    /// search before the background tab that was actually making the sound.
    static let pauseJS = deepWalk(
        "r.querySelectorAll('video,audio').forEach(m=>{if(!m.paused&&!m.ended&&!m.muted&&m.volume>0){m.dataset.hsPaused='1';m.pause();n++}})",
        // Never "" after pausing: a file:// page has no hostname, and an
        // empty answer would mean "nothing paused" -- so never resumed.
        result: "n?(location.hostname||'this page'):''")
    /// Resumes elements we marked that are still paused, clearing the mark.
    /// play() is a promise that rejects when the page forbids it; swallowed,
    /// and a throw from one element never stops the others resuming.
    static let resumeJS = deepWalk(
        "r.querySelectorAll('[data-hs-paused]').forEach(m=>{delete m.dataset.hsPaused;if(m.paused){try{const p=m.play();if(p&&p.catch)p.catch(()=>{})}catch(_){}n++}})",
        result: "n")

    /// Sites checked before walking every tab: a video in a background tab
    /// is nearly always on one of these, and a tab's URL costs nothing to
    /// read while running script in 200 tabs takes seconds. A hint only --
    /// the every-tab pass still catches anything else.
    static let mediaSites = [
        "youtube.com", "netflix.com", "primevideo.com", "amazon.com/gp/video", "twitch.tv",
        "vimeo.com", "disneyplus.com", "hulu.com", "max.com", "tv.apple.com", "spotify.com", "soundcloud.com",
    ]

    /// Which tabs one browser pass looks in.
    enum TabPass: Equatable, CaseIterable { case activeTabs, mediaSiteTabs, allTabs }
    typealias ChromiumPass = TabPass

    static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// An object id as AppleScript: bare when it is a number (Chrome, Brave,
    /// Edge, Vivaldi, Safari), quoted when it is text (Arc's window and tab
    /// ids are UUIDs, and a bare UUID is a syntax error that stopped the
    /// whole resume script compiling -- so Arc never resumed). Nil for
    /// anything else, so an odd answer can never become script.
    static func idLiteral<S: StringProtocol>(_ id: S) -> String? {
        guard !id.isEmpty, id.count <= 128,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return id.allSatisfy(\.isNumber) ? String(id) : "\"\(id)\""
    }

    /// The loop body one pass runs per window, for `tabRef` tabs. `attempt`
    /// is what runs on each tab `t` of window `w`.
    private static func passBody(_ pass: TabPass, current: String, attempt: String) -> String {
        switch pass {
        case .activeTabs:
            return "repeat with t in {\(current) of w}\n\(attempt)\nend repeat"
        case .allTabs:
            return "repeat with t in (tabs of w)\n\(attempt)\nend repeat"
        case .mediaSiteTabs:
            let match = mediaSites.map { "u contains \"\($0)\"" }.joined(separator: " or ")
            // A blank tab's URL is `missing value`, which `contains` refuses.
            return """
            set urls to URL of tabs of w
            repeat with i from 1 to count of urls
              set u to item i of urls
              if u is not missing value then
                if \(match) then
                  set t to tab i of w
            \(attempt)
                end if
              end if
            end repeat
            """
        }
    }

    /// One tab's try: run `call` (which sets `r`), and record `handle` and
    /// the host when it paused something. A discarded or chrome:// tab
    /// answers `missing value`, which is not a pause -- counted as one, it
    /// ended the search with nothing actually paused.
    private static func attempt(call: String, handle: String) -> String {
        """
                try
                  set r to \(call)
                  if r is not missing value then
                    if r is not "" then set out to out & \(handle) & ":" & r & ","
                  end if
                on error msg
                  if firstErr is "" then set firstErr to msg
                end try
        """
    }

    private static func pauseScript(app: String, body: String) -> String {
        """
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

    /// Chromium, in up to three passes: the active tab of every window (a
    /// video is almost always the tab being watched), then tabs on known
    /// media sites (URLs are read in one Apple Event per window), then every
    /// tab -- which on a 200-tab browser takes seconds and so runs last.
    /// Output: "w:t:host," per paused tab, or "ERR:<message>".
    static func chromiumPause(_ app: String, pass: TabPass) -> String {
        let call = "execute t javascript \"\(escaped(pauseJS))\""
        return pauseScript(app: app, body: passBody(
            pass, current: "active tab", attempt: attempt(call: call, handle: "(id of w) & \":\" & (id of t)")))
    }

    /// Resumes each paused tab by its ids. When the tab is not where it was
    /// (dragged to another window during the announcement) or resumed
    /// nothing, the tab id is looked for in every window: only elements we
    /// marked are ever played, so trying a wrong tab does nothing.
    static func chromiumResume(_ app: String, handles: [String]) -> String {
        let js = escaped(resumeJS)
        let lines = handles.compactMap { h -> String? in
            let parts = h.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let window = idLiteral(parts[0]), let tab = idLiteral(parts[1]) else { return nil }
            return """
            set done to false
            try
              set r to execute (tab id \(tab) of window id \(window)) javascript "\(js)"
              if r is not missing value then
                if (r as integer) > 0 then set done to true
              end if
            end try
            if not done then
              repeat with w in windows
                try
                  execute (tab id \(tab) of w) javascript "\(js)"
                  exit repeat
                end try
              end repeat
            end if
            """
        }
        return "tell application \"\(app)\"\n\(lines.joined(separator: "\n"))\nend tell"
    }

    /// Safari, in the same three passes as Chromium. Safari tabs have no
    /// id, so a tab is "windowID:index". Output: "w:i:host," per paused tab.
    static func safariPause(pass: TabPass) -> String {
        let call = "do JavaScript \"\(escaped(pauseJS))\" in t"
        return pauseScript(app: "Safari", body: passBody(
            pass, current: "current tab", attempt: attempt(call: call, handle: "(id of w) & \":\" & (index of t)")))
    }

    /// The front tabs only, as before; kept for callers that want one pass.
    static var safariPause: String { safariPause(pass: .activeTabs) }

    /// Resumes each paused Safari tab by window and index. If that resumed
    /// nothing -- the person switched or reordered tabs, closed the window,
    /// or the index moved -- every tab of that window is tried, and every
    /// window when the window is gone. Only marked elements play, so the
    /// sweep never starts anything we did not pause.
    static func safariResume(handles: [String]) -> String {
        let js = escaped(resumeJS)
        let sweepAll = """
              set ts to {}
              repeat with w in windows
                set ts to ts & (tabs of w)
              end repeat
        """
        let lines = handles.map { h -> String in
            let parts = h.split(separator: ":", omittingEmptySubsequences: false)
            let window = parts.first.flatMap { $0.allSatisfy(\.isNumber) && !$0.isEmpty ? String($0) : nil }
            let index = parts.count == 2 && !parts[1].isEmpty && parts[1].allSatisfy(\.isNumber) ? String(parts[1]) : nil
            guard let window else {
                return "\(sweepAll)\nrepeat with t in ts\n  try\n    do JavaScript \"\(js)\" in t\n  end try\nend repeat"
            }
            let exact = index.map { i in
                """
                try
                  set r to do JavaScript "\(js)" in tab \(i) of window id \(window)
                  if r is not missing value then
                    if (r as integer) > 0 then set done to true
                  end if
                end try
                """
            } ?? ""
            return """
            set done to false
            \(exact)
            if not done then
              try
                set ts to tabs of window id \(window)
              on error
            \(sweepAll)
              end try
              repeat with t in ts
                try
                  do JavaScript "\(js)" in t
                end try
              end repeat
            end if
            """
        }
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
            return await pauseBrowser(player) { MediaScripts.chromiumPause(player.rawValue, pass: $0) }
        case .safari:
            return await pauseBrowser(player) { MediaScripts.safariPause(pass: $0) }
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

    /// A browser, in passes. The front tabs AND the media-site tabs are both
    /// always looked at: the tab in front playing something must not hide a
    /// background YouTube tab that is playing too. Only when neither found
    /// anything is every tab walked.
    ///
    /// A browser-wide refusal ("JavaScript through AppleScript is turned
    /// off", not authorised) stops at once: walking 200 tabs would only
    /// collect 200 refusals. Any other error belongs to one tab (a
    /// chrome:// page, a crashed renderer) and must not stop the search for
    /// the tab that is playing.
    private func pauseBrowser(_ player: MediaPlayer, script: (MediaScripts.TabPass) -> String) async -> PauseOutcome {
        var found: PausedMedia?
        var problem: String?
        for pass in MediaScripts.TabPass.allCases {
            if pass == .allTabs, found != nil { break }
            switch browserOutcome(player, await runner.run(script(pass))) {
            case .paused(let m):
                found = found.map { $0.merging(m) } ?? m
            case .nothingPlaying:
                continue
            case .blocked(let why):
                if MediaPauseCoordinator.isBrowserWide(why) { return found.map(PauseOutcome.paused) ?? .blocked(why) }
                if problem == nil { problem = why }
            }
        }
        if let found { return .paused(found) }
        return problem.map(PauseOutcome.blocked) ?? .nothingPlaying
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

// MARK: - The coordinator (the long-lived process, or a lone `--say`)

/// Holds media paused across overlapping announcements: a burst of Slack
/// messages pauses once, keeps extending, and resumes once after the last.
///
/// Every pause, extend and resume runs one after another, in the order they
/// were asked for. Pausing takes `osascript` up to seconds, and while it ran
/// a second request used to slip in: a second pause saw nothing held and
/// paused again, overwriting (and so never resuming) what the first paused;
/// a resume found nothing held yet, and the pause landing after it left the
/// media paused for the whole hold.
@MainActor
public final class MediaPauseCoordinator: ObservableObject {
    public static let shared = MediaPauseCoordinator()

    /// One line for Settings: what the last announcement paused, or why it
    /// could not -- the Chrome setting, most likely.
    @Published public private(set) var lastReport: String?
    @Published public private(set) var isHolding = false
    /// The last pause met a player it could not pause (refused, or one
    /// HomeSpeaker cannot drive). For `--test-media-pause`'s exit code.
    public private(set) var lastPauseHadProblems = false

    private let controller: MediaController
    private let audio: @Sendable () -> Set<String>
    private let safariRunning: @MainActor () -> Bool
    private var held: [PausedMedia] = []
    private var resumeAt: Date?
    private var resumeTask: Task<Void, Never>?
    /// The last request queued: each new one waits for it.
    private var tail: Task<Void, Never>?
    /// Waiting for the hold to end (`waitUntilReleased`).
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

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

    /// Queues `op` behind every request already asked for.
    @discardableResult
    private func enqueue(_ op: @escaping @MainActor (MediaPauseCoordinator) async -> Void) -> Task<Void, Never> {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await op(self)
        }
        tail = task
        return task
    }

    /// Pauses what is playing for `seconds`, or extends an existing hold.
    public func pause(for seconds: Double) async {
        await enqueue { await $0.performPause(seconds) }.value
    }

    /// Keeps what is already paused paused for at least `seconds` more.
    /// Unlike `pause(for:)` it never pauses anything new: when this Mac
    /// finishes speaking after the hold ran out, whatever the user started
    /// since must be left alone. Queued behind a pause still under way, so
    /// it extends what that pause holds rather than being dropped.
    public func extend(for seconds: Double) {
        enqueue { $0.performExtend(seconds) }
    }

    /// Resumes now: the announcement failed, or the app is quitting. A
    /// pause still under way finishes first, and what it paused is resumed.
    public func resumeNow() async {
        resumeTask?.cancel()
        resumeTask = nil
        await enqueue { await $0.performResume() }.value
    }

    /// Returns once nothing is held: at once when nothing is, otherwise
    /// when the hold runs out or is resumed. A lone `--say` waits on this,
    /// so it does not exit with the media it paused still paused.
    public func waitUntilReleased() async {
        await tail?.value
        guard isHolding else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    private func performPause(_ seconds: Double) async {
        if let current = resumeAt {
            resumeAt = max(current, Date().addingTimeInterval(seconds))
            schedule()
            return
        }
        let (players, unsupported) = MediaPlayer.players(producing: audio(), safariRunning: safariRunning())
        guard !players.isEmpty else {
            lastPauseHadProblems = !unsupported.isEmpty
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
            // Added to, never replaced: what is held is what gets resumed.
            for m in paused { hold(m) }
            // Counted from when the pause landed: in the app the announcement
            // is sent only after this returns, so that is when speech starts.
            resumeAt = Date().addingTimeInterval(seconds)
            isHolding = true
            schedule()
        }
        lastPauseHadProblems = !problems.isEmpty
        lastReport = Self.report(paused: paused, problems: problems)
    }

    private func hold(_ m: PausedMedia) {
        if let i = held.firstIndex(where: { $0.player == m.player }) {
            held[i] = held[i].merging(m)
        } else {
            held.append(m)
        }
    }

    private func performExtend(_ seconds: Double) {
        guard let current = resumeAt else { return }
        resumeAt = max(current, Date().addingTimeInterval(seconds))
        schedule()
    }

    private func performResume() async {
        let toResume = held
        held = []
        resumeAt = nil
        isHolding = false
        for m in toResume { await controller.resume(m) }
        let waiters = releaseWaiters
        releaseWaiters = []
        for w in waiters { w.resume() }
    }

    /// The timer's resume: only if the hold really is over by the time it
    /// runs (an extend queued ahead of it may have moved the end).
    private func performExpiry() async {
        guard let at = resumeAt else { return }
        if at.timeIntervalSinceNow > 0.05 {
            schedule()
            return
        }
        await performResume()
    }

    private func schedule() {
        resumeTask?.cancel()
        guard let at = resumeAt else { return }
        resumeTask = Task { [weak self] in
            let wait = max(at.timeIntervalSinceNow, 0)
            try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
            guard !Task.isCancelled, let self else { return }
            // This task is the timer: forget it before resuming, so nothing
            // on the way cancels the task doing the resuming.
            self.resumeTask = nil
            await self.enqueue { await $0.performExpiry() }.value
        }
    }

    /// A refusal that holds for every tab of the browser, as opposed to one
    /// tab's own error.
    nonisolated static func isBrowserWide(_ why: String) -> Bool {
        explain(why) != why
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
    /// The name requests travel under for `profile`: the app's for the app,
    /// the extension's for the extension, so neither pauses for the other.
    public static func notificationName(for profile: HomeSpeakerProfile) -> Notification.Name {
        profile.messageName(.mediaPause)
    }

    /// The coordinator each profile's long-lived process holds, set by
    /// `listen`. When there is none (the Stop hook, `--say`), requests go
    /// to that process as a distributed notification instead.
    @MainActor private static var coordinators: [String: MediaPauseCoordinator] = [:]

    /// Where one announcement's pause went, so its extend and resume go to
    /// the same place even if who is alive changes meanwhile.
    enum Destination {
        /// A coordinator in this process: the long-lived one's, or a lone
        /// `--say`'s own when no long-lived process is alive.
        case coordinator(MediaPauseCoordinator)
        /// The long-lived process of this profile, over a notification.
        case post(HomeSpeakerProfile)
    }

    @MainActor private static var destinations: [String: Destination] = [:]
    /// A short-lived process's own coordinator, per profile, made when no
    /// long-lived process was alive to hold the pause.
    @MainActor private static var ownHolds: [String: MediaPauseCoordinator] = [:]

    /// The coordinator this process holds for `profile`, if it listens.
    @MainActor public static func inProcess(for profile: HomeSpeakerProfile) -> MediaPauseCoordinator? {
        coordinators[profile.messagePrefix]
    }

    /// Where a pause for `profile` goes now: this process's coordinator when
    /// it listens; else the long-lived process `route` finds alive (the
    /// HomeSpeaker in use, which may be the other one); else, with nobody
    /// alive, a coordinator of this process's own, which the caller then
    /// waits on (`waitForOwnHold`) so the media is resumed before it exits.
    @MainActor static func destination(
        for profile: HomeSpeakerProfile, route: RequestRoute,
        makeOwn: @MainActor () -> MediaPauseCoordinator = { MediaPauseCoordinator() }
    ) -> Destination {
        if let c = coordinators[profile.messagePrefix] { return .coordinator(c) }
        if let listener = route.listener(for: profile) {
            if let c = coordinators[listener.messagePrefix] { return .coordinator(c) }
            return .post(listener)
        }
        if let own = ownHolds[profile.messagePrefix] { return .coordinator(own) }
        let own = makeOwn()
        ownHolds[profile.messagePrefix] = own
        return .coordinator(own)
    }

    /// Pause media for `seconds`, through whichever process can hold it.
    public static func pause(
        seconds: Double, profile: HomeSpeakerProfile = .current, route: RequestRoute = .live(),
        makeOwn: @escaping @MainActor () -> MediaPauseCoordinator = { MediaPauseCoordinator() }
    ) async {
        let destination = await MainActor.run { () -> Destination in
            let d = destination(for: profile, route: route, makeOwn: makeOwn)
            destinations[profile.messagePrefix] = d
            return d
        }
        switch destination {
        case .coordinator(let c):
            await c.pause(for: seconds)
        case .post(let listener):
            post(["action": "pause", "seconds": seconds], to: listener)
            // Give the app a moment to pause before the chime starts.
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    /// Keep media paused `seconds` longer, if anything is paused.
    public static func extend(
        seconds: Double, profile: HomeSpeakerProfile = .current, route: RequestRoute = .live()
    ) async {
        switch await sentTo(profile, route: route) {
        case .coordinator(let c): await c.extend(for: seconds)
        case .post(let listener): post(["action": "extend", "seconds": seconds], to: listener)
        case nil: break
        }
    }

    public static func resumeNow(profile: HomeSpeakerProfile = .current, route: RequestRoute = .live()) async {
        switch await sentTo(profile, route: route) {
        case .coordinator(let c): await c.resumeNow()
        case .post(let listener): post(["action": "resume"], to: listener)
        case nil: break
        }
    }

    /// Waits until a pause this process holds itself for `profile` is
    /// over; at once when it holds none. A lone `--say` or `--announce`
    /// calls it before exiting.
    public static func waitForOwnHold(profile: HomeSpeakerProfile = .current) async {
        guard let own = await MainActor.run(body: { ownHolds[profile.messagePrefix] }) else { return }
        await own.waitUntilReleased()
    }

    /// Where `profile`'s last pause went; with none, where one would go now
    /// -- never a new coordinator of this process's own, which would hold
    /// nothing.
    private static func sentTo(_ profile: HomeSpeakerProfile, route: RequestRoute) async -> Destination? {
        await MainActor.run { () -> Destination? in
            if let d = destinations[profile.messagePrefix] { return d }
            if let c = coordinators[profile.messagePrefix] { return .coordinator(c) }
            guard let listener = route.listener(for: profile) else { return nil }
            if let c = coordinators[listener.messagePrefix] { return .coordinator(c) }
            return .post(listener)
        }
    }

    private static func post(_ info: [String: Any], to profile: HomeSpeakerProfile) {
        DistributedNotificationCenter.default().postNotificationName(
            notificationName(for: profile), object: nil, userInfo: info, deliverImmediately: true)
    }

    /// The long-lived process's side: listen for other HomeSpeaker
    /// processes of `profile` asking.
    @MainActor public static func listen(
        with coordinator: MediaPauseCoordinator, profile: HomeSpeakerProfile = .current
    ) -> NSObjectProtocol {
        coordinators[profile.messagePrefix] = coordinator
        return DistributedNotificationCenter.default().addObserver(
            forName: notificationName(for: profile), object: nil, queue: .main
        ) { note in
            let action = note.userInfo?["action"] as? String
            let seconds = (note.userInfo?["seconds"] as? NSNumber)?.doubleValue ?? 0
            Task { @MainActor in
                if action == "resume" { await coordinator.resumeNow() }
                else if action == "extend" { coordinator.extend(for: min(seconds, 120)) }
                else if seconds > 0 { await coordinator.pause(for: min(seconds, 120)) }
            }
        }
    }
}
