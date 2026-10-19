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
// - MediaRemote (the private framework behind Control Center's Now Playing),
//   called from this process, accepts a pause and nothing pauses: since
//   macOS 15.4 it answers only Apple-signed processes. Called from inside
//   /usr/bin/perl, which is Apple-signed, it works -- see "The system's Now
//   Playing" below.
// - The hardware Play/Pause media key, synthesised, did not pause QuickTime,
//   and is a TOGGLE: sent when nothing is playing, it STARTS playback.
//
// What works, in order: MediaRemote (through perl) pauses every app that is
// playing in the system's Now Playing, with an explicit Pause, never the
// toggle. Then CoreAudio says, with no permission prompt, which apps are
// still producing sound that Now Playing did not cover; each of those that
// HomeSpeaker knows is paused through its own scripting interface, which can
// also tell us whether it was playing. So only what was actually playing is
// paused, and only that is resumed -- and only if it is still paused when the
// announcement ends, so a video the user restarted by hand is left alone.
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

    /// How long one tab may take to answer. A suspended tab (Workona, a
    /// discarded background tab) never answers, and AppleScript's own wait
    /// is 120 seconds -- far past the runner's deadline, so one frozen tab
    /// cost every tab after it.
    static let tabTimeout = "with timeout of 1 second"
    /// AppleScript's "AppleEvent timed out".
    static let timedOut = -1712
    /// What a pause script logs to stderr the moment it pauses a tab.
    static let pausedMarker = "PAUSED:"

    /// One tab's try: run `call` (which sets `r`), and record `handle` and
    /// the host when it paused something. A discarded or chrome:// tab
    /// answers `missing value`, which is not a pause -- counted as one, it
    /// ended the search with nothing actually paused.
    ///
    /// Each pause is also logged to stderr as it happens: stdout is only
    /// written when the script returns, so a script killed at the deadline
    /// lost the tabs it had ALREADY paused, and they stayed paused for good.
    /// A tab that timed out is not an error: it is a frozen tab, not a
    /// browser that refuses.
    private static func attempt(call: String, handle: String) -> String {
        """
                try
                  \(tabTimeout)
                    set r to \(call)
                  end timeout
                  if r is not missing value then
                    if r is not "" then
                      set out to out & \(handle) & ":" & r & ","
                      log "\(pausedMarker)" & \(handle) & ":" & r
                    end if
                  end if
                on error msg number errNum
                  if errNum is not \(timedOut) and firstErr is "" then set firstErr to msg
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
              \(tabTimeout)
                set r to execute (tab id \(tab) of window id \(window)) javascript "\(js)"
              end timeout
              if r is not missing value then
                if (r as integer) > 0 then set done to true
              end if
            end try
            if not done then
              repeat with w in windows
                try
                  \(tabTimeout)
                    execute (tab id \(tab) of w) javascript "\(js)"
                  end timeout
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
                return "\(sweepAll)\nrepeat with t in ts\n  try\n    \(tabTimeout)\n      do JavaScript \"\(js)\" in t\n    end timeout\n  end try\nend repeat"
            }
            let exact = index.map { i in
                """
                try
                  \(tabTimeout)
                    set r to do JavaScript "\(js)" in tab \(i) of window id \(window)
                  end timeout
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
                  \(tabTimeout)
                    do JavaScript "\(js)" in t
                  end timeout
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
    /// Seconds before a hung script is killed.
    let deadline: TimeInterval

    public init() { self.init(deadline: 8) }
    init(deadline: TimeInterval) { self.deadline = deadline }

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
                let killed = Killed()
                DispatchQueue.global().asyncAfter(deadline: .now() + deadline) {
                    if p.isRunning { killed.set(); p.terminate() }
                }
                p.waitUntilExit()
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: Self.result(
                    status: p.terminationStatus, timedOut: killed.value, stdout: o, stderr: e, deadline: deadline))
            }
        }
    }

    /// What one run answers. The tabs a pause script logged as paused are
    /// never lost: when the script was killed or failed after pausing, or
    /// said nothing on stdout, they are answered as if the script had
    /// returned them, so they are held and resumed. A failure always has a
    /// reason -- an empty one read "Could not pause Google Chrome: ."
    static func result(
        status: Int32, timedOut: Bool, stdout: String, stderr: String, deadline: TimeInterval = 8
    ) -> Result<String, ScriptFailure> {
        let paused = pausedEntries(stderr)
        let said = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == 0, !said.isEmpty { return .success(stdout) }
        if !paused.isEmpty { return .success(paused.map { $0 + "," }.joined()) }
        if status == 0 { return .success(stdout) }
        let reason = stderr.split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix(MediaScripts.pausedMarker) }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !reason.isEmpty { return .failure(ScriptFailure(reason)) }
        return .failure(ScriptFailure(timedOut
            ? "it did not answer within \(Int(deadline)) seconds"
            : "osascript stopped with status \(status) and gave no reason"))
    }

    /// The `PAUSED:<handle>:<host>` lines a pause script logged.
    static func pausedEntries(_ stderr: String) -> [String] {
        stderr.split(whereSeparator: \.isNewline).compactMap { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix(MediaScripts.pausedMarker) else { return nil }
            let entry = String(l.dropFirst(MediaScripts.pausedMarker.count))
            return entry.isEmpty ? nil : entry
        }
    }

    /// Set by the deadline timer, read after the process exits.
    private final class Killed: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        var value: Bool { lock.withLock { _value } }
        func set() { lock.withLock { _value = true } }
    }
}

// MARK: - The system's Now Playing (MediaRemote, through /usr/bin/perl)
//
// MediaRemote is what Control Center's Now Playing drives, and it can pause
// ANY app that registers there (Firefox, VLC, IINA, Podcasts, TV ...), not
// only the players above. Since macOS 15.4 mediaremoted ignores it from a
// process Apple did not sign -- which is why it "succeeded and paused
// nothing" here before. /usr/bin/perl is Apple-signed, and it may load this
// very binary (an app, the tool, the test bundle: dyld loads a
// position-independent executable without running its main) and call
// `homespeaker_media_remote_entry`, which then speaks to MediaRemote with
// perl's standing. So no helper file ships: the image that holds this code
// is the one perl loads, found with `dladdr`. The same trick is proven in
// the Vitruvian app (apps/desktop/vitruvian/Sources/NowPlayingAdapter).

/// One Now Playing session HomeSpeaker paused through MediaRemote.
public struct NowPlayingSession: Equatable, Sendable {
    public var pid: Int32
    /// The app's bundle identifier (`com.google.Chrome`, `org.videolan.vlc`).
    public var bundleID: String
    /// The app that owns the session, when the session is a helper's.
    public var parentBundleID: String?
    /// What the person calls the app ("Google Chrome", "VLC").
    public var name: String
    /// What was playing: a song, a video's title. Resume plays the session
    /// again only while it still shows this, so a video the person switched
    /// to meanwhile is never started.
    public var title: String?
    /// MediaRemote's id for the recording. Not stable: Chrome gives a paused
    /// video a new one, so it is never what decides a resume.
    public var item: String?
    /// False when the Pause was taken but the session still read as playing
    /// moments later. It is still held, so a pause that lands late is
    /// resumed (resume only plays what is paused); but its app is not
    /// counted as paused, so the scripts try it too.
    public var confirmed: Bool

    public init(pid: Int32, bundleID: String, parentBundleID: String? = nil, name: String,
                title: String? = nil, item: String? = nil, confirmed: Bool = true) {
        self.pid = pid
        self.bundleID = bundleID
        self.parentBundleID = parentBundleID
        self.name = name
        self.title = title
        self.item = item
        self.confirmed = confirmed
    }

    /// Whether audio from `bundleID` (CoreAudio's answer) is this session's
    /// app: itself, or a helper whose id extends it (Chrome's audio comes
    /// from `com.google.Chrome.helper`).
    func owns(_ audioBundleID: String) -> Bool {
        [bundleID, parentBundleID].compactMap { $0 }.contains { id in
            audioBundleID == id || audioBundleID.hasPrefix(id + ".")
        }
    }

    init?(json: [String: Any], confirmed: Bool = true) {
        guard let pid = (json["pid"] as? NSNumber)?.int32Value, pid > 0,
              let bundleID = json["bundleID"] as? String, !bundleID.isEmpty else { return nil }
        let name = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? bundleID
        self.init(pid: pid, bundleID: bundleID, parentBundleID: json["parentBundleID"] as? String,
                  name: name, title: (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                  item: json["item"] as? String, confirmed: confirmed)
    }
}

/// Pauses and resumes the system's Now Playing sessions. A protocol so tests
/// never touch what the Mac running them is playing.
public protocol NowPlayingRunner: Sendable {
    /// Pauses every session that is playing; answers the ones it sent a
    /// Pause to, each marked with whether it was seen to stop.
    func pausePlaying() async -> Result<[NowPlayingSession], ScriptFailure>
    /// Plays each of `sessions` again -- only if it is still paused on the
    /// same recording, so one the person restarted or changed is left alone.
    func resume(_ sessions: [NowPlayingSession]) async
}

/// No Now Playing at all: what a controller built around a stand-in script
/// runner gets, so a test never pauses the real Mac's music.
public struct NoNowPlaying: NowPlayingRunner {
    public init() {}
    public func pausePlaying() async -> Result<[NowPlayingSession], ScriptFailure> { .success([]) }
    public func resume(_ sessions: [NowPlayingSession]) async {}
}

/// MediaRemote through `/usr/bin/perl`, which loads the image this code is
/// in and calls `homespeaker_media_remote_entry`.
public struct PerlNowPlayingRunner: NowPlayingRunner {
    /// Seconds before a hung perl is killed. What it paused before then is
    /// kept: each pause is written out as it lands.
    let deadline: TimeInterval
    /// The Mach-O image perl loads; nil when it cannot be found.
    let image: String?

    public init() { self.init(deadline: 3, image: NowPlayingRemote.imagePath()) }
    init(deadline: TimeInterval, image: String?) {
        self.deadline = deadline
        self.image = image
    }

    public func pausePlaying() async -> Result<[NowPlayingSession], ScriptFailure> {
        switch await run(action: "pause") {
        case .failure(let e): return .failure(e)
        case .success(let lines): return .success(Self.paused(lines))
        }
    }

    public func resume(_ sessions: [NowPlayingSession]) async {
        guard !sessions.isEmpty else { return }
        _ = await run(action: "resume", sessions: sessions)
    }

    /// Every session MediaRemote knows, read only: for tests and diagnosis.
    func list() async -> Result<[[String: Any]], ScriptFailure> {
        switch await run(action: "list") {
        case .failure(let e): return .failure(e)
        case .success(let lines):
            guard let last = lines.last(where: { $0["clients"] != nil }),
                  let clients = last["clients"] as? [[String: Any]] else {
                return .failure(ScriptFailure(lines.compactMap { $0["error"] as? String }.first
                    ?? "MediaRemote gave no answer"))
            }
            return .success(clients)
        }
    }

    /// The sessions a pause run reported, each once: `paused` (seen to
    /// stop) and `unconfirmed` (took the Pause, still playing just after).
    static func paused(_ lines: [[String: Any]]) -> [NowPlayingSession] {
        var out: [NowPlayingSession] = []
        for line in lines {
            let entry = (line["paused"] as? [String: Any]).map { ($0, true) }
                ?? (line["unconfirmed"] as? [String: Any]).map { ($0, false) }
            guard let (json, confirmed) = entry, let s = NowPlayingSession(json: json, confirmed: confirmed),
                  !out.contains(where: { $0.pid == s.pid }) else { continue }
            out.append(s)
        }
        return out
    }

    /// The perl program: load the image, find the entry, call it. The image
    /// path is an argument, never part of the program text.
    static let perlProgram = """
    use DynaLoader;
    my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die "cannot load: " . DynaLoader::dl_error() . "\\n";
    my $s = DynaLoader::dl_find_symbol($h, "homespeaker_media_remote_entry") or die "no entry: " . DynaLoader::dl_error() . "\\n";
    DynaLoader::dl_install_xsub("main::homespeaker_media_remote", $s);
    homespeaker_media_remote();
    """

    /// The environment perl runs with: this process's, without anything that
    /// would load other code into perl, and with the request.
    static func environment(action: String, sessions: [NowPlayingSession]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { key, _ in
            !key.hasPrefix("PERL") && !key.hasPrefix("DYLD_")
        }
        env["HOMESPEAKER_MR_ACTION"] = action
        env["HOMESPEAKER_MR_PIDS"] = sessions.map { String($0.pid) }.joined(separator: ",")
        let titles = Dictionary(sessions.compactMap { s in s.title.map { (String(s.pid), $0) } },
                                uniquingKeysWith: { a, _ in a })
        if !titles.isEmpty, let data = try? JSONSerialization.data(withJSONObject: titles),
           let text = String(data: data, encoding: .utf8) {
            env["HOMESPEAKER_MR_TITLES"] = text
        }
        return env
    }

    /// Runs one action; answers the JSON lines it wrote.
    func run(action: String, sessions: [NowPlayingSession] = []) async -> Result<[[String: Any]], ScriptFailure> {
        guard let image else { return .failure(ScriptFailure("cannot find HomeSpeaker's own program file")) }
        let deadline = self.deadline
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
                p.arguments = ["-e", Self.perlProgram, image]
                p.environment = Self.environment(action: action, sessions: sessions)
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch {
                    cont.resume(returning: .failure(ScriptFailure(error.localizedDescription))); return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + deadline) { if p.isRunning { p.terminate() } }
                // Read before waiting: a full pipe would block perl forever.
                let o = out.fileHandleForReading.readDataToEndOfFile()
                let e = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let lines = Self.lines(o)
                if lines.isEmpty {
                    let why = (String(data: e, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(returning: .failure(ScriptFailure(why.isEmpty
                        ? "MediaRemote did not answer within \(Int(deadline)) seconds" : why)))
                    return
                }
                cont.resume(returning: .success(lines))
            }
        }
    }

    /// One JSON object per line; anything else is skipped.
    static func lines(_ data: Data) -> [[String: Any]] {
        data.split(separator: UInt8(ascii: "\n")).compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any]
        }
    }
}

/// The half that runs inside `/usr/bin/perl`.
enum NowPlayingRemote {
    /// The image holding this code: the app, the tool or the test bundle.
    static func imagePath() -> String? {
        var info = Dl_info()
        let entry = unsafeBitCast(homespeakerMediaRemoteEntry as @convention(c) () -> Void, to: UnsafeRawPointer.self)
        guard dladdr(entry, &info) != 0, let name = info.dli_fname else { return nil }
        let path = String(cString: name)
        return path.hasPrefix("/") ? path : nil
    }

    // MediaRemote's commands and playback states.
    static let play: Int32 = 0
    static let pause: Int32 = 1
    static let statePlaying: UInt32 = 1
    static let statePaused: UInt32 = 2

    private static let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    private static let callbacks = DispatchQueue(label: "dev.vitruvian.homespeaker.media-remote", attributes: .concurrent)
    private static let output = NSLock()

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private static func constant(_ name: String) -> String? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return symbol.assumingMemoryBound(to: NSString?.self).pointee as String?
    }

    static func emit(_ reply: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{\"error\":\"json\"}".utf8)
        output.lock()
        defer { output.unlock() }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }

    /// One registered Now Playing client, with a player path of its own.
    struct Client {
        let pid: Int32
        let bundleID: String
        let parentBundleID: String?
        let name: String
        let path: NSObject
        let isCurrent: Bool
        var state: UInt32?
        var info: [String: Any] = [:]

        var title: String? {
            (info["kMRMediaRemoteNowPlayingInfoTitle"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        var item: String? { info["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] as? String }
        var rate: Double? { (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue }
        /// Its own state wins; a rate only counts when it gave none.
        var isPlaying: Bool {
            if let state, state != 0 { return state == NowPlayingRemote.statePlaying }
            return (rate ?? 0) > 0
        }

        var session: [String: Any] {
            var s: [String: Any] = ["pid": pid, "bundleID": bundleID, "name": name]
            if let parentBundleID { s["parentBundleID"] = parentBundleID }
            if let title { s["title"] = title }
            if let item { s["item"] = item }
            return s
        }
    }

    /// Every registered client (at most 16) and which one is the system's
    /// current player, with each one's state and what it plays.
    static func clients() -> [Client] {
        typealias ReadClient = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
        typealias ReadClients = @convention(c) (DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void
        typealias PID = @convention(c) (AnyObject) -> Int32
        typealias ClientString = @convention(c) (AnyObject) -> Unmanaged<CFString>?
        guard let getPID = function("MRNowPlayingClientGetProcessIdentifier", as: PID.self) else { return [] }
        let getName = function("MRNowPlayingClientGetDisplayName", as: ClientString.self)
        let getParent = function("MRNowPlayingClientGetParentAppBundleIdentifier", as: ClientString.self)
        let getBundle = function("MRNowPlayingClientGetBundleIdentifier", as: ClientString.self)
        let lock = NSLock()
        var current: Int32?
        var found: [(pid: Int32, name: String?, parent: String?, bundle: String?)] = []
        func record(_ client: AnyObject) {
            let pid = getPID(client)
            guard pid > 0, !found.contains(where: { $0.pid == pid }) else { return }
            found.append((pid, getName?(client)?.takeUnretainedValue() as String?,
                          getParent?(client)?.takeUnretainedValue() as String?,
                          getBundle?(client)?.takeUnretainedValue() as String?))
        }
        let group = DispatchGroup()
        if let getClient = function("MRMediaRemoteGetNowPlayingClient", as: ReadClient.self) {
            group.enter()
            getClient(callbacks) { client in
                lock.withLock {
                    if let client { current = getPID(client); record(client) }
                }
                group.leave()
            }
        }
        if let getClients = function("MRMediaRemoteGetNowPlayingClients", as: ReadClients.self) {
            group.enter()
            getClients(callbacks) { list in
                lock.withLock {
                    for client in (list as? [AnyObject] ?? []).prefix(16) { record(client) }
                }
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 0.5)
        let (currentPID, listed) = lock.withLock { (current, found) }
        var clients: [Client] = []
        for c in listed {
            let app = NSRunningApplication(processIdentifier: c.pid)
            guard app?.isTerminated != true,
                  let bundleID = app?.bundleIdentifier ?? c.bundle, !bundleID.isEmpty,
                  let path = makePath(pid: c.pid, bundleID: bundleID) else { continue }
            let name = [c.name, app?.localizedName].compactMap { $0?.nilIfEmpty }.first ?? bundleID
            clients.append(Client(pid: c.pid, bundleID: bundleID,
                                  parentBundleID: c.parent?.nilIfEmpty.flatMap { $0 == bundleID ? nil : $0 },
                                  name: name, path: path, isCurrent: c.pid == currentPID))
        }
        // Each one's state and what it plays, all at once.
        let reads = DispatchGroup()
        for i in clients.indices {
            let path = clients[i].path
            reads.enter()
            readState(path) { state in
                lock.withLock { clients[i].state = state }
                reads.leave()
            }
            reads.enter()
            readInfo(path) { info in
                lock.withLock { clients[i].info = info }
                reads.leave()
            }
        }
        _ = reads.wait(timeout: .now() + 0.5)
        return lock.withLock { clients }
    }

    /// A player path of this app's own (as `NotchNativePlayback.makeTarget`
    /// in the Vitruvian app): a copy of the local path, never the shared one.
    static func makePath(pid: Int32, bundleID: String) -> NSObject? {
        guard let pathClass = NSClassFromString("MRPlayerPath"),
              let clientClass = NSClassFromString("MRClient"),
              class_getClassMethod(pathClass, NSSelectorFromString("localPlayerPath")) != nil,
              class_getInstanceMethod(clientClass, NSSelectorFromString("initWithBundleIdentifier:")) != nil,
              let local = (pathClass as AnyObject).perform(NSSelectorFromString("localPlayerPath"))?
                .takeUnretainedValue() as? NSObject,
              let path = local.copy() as? NSObject,
              let allocation = (clientClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeRetainedValue(),
              let client = allocation.perform(NSSelectorFromString("initWithBundleIdentifier:"), with: bundleID)?
                .takeUnretainedValue() as? NSObject else { return nil }
        typealias SetPID = @convention(c) (AnyObject, Selector, Int32) -> Void
        let setPID = NSSelectorFromString("setProcessIdentifier:")
        guard client.responds(to: setPID), path.responds(to: NSSelectorFromString("setClient:")),
              path.responds(to: NSSelectorFromString("setPlayer:")) else { return nil }
        unsafeBitCast(client.method(for: setPID), to: SetPID.self)(client, setPID, pid)
        path.perform(NSSelectorFromString("setClient:"), with: client)
        // Nil: this app's active player.
        path.perform(NSSelectorFromString("setPlayer:"), with: nil)
        return path
    }

    static func readState(_ path: NSObject, completion: @escaping (UInt32?) -> Void) {
        typealias Read = @convention(c) (AnyObject, DispatchQueue, @escaping @convention(block) (UInt32) -> Void) -> Void
        guard let read = function("MRMediaRemoteGetPlaybackStateForPlayer", as: Read.self) else { completion(nil); return }
        read(path, callbacks) { completion($0) }
    }

    static func readInfo(_ path: NSObject, completion: @escaping ([String: Any]) -> Void) {
        typealias Read = @convention(c) (AnyObject, Bool, DispatchQueue,
            @escaping @convention(block) (NSDictionary?, UnsafeRawPointer?) -> Void) -> Void
        guard let read = function("MRMediaRemoteGetNowPlayingInfoForPlayer", as: Read.self) else { completion([:]); return }
        read(path, false, callbacks) { info, _ in completion((info as? [String: Any]) ?? [:]) }
    }

    /// The state now, waiting at most `timeout`.
    static func state(_ path: NSObject, timeout: TimeInterval = 0.3) -> UInt32? {
        let group = DispatchGroup()
        let lock = NSLock()
        var answer: UInt32?
        group.enter()
        readState(path) { s in lock.withLock { answer = s }; group.leave() }
        _ = group.wait(timeout: .now() + timeout)
        return lock.withLock { answer }
    }

    static func info(_ path: NSObject, timeout: TimeInterval = 0.3) -> [String: Any] {
        let group = DispatchGroup()
        let lock = NSLock()
        var answer: [String: Any] = [:]
        group.enter()
        readInfo(path) { i in lock.withLock { answer = i }; group.leave() }
        _ = group.wait(timeout: .now() + timeout)
        return lock.withLock { answer }
    }

    /// The system's current player's process, now.
    static func currentPID() -> Int32? {
        typealias Read = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
        typealias PID = @convention(c) (AnyObject) -> Int32
        guard let read = function("MRMediaRemoteGetNowPlayingClient", as: Read.self),
              let getPID = function("MRNowPlayingClientGetProcessIdentifier", as: PID.self) else { return nil }
        let group = DispatchGroup()
        let lock = NSLock()
        var pid: Int32?
        group.enter()
        read(callbacks) { c in lock.withLock { pid = c.map(getPID) }; group.leave() }
        _ = group.wait(timeout: .now() + 0.3)
        return lock.withLock { pid }
    }

    /// Sends `command` (an explicit Play or Pause, never the toggle) to one
    /// client's player: scoped to the recording when there is one, then
    /// without. Answers whether the player took it.
    ///
    /// mediaremoted may hand an unscoped command to the system's current
    /// player instead. A stray Pause is harmless; a stray Play could start
    /// something the person paused themselves, so Play goes unscoped only
    /// to the current player, or to one with no recording id to scope to.
    static func send(_ command: Int32, to client: Client) -> Bool {
        typealias Send = @convention(c) (Int32, CFDictionary?, AnyObject, UInt32, DispatchQueue,
            @escaping @convention(block) (UInt32, NSArray?) -> Void) -> Bool
        guard let send = function("MRMediaRemoteSendCommandToPlayer", as: Send.self) else { return false }
        var attempts: [CFDictionary?] = []
        if let item = client.item, let key = constant("kMRMediaRemoteOptionNowPlayingContentItemID") {
            attempts.append([key: item] as CFDictionary)
        }
        if command != play || client.isCurrent || attempts.isEmpty { attempts.append(nil) }
        for options in attempts {
            let group = DispatchGroup()
            let lock = NSLock()
            var delivered = false
            group.enter()
            let accepted = send(command, options, client.path, 0, callbacks) { error, responses in
                lock.withLock {
                    delivered = error == 0
                        && (responses as? [NSNumber]).map { $0.isEmpty || $0.contains { $0.intValue == 0 } } != false
                }
                group.leave()
            }
            guard accepted else { continue }
            guard group.wait(timeout: .now() + 0.6) == .success else { continue }
            if lock.withLock({ delivered }) { return true }
        }
        return false
    }

    /// The system-wide command, for when `client` is the current player and
    /// the direct send did not land. Checked again right before sending, so
    /// it never reaches a player that took over meanwhile.
    static func sendToCurrent(_ command: Int32, client: Client) -> Bool {
        typealias Send = @convention(c) (Int32, CFDictionary?) -> Bool
        guard currentPID() == client.pid,
              let send = function("MRMediaRemoteSendCommand", as: Send.self) else { return false }
        return send(command, nil)
    }

    /// Waits up to `timeout` for `path` to leave (or reach) playing.
    static func settle(_ path: NSObject, playing: Bool, timeout: TimeInterval) -> UInt32? {
        let end = Date().addingTimeInterval(timeout)
        var last: UInt32?
        repeat {
            Thread.sleep(forTimeInterval: 0.06)
            last = state(path, timeout: 0.2)
            if let last, (last == statePlaying) == playing { return last }
        } while Date() < end
        return last
    }

    /// Pauses every client that is playing, in parallel. Each confirmed
    /// pause is written the moment it lands, so a kill at the deadline
    /// cannot lose it.
    static func pauseAll() {
        let playing = clients().filter(\.isPlaying)
        let group = DispatchGroup()
        for client in playing {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                var sent = send(pause, to: client)
                if !sent { sent = sendToCurrent(pause, client: client) }
                guard sent else { emit(["failed": client.session, "reason": "not delivered"]); return }
                let after = settle(client.path, playing: false, timeout: 0.6)
                if let after, after != statePlaying {
                    emit(["paused": client.session])
                } else if after == nil, (info(client.path, timeout: 0.2)["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue == 0 {
                    emit(["paused": client.session])
                } else {
                    emit(["unconfirmed": client.session])
                }
            }
        }
        _ = group.wait(timeout: .now() + 2)
        emit(["done": true, "playing": playing.count])
    }

    /// Plays each paused client again -- only if it is the same app, still
    /// paused, and showing the same title when one was recorded.
    static func resume(pids: [Int32], titles: [String: String]) {
        let all = clients()
        var resumed: [Int32] = []
        for pid in pids {
            guard let client = all.first(where: { $0.pid == pid }), !client.isPlaying else { continue }
            if let expected = titles[String(pid)], let now = client.title, now != expected { continue }
            if client.state.map({ $0 != statePaused && $0 != 0 }) == true { continue }
            var sent = send(play, to: client)
            if !sent { sent = sendToCurrent(play, client: client) }
            if sent { resumed.append(pid) }
        }
        emit(["done": true, "resumed": resumed.map { Int($0) }])
    }

    /// Every client, read only.
    static func list() {
        emit(["clients": clients().map { c -> [String: Any] in
            var s = c.session
            s["state"] = Int(c.state ?? 0)
            s["playing"] = c.isPlaying
            s["current"] = c.isCurrent
            return s
        }])
    }
}

/// Called by `/usr/bin/perl` (`PerlNowPlayingRunner`), never by HomeSpeaker
/// itself. `HOMESPEAKER_MR_ACTION` is `pause`, `resume` (the processes in
/// `HOMESPEAKER_MR_PIDS`, with their titles in `HOMESPEAKER_MR_TITLES`) or
/// `list`; the answer is JSON lines on stdout.
@_cdecl("homespeaker_media_remote_entry")
public func homespeakerMediaRemoteEntry() {
    let env = ProcessInfo.processInfo.environment
    let pids = (env["HOMESPEAKER_MR_PIDS"] ?? "").split(separator: ",")
        .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    let titles = (env["HOMESPEAKER_MR_TITLES"]?.data(using: .utf8))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
    switch env["HOMESPEAKER_MR_ACTION"] {
    case "pause": NowPlayingRemote.pauseAll()
    case "resume": NowPlayingRemote.resume(pids: pids, titles: titles)
    case "list": NowPlayingRemote.list()
    default: NowPlayingRemote.emit(["error": "unknown action"])
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Pausing one player

public struct MediaController: Sendable {
    let runner: ScriptRunner
    /// The system's Now Playing, tried before any script.
    let nowPlaying: NowPlayingRunner

    /// The live controller: MediaRemote first, scripts for the rest.
    public init() { self.init(runner: OSAScriptRunner(), nowPlaying: PerlNowPlayingRunner()) }

    /// Around `runner`; Now Playing only when given. A stand-in runner means
    /// a test, which must never pause what the Mac running it plays.
    public init(runner: ScriptRunner, nowPlaying: NowPlayingRunner = NoNowPlaying()) {
        self.runner = runner
        self.nowPlaying = nowPlaying
    }

    public func pauseNowPlaying() async -> Result<[NowPlayingSession], ScriptFailure> {
        await nowPlaying.pausePlaying()
    }

    public func resume(_ sessions: [NowPlayingSession]) async {
        await nowPlaying.resume(sessions)
    }

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
        let words = spokenWords(in: spoken)
        return min(max(2.5 + Double(words) / 2.5 + max(extra, 0), 3), 120)
    }

    /// Spoken word-equivalents in `spoken`, accounting for compound tokens
    /// (`feat/homespeaker-system`, `MediaPause.swift`), multi-digit numbers
    /// (`#3484` -> "number three thousand four hundred eighty-four"), and
    /// prosodic pauses between sentences and clauses.
    public static func spokenWords(in spoken: String) -> Int {
        let trimmed = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        // Keep contractions ("don't", "James's") together as one word, and
        // split camelCase ("MediaPause" -> "Media Pause") into sub-words.
        let chars = Array(trimmed)
        var normalized = String()
        normalized.reserveCapacity(chars.count + 8)
        var symbolWords = 0
        for i in chars.indices {
            let c = chars[i]
            let prev = i > 0 ? chars[i - 1] : nil
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            if (c == "'" || c == "\u{2019}"), prev?.isLetter == true, next?.isLetter == true {
                continue
            }
            if c == "#", next?.isNumber == true {
                symbolWords += 1
            } else if c == "%", prev?.isNumber == true {
                symbolWords += 1
            }
            if let prev, prev.isLowercase, c.isUppercase {
                normalized.append(" ")
            } else if let prev, prev.isLetter != c.isLetter, (prev.isLetter || prev.isNumber), (c.isLetter || c.isNumber) {
                normalized.append(" ")
            }
            normalized.append(c)
        }

        let tokens = normalized.split { !$0.isLetter && !$0.isNumber }
        var count = symbolWords
        for token in tokens {
            if token.allSatisfy(\.isNumber) {
                // Multi-digit numbers ("3484", "150") take ~1 spoken word per digit.
                count += min(max(token.count, 1), 10)
            } else {
                count += 1
            }
        }

        // Internal sentence and clause boundaries add ~0.4 s (1 word-equivalent)
        // of prosodic pause before the next clause starts.
        var pauses = 0
        for i in chars.indices {
            let c = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            let hasLaterWord = chars[(i + 1)...].contains { $0.isLetter || $0.isNumber }
            guard hasLaterWord else { break }
            if (c == "." || c == "!" || c == "?" || c == ";" || c == ":"), next?.isWhitespace == true {
                pauses += 1
            } else if c == "\u{2014}" || (c == "-" && next == "-" && i > 0 && chars[i - 1].isWhitespace) {
                pauses += 1
            }
        }

        return count + pauses
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

    /// One announcement's hold lease in the active queue.
    ///
    /// A single announcement calls `pause(for:id:)` before its network call
    /// and `extend(for:id:)` with the same `id` once the speaker starts:
    /// updating that lease in place resets its clock without double-counting.
    /// A second announcement arriving while the first is still speaking gets
    /// its own lease and stacks after the previous lease ends instead of
    /// being swallowed by `max(...)`.
    private struct HoldLease {
        let id: String
        var anchoredAt: Date
        var duration: Double
    }

    private let controller: MediaController
    private let audio: @Sendable () -> Set<String>
    private let safariRunning: @MainActor () -> Bool
    private var held: [PausedMedia] = []
    /// Now Playing sessions paused through MediaRemote.
    private var heldSessions: [NowPlayingSession] = []
    /// Why MediaRemote could not be used on the last pause, if it could
    /// not: the scripts then did all the work. For diagnosis only.
    public private(set) var mediaRemoteProblem: String?
    private var leases: [HoldLease] = []
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

    /// Pauses what is playing for `seconds`, or stacks onto an existing hold.
    public func pause(for seconds: Double, id: String? = nil) async {
        await enqueue { await $0.performPause(seconds, id: id) }.value
    }

    /// Keeps what is already paused paused for at least `seconds` more.
    /// Unlike `pause(for:)` it never pauses anything new: when this Mac
    /// finishes speaking after the hold ran out, whatever the user started
    /// since must be left alone. Queued behind a pause still under way, so
    /// it extends what that pause holds rather than being dropped.
    public func extend(for seconds: Double, id: String? = nil) {
        enqueue { $0.performExtend(seconds, id: id) }
    }

    /// Resumes now: the announcement failed, or the app is quitting. When
    /// `id` is given, only that announcement's lease is dropped so an
    /// earlier announcement still speaking keeps its hold.
    public func resumeNow(id: String? = nil) async {
        if id == nil {
            resumeTask?.cancel()
            resumeTask = nil
        }
        await enqueue { await $0.performResume(id: id) }.value
    }

    /// Returns once nothing is held: at once when nothing is, otherwise
    /// when the hold runs out or is resumed. A lone `--say` waits on this,
    /// so it does not exit with the media it paused still paused.
    public func waitUntilReleased() async {
        await tail?.value
        guard isHolding else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    /// Start and end of each lease in order, stacked so each one starts no
    /// earlier than the previous one ends.
    private func resolvedLeases() -> [(id: String, start: Date, end: Date)] {
        var out: [(id: String, start: Date, end: Date)] = []
        out.reserveCapacity(leases.count)
        for lease in leases {
            let previousEnd = out.last?.end ?? lease.anchoredAt
            let start = max(previousEnd, lease.anchoredAt)
            let end = start.addingTimeInterval(max(lease.duration, 0))
            out.append((lease.id, start, end))
        }
        return out
    }

    private func recomputeResumeAt(now: Date = Date()) {
        let resolved = resolvedLeases()
        guard let lastEnd = resolved.last?.end, lastEnd > now else {
            leases = []
            resumeAt = nil
            return
        }
        resumeAt = min(lastEnd, now.addingTimeInterval(120))
    }

    private func addOrUpdateLease(seconds: Double, id: String?, now: Date = Date()) {
        if let id, let idx = leases.firstIndex(where: { $0.id == id }) {
            extendLease(at: idx, seconds: seconds, now: now)
        } else {
            if leases.count >= 64, let end = resolvedLeases().last?.end {
                leases = [HoldLease(id: UUID().uuidString, anchoredAt: now, duration: max(end.timeIntervalSince(now), 0))]
            }
            leases.append(HoldLease(id: id ?? UUID().uuidString, anchoredAt: now, duration: max(seconds, 0)))
        }
        recomputeResumeAt(now: now)
    }

    private func extendLease(at idx: Int, seconds: Double, now: Date = Date()) {
        let resolved = resolvedLeases()
        let current = resolved[idx]
        if now <= current.start {
            leases[idx].anchoredAt = max(leases[idx].anchoredAt, now)
            leases[idx].duration = max(leases[idx].duration, max(seconds, 0))
        } else {
            let remaining = max(current.end.timeIntervalSince(now), 0)
            leases[idx].anchoredAt = now
            leases[idx].duration = max(remaining, max(seconds, 0))
        }
    }

    private func performPause(_ seconds: Double, id: String? = nil) async {
        if resumeAt != nil {
            addOrUpdateLease(seconds: seconds, id: id)
            schedule()
            return
        }
        // Who is making sound, read BEFORE anything is paused: an app keeps
        // its output open a moment after it stops.
        let sounding = audio()
        // The system's Now Playing first: it pauses any app that registers
        // there, browsers included, with no Automation prompt.
        var problems: [String] = []
        var sessions: [NowPlayingSession] = []
        switch await controller.pauseNowPlaying() {
        case .success(let s): sessions = s; mediaRemoteProblem = nil
        case .failure(let e): mediaRemoteProblem = e.message
        }
        // What is still sounding and Now Playing did not pause: a player that
        // does not register there, or one whose pause did not land.
        let confirmed = sessions.filter(\.confirmed)
        let handledPlayers = Set(confirmed.flatMap { s in
            MediaPlayer.players(producing: Set([s.bundleID, s.parentBundleID].compactMap { $0 }),
                                safariRunning: true).players
        })
        let remaining = sounding.filter { id in
            !confirmed.contains { $0.owns(id) }
                && !MediaPlayer.players(producing: [id], safariRunning: true).players.contains { handledPlayers.contains($0) }
        }
        let (players, unsupported) = MediaPlayer.players(producing: remaining, safariRunning: safariRunning())
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
        for (p, outcome) in outcomes {
            switch outcome {
            case .paused(let m): paused.append(m)
            case .nothingPlaying: break
            case .blocked(let why): problems.append("\(p.rawValue): \(Self.explain(why))")
            }
        }
        if !paused.isEmpty || !sessions.isEmpty {
            // Added to, never replaced: what is held is what gets resumed.
            for m in paused { hold(m) }
            for s in sessions where !heldSessions.contains(where: { $0.pid == s.pid }) { heldSessions.append(s) }
            // Counted from when the pause landed: in the app the announcement
            // is sent only after this returns, so that is when speech starts.
            addOrUpdateLease(seconds: seconds, id: id)
            isHolding = true
            schedule()
        }
        lastPauseHadProblems = !problems.isEmpty || !unsupported.isEmpty
        lastReport = Self.report(paused: paused, problems: problems, sessions: confirmed, unsupported: unsupported)
    }

    private func hold(_ m: PausedMedia) {
        if let i = held.firstIndex(where: { $0.player == m.player }) {
            held[i] = held[i].merging(m)
        } else {
            held.append(m)
        }
    }

    private func performExtend(_ seconds: Double, id: String? = nil) {
        guard resumeAt != nil, !leases.isEmpty else { return }
        let idx: Int
        if let id, let found = leases.firstIndex(where: { $0.id == id }) {
            idx = found
        } else {
            idx = leases.indices.last!
        }
        let now = Date()
        extendLease(at: idx, seconds: seconds, now: now)
        recomputeResumeAt(now: now)
        schedule()
    }

    private func performResume(id: String? = nil) async {
        if let id {
            leases.removeAll { $0.id == id }
            recomputeResumeAt()
            if resumeAt != nil {
                schedule()
                return
            }
        }
        resumeTask?.cancel()
        resumeTask = nil
        let toResume = held
        let sessions = heldSessions
        held = []
        heldSessions = []
        leases = []
        resumeAt = nil
        isHolding = false
        if !sessions.isEmpty { await controller.resume(sessions) }
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

    nonisolated static func report(
        paused: [PausedMedia], problems: [String], sessions: [NowPlayingSession] = [], unsupported: [String] = []
    ) -> String? {
        var parts: [String] = []
        let names = sessions.map { s in s.title.map { "\(s.name) (\($0))" } ?? s.name }
            + paused.map { m in
                m.sites.isEmpty ? m.player.rawValue : "\(m.player.rawValue) (\(m.sites.joined(separator: ", ")))"
            }
        if !names.isEmpty { parts.append("Paused " + names.joined(separator: ", ") + ".") }
        if !problems.isEmpty { parts.append("Could not pause " + problems.joined(separator: "; ") + ".") }
        if !unsupported.isEmpty {
            parts.append("Could not pause \(unsupported.joined(separator: ", ")) -- HomeSpeaker does not know how to control it.")
        }
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
        seconds: Double, id: String? = nil, profile: HomeSpeakerProfile = .current, route: RequestRoute = .live(),
        makeOwn: @escaping @MainActor () -> MediaPauseCoordinator = { MediaPauseCoordinator() }
    ) async {
        let destination = await MainActor.run { () -> Destination in
            let d = destination(for: profile, route: route, makeOwn: makeOwn)
            destinations[profile.messagePrefix] = d
            return d
        }
        switch destination {
        case .coordinator(let c):
            await c.pause(for: seconds, id: id)
        case .post(let listener):
            var payload: [String: Any] = ["action": "pause", "seconds": seconds]
            if let id { payload["id"] = id }
            post(payload, to: listener)
            // Give the app a moment to pause before the chime starts.
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    /// Keep media paused `seconds` longer, if anything is paused.
    public static func extend(
        seconds: Double, id: String? = nil, profile: HomeSpeakerProfile = .current, route: RequestRoute = .live()
    ) async {
        switch await sentTo(profile, route: route) {
        case .coordinator(let c): await c.extend(for: seconds, id: id)
        case .post(let listener):
            var payload: [String: Any] = ["action": "extend", "seconds": seconds]
            if let id { payload["id"] = id }
            post(payload, to: listener)
        case nil: break
        }
    }

    public static func resumeNow(id: String? = nil, profile: HomeSpeakerProfile = .current, route: RequestRoute = .live()) async {
        switch await sentTo(profile, route: route) {
        case .coordinator(let c): await c.resumeNow(id: id)
        case .post(let listener):
            var payload: [String: Any] = ["action": "resume"]
            if let id { payload["id"] = id }
            post(payload, to: listener)
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
            let id = note.userInfo?["id"] as? String
            Task { @MainActor in
                if action == "resume" { await coordinator.resumeNow(id: id) }
                else if action == "extend" { coordinator.extend(for: min(seconds, 120), id: id) }
                else if seconds > 0 { await coordinator.pause(for: min(seconds, 120), id: id) }
            }
        }
    }
}
