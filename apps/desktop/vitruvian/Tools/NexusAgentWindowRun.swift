// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

// Runs this app's real Quick Prompt window and checks what a person meets in
// it: that typing lands in the prompt, that the caret follows the
// conversation, what Esc and ⌘W do, what the app would say about a turn
// that ends out of sight, and that a diagram in a reply is drawn. It is a
// developer's tool, run by hand, and not a test that CI runs:
//
//   bazel run --config=macos-app //apps/desktop/vitruvian:nexus_agent_window_run -- [<Vitruvian.zip or Vitruvian.app>]
//
// IT SHOWS A WINDOW. The Quick Prompt is on your screen three times, for
// under ten seconds in all, and it takes the keyboard while it is there, as
// it does in the app. Do not type or click until the run has printed its
// count: a key pressed meanwhile goes into the prompt, and a click outside
// the window hides it, by design, which fails the checks that follow. The
// run prints how long the window was on screen (a second and a half, when
// measured), and ends itself if that passes nine seconds.
//
// With the screen locked the window is under the lock screen, and the
// window server may keep the keyboard from it. The run says so and makes
// the same checks, unchanged. If any of the window's checks then fails, the
// run ends INCOMPLETE (status 75): the lock alone can be why, so those are
// checks not made, and not findings about the app.
//
// What is real:
// - `NexusAgentService`, this app's own subclass of the shared engine, and
//   the way it shows the window: the method the global shortcut calls
//   (`toggleQuickPrompt`), so its panel, its key and click monitors and its
//   resizing are the app's. That includes its watch for a click outside
//   the panel, which only listens, and only while the panel is up.
// - The view in the panel: `NexusAgentQuickPromptView`, built as
//   `UIServiceViewFactory` builds it, around the shared chat view.
// - The keys. Each is a key event posted to this program's own event queue
//   and sent on by its event loop, which is the way a key the user presses
//   reaches the service's key monitor and then the field with the caret.
//   None is posted to the whole Mac (`CGEvent` is never used), so nothing
//   can be typed into another app.
// - The diagram: the card's own web view, with the copy of Mermaid found
//   from the main bundle. This tool is built as an app for that reason: the
//   lookup reads the main bundle's resources, where Bazel puts the copy for
//   this tool exactly as it does for the app.
//
// What stands in:
// - The agent. No program is started: a turn is "run" by keeping what the
//   service would have started it with, and its output and its exit are
//   handed over from here, when the run wants them.
// - The files. The service is built over files held in memory, as the unit
//   tests' `Rig` is.
// - The host. The service is handed one that keeps the notices it is given
//   and works out, with `VitruvianNexusAgentHost`'s own rule, what the app
//   would show for each. Nothing is shown: no notch notice, no sound, no
//   notification.
//
// What it never does: start an agent or the bot, register the global
// shortcut, post a notification, play a sound, build or speak to the notch
// island, or read the user's own files and settings.
// - The whole run happens in a second copy of this program whose home
//   folder is a throwaway one (CFFIXED_USER_HOME); that copy refuses to
//   start if its home is still the user's.
// - Settings cannot be sent to the throwaway home (see
//   Tools/NexusAgentChatSnapshots.swift, which meets the same thing), so
//   the tool uses two settings domains of its own and never the app's: one
//   handed to the service, and this program's own. Both are emptied at the
//   end and their files removed, by name.
//
// With a path given, the built app is checked too, without being started:
// the copy of Mermaid is looked for in that bundle the way the app looks
// for it, and a diagram is drawn with it in a web view no window holds.
//
// Two things in its output need a word. WebKit prints one line of its own,
// "sandbox_extension_issue_file_to_process failed", about the temporary
// folder Bazel unpacks this program into; the pages draw all the same. And
// after the count the program waits fifteen seconds before it ends, which
// is the clearing up of its settings files.
//
// What it does not check:
// - The pointer. Nothing is clicked or hovered: the session list and the
//   model name's editor are opened by what their buttons call, and the
//   window is shown and hidden by keys and by the shortcut's own method.
// - The notch. The chat docked in the island is not run here: the island's
//   Escape is covered by the unit tests (`notchEscapeClosesTheModelEditorFirst`).
// - The shortcut itself, the real agent, and the built app's own window.

import AppKit
import NexusAgentUI
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI
import WebKit

// MARK: - A home of its own

let scratchKey = "NEXUS_AGENT_WINDOW_RUN_SCRATCH"
let builtAppKey = "NEXUS_AGENT_WINDOW_RUN_BUILT_APP"

func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data("nexus_agent_window_run: \(message)\n".utf8))
    exit(status)
}

func resolved(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

/// The user's home as the system's own records give it, whatever the
/// environment says.
func usersOwnHome() -> String {
    guard let record = getpwuid(getuid()), let directory = record.pointee.pw_dir else {
        fail("cannot tell which home folder is the user's, so cannot be sure of avoiding it", status: 70)
    }
    return resolved(String(cString: directory))
}

let givenPaths = Array(CommandLine.arguments.dropFirst())
guard givenPaths.count <= 1, givenPaths.allSatisfy({ $0.hasPrefix("/") && ($0.hasSuffix(".zip") || $0.hasSuffix(".app")) }) else {
    fail("usage: nexus_agent_window_run [<absolute path of the built Vitruvian.zip or Vitruvian.app>]", status: 64)
}

/// The app's settings, which this tool must never read or write; the domain
/// the service is handed; and this program's own, which `UserDefaults.standard`
/// is here.
let appDomain = "com.vitruviansoftware.vitruvian"
let serviceDomain = appDomain + ".window-run.nexus-agent"
let ownDomain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
guard ownDomain != appDomain, !ownDomain.contains("/") else {
    fail("refusing to run: this program's settings domain is \(ownDomain), which would be the app's", status: 78)
}

/// Removes the two settings files this tool leaves in the account's real
/// Library/Preferences. The settings daemon writes an emptied domain to
/// disk when it gets round to it, so a file removed at once comes back:
/// on macOS 27 that was eight to nine seconds after the second copy ended,
/// measured. This keeps looking until none has been there for fifteen.
func removeOwnSettingsFiles() {
    let folder = usersOwnHome() + "/Library/Preferences/"
    let files = [serviceDomain, ownDomain].map { folder + $0 + ".plist" }
    let look: TimeInterval = 0.25
    let enough: TimeInterval = 15
    var quiet: TimeInterval = 0
    var waited: TimeInterval = 0
    print("clearing up: waiting \(Int(enough)) s for the settings daemon to let go of this tool's two settings files")
    while quiet < enough, waited < 90 {
        let present = files.filter { FileManager.default.fileExists(atPath: $0) }
        for file in present { try? FileManager.default.removeItem(atPath: file) }
        quiet = present.isEmpty ? quiet + look : 0
        Thread.sleep(forTimeInterval: look)
        waited += look
    }
    if quiet < enough {
        FileHandle.standardError.write(Data("nexus_agent_window_run: its settings files in \(folder) did not stay removed\n".utf8))
    }
}

guard let scratch = ProcessInfo.processInfo.environment[scratchKey] else {
    // The first copy only makes the throwaway home, unpacks the built app
    // if one was named, runs the second copy, and clears up. It reads no
    // settings and shows nothing.
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-agent-window-run-\(getpid())", isDirectory: true)
    let home = scratch.appendingPathComponent("home", isDirectory: true)
    guard let program = Bundle.main.executableURL else { fail("cannot find its own program file", status: 70) }
    do {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var environment = ProcessInfo.processInfo.environment
        environment[scratchKey] = scratch.path
        environment["CFFIXED_USER_HOME"] = home.path
        environment["HOME"] = home.path
        if let given = givenPaths.first {
            if given.hasSuffix(".zip") {
                // The archive Bazel wrote holds the app at its top.
                let unpacked = scratch.appendingPathComponent("built-app", isDirectory: true)
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = ["-q", given, "-d", unpacked.path]
                try unzip.run()
                unzip.waitUntilExit()
                let apps = ((try? FileManager.default.contentsOfDirectory(atPath: unpacked.path)) ?? [])
                    .filter { $0.hasSuffix(".app") }
                guard unzip.terminationStatus == 0, apps.count == 1 else {
                    try? FileManager.default.removeItem(at: scratch)
                    fail("could not unpack one app from \(given)", status: 66)
                }
                environment[builtAppKey] = unpacked.appendingPathComponent(apps[0]).path
            } else {
                environment[builtAppKey] = given
            }
        }
        let copy = Process()
        copy.executableURL = program
        copy.environment = environment
        try copy.run()
        copy.waitUntilExit()
        try? FileManager.default.removeItem(at: scratch)
        removeOwnSettingsFiles()
        exit(copy.terminationStatus)
    } catch {
        try? FileManager.default.removeItem(at: scratch)
        fail("could not start in a throwaway home: \(error.localizedDescription)", status: 70)
    }
}

// From here on this is the second copy. It runs only if every way of asking
// for the home folder gives the throwaway one.
let privateHome = resolved(scratch + "/home")
let ownHome = usersOwnHome()
guard resolved(NSHomeDirectory()) == privateHome,
      resolved(FileManager.default.homeDirectoryForCurrentUser.path) == privateHome,
      privateHome != ownHome, !privateHome.hasPrefix(ownHome + "/"), !ownHome.hasPrefix(privateHome + "/") else {
    fail("refusing to run: the home folder is \(NSHomeDirectory()), not the throwaway \(privateHome)", status: 78)
}
print("home: \(NSHomeDirectory())")
print("settings domains: \(serviceDomain), \(ownDomain)")

// MARK: - The count

var passed = 0
var failed = 0
var notChecked = 0

func check(_ ok: Bool, _ what: String) {
    print((ok ? "PASS  " : "FAIL  ") + what)
    if ok { passed += 1 } else { failed += 1 }
}

/// A check the run could not make, with why. It is neither a pass nor a
/// failure, and the count says how many there were.
func couldNotCheck(_ what: String) {
    print("NOT CHECKED  " + what)
    notChecked += 1
}

func note(_ what: String) {
    print("NOTE  " + what)
}

// MARK: - A Mac in memory

/// The files the service is shown and the agent it believes it started.
/// Nothing here reaches a disk or a process.
final class Rig {
    let defaults: UserDefaults
    let home: String
    var files: [String: String] = [:]
    /// The programs that are "installed". The agent is one while its path
    /// is in here, and missing once it is taken out.
    var executables: Set<String> = []
    var sessions: [NexusAgentSessionSummary] = []
    /// The arguments of every turn the service started, in order.
    var agentRuns: [[String]] = []
    var agentOutput: (@MainActor @Sendable (Data) -> Void)?
    var agentExit: (@MainActor @Sendable (Int32) -> Void)?
    /// How often the service told a running agent to stop.
    var agentTerminations = 0

    /// Where the engine looks for agy first, under the home it is given.
    var agy: String { home + "/.local/bin/agy" }

    init(home: String) {
        self.home = home
        guard let defaults = UserDefaults(suiteName: serviceDomain) else {
            fail("could not open a settings domain of its own", status: 70)
        }
        defaults.removePersistentDomain(forName: serviceDomain)
        // The feature is installed, as it is for a user who has the prompt.
        defaults.set(true, forKey: AppFeature.nexusAgent.availabilityKey)
        self.defaults = defaults
    }

    var environment: NexusAgentService.Environment {
        NexusAgentService.Environment(
            defaults: defaults,
            home: home,
            processEnvironment: ["PATH": "/usr/bin"],
            stateDirectory: home + "/Library/Application Support/NexusAgent",
            isExecutable: { [unowned self] in executables.contains($0) },
            fileExists: { [unowned self] in files[$0] != nil || executables.contains($0) },
            readFile: { [unowned self] in files[$0] },
            readTail: { [unowned self] path, _ in files[path] },
            writePrivateFile: { [unowned self] path, content in
                files[path] = content
                return true
            },
            removeFile: { [unowned self] in files[$0] = nil },
            isBotProcess: { _ in false },
            signal: { _, _ in },
            launchBot: { _, _, _, _, _ in throw CocoaError(.featureUnsupported) },
            schedule: { _, _ in },
            openFile: { _ in },
            launchAgent: { [unowned self] _, arguments, _, _, onOutput, onExit in
                agentRuns.append(arguments)
                agentOutput = onOutput
                agentExit = onExit
                return NexusAgentRunningAgent(terminate: { [unowned self] in agentTerminations += 1 })
            },
            listSessions: { [unowned self] _, _, _ in sessions })
    }

    /// One line of agy's stream, as the agent would print it.
    func agentPrints(_ event: [String: Any]) {
        guard let line = try? JSONSerialization.data(withJSONObject: event) else {
            fail("could not write a line of the stand-in agent's output", status: 70)
        }
        agentOutput?(line + Data([0x0A]))
    }

    /// A piece of the reply arrives.
    func agentSays(_ text: String) {
        agentPrints(["event": "step_update", "step_update": ["step_type": "agent_response", "text_delta": text]])
    }
}

/// The app's settings and text are `VitruvianNexusAgentHost`'s own, read
/// from the settings domain the service was handed. What differs is the
/// telling: a notice is kept, with what that host's rule says the app would
/// show for it, and nothing is shown.
final class RecordingHost: NexusAgentHost {
    struct Told {
        var notice: NexusAgentTurnNotice
        var isChatVisible: Bool
        /// What the app would show: the notch notice, the sound and, when
        /// one is due, the notification.
        var announcement: VitruvianNexusAgentHost.TurnAnnouncement
    }

    private let own: VitruvianNexusAgentHost
    private(set) var finished: [Told] = []
    private(set) var approvals = 0

    init(defaults: UserDefaults) {
        own = VitruvianNexusAgentHost(defaults: defaults)
    }

    var configuredBotDirectory: String { own.configuredBotDirectory }
    var startsBotAtLaunch: Bool { own.startsBotAtLaunch }
    var planMode: Bool {
        get { own.planMode }
        set { own.planMode = newValue }
    }
    var hiddenClaudeSessionIDs: [String] {
        get { own.hiddenClaudeSessionIDs }
        set { own.hiddenClaudeSessionIDs = newValue }
    }
    var chosenProviderID: UUID? {
        get { own.chosenProviderID }
        set { own.chosenProviderID = newValue }
    }
    var savedProviders: [NexusAgentCLIProvider] {
        get { own.savedProviders }
        set { own.savedProviders = newValue }
    }
    var promptHistory: [String] {
        get { own.promptHistory }
        set { own.promptHistory = newValue }
    }
    var worktreeMode: Bool {
        get { own.worktreeMode }
        set { own.worktreeMode = newValue }
    }
    var strings: NexusAgentHostStrings { own.strings }

    func turnNeedsApproval(_ notice: NexusAgentTurnNotice) {
        approvals += 1
    }

    func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {
        finished.append(Told(
            notice: notice, isChatVisible: isChatVisible,
            announcement: VitruvianNexusAgentHost.announcement(finished: notice, isChatVisible: isChatVisible,
                                                               strings: strings)))
    }
}

/// The one view this run shows. The app's factory (`UIServiceViewFactory`)
/// builds the same view around the app's one service; here it is built
/// around the service of this run, and the island is counted instead of
/// told. Nothing else is ever asked for, and the run ends if something is.
struct WindowRunViews: ServiceViewFactory {
    let service: NexusAgentService
    let toldTheIsland: @MainActor () -> Void

    func nexusAgentQuickPrompt() -> AnyView {
        AnyView(NexusAgentQuickPromptView(service: service, setNotchLayer: { [toldTheIsland] _ in toldTheIsland() }))
    }

    private func notShown(_ view: String = #function) -> Never {
        fail("the run asked for a view it never shows: \(view)", status: 70)
    }

    func switcher(_ switcher: AppSwitcher) -> AnyView { notShown() }
    func dockPreview(_ service: DockPreviewService) -> AnyView { notShown() }
    func pinnedDockPreview(_ panel: DockPreviewPinnedPanel) -> AnyView { notShown() }
    func shelf(_ shelf: ShelfService) -> AnyView { notShown() }
    func dockedShelf(_ shelf: ShelfService) -> AnyView { notShown() }
    func commandBar() -> AnyView { notShown() }
    func clipboardQuickPanel() -> AnyView { notShown() }
    func snippetLibrary() -> AnyView { notShown() }
    func scratchpad() -> AnyView { notShown() }
    func quickLauncher() -> AnyView { notShown() }
    func radialMenu() -> AnyView { notShown() }
    func cameraPreview() -> AnyView { notShown() }
    func recentCaptures(onClose: @escaping () -> Void) -> AnyView { notShown() }
    func cutFeedback(_ cutPaste: FinderCutPaste) -> AnyView { notShown() }
    func cleaningOverlay() -> AnyView { notShown() }
    func screenshotEditor(model: ScreenshotEditorModel, controller: ScreenshotEditorController) -> AnyView { notShown() }
    func recorderEditor(model: RecorderEditorModel, controller: RecorderEditorController) -> AnyView { notShown() }
    func notch(_ service: NotchService) -> AnyView { notShown() }
    func notchMirror(_ service: NotchService, mirror: NotchMirrorModel) -> AnyView { notShown() }
    func notchQuickAccess(_ service: NotchService, motion: NotchQuickAccessMotion,
                          backdrop: NotchBackdropPresentation) -> AnyView { notShown() }
    func notchBackground(_ presentation: NotchBackdropPresentation) -> AnyView { notShown() }
    func lockScreenPlayer(model: NotchLockScreenModel, size: CGSize) -> AnyView { notShown() }
    func lockScreenActivities(model: NotchLockScreenModel, size: CGSize) -> AnyView { notShown() }
    func lockScreenIsland(model: NotchLockScreenModel, size: CGSize, cameraWidth: CGFloat, geometry: NotchGeometry,
                          window: CGSize, origin: CGPoint) -> AnyView { notShown() }
}

// MARK: - The event loop, by hand

let application = NSApplication.shared
/// The Quick Prompt's panel, once the service has built it.
var panel: NSPanel?
/// How long the panel has been on screen in all, and since when it is now.
var onScreenBefore: TimeInterval = 0
var onScreenSince: Date?
let onScreenLimit: TimeInterval = 9

var onScreen: TimeInterval {
    onScreenBefore + (onScreenSince.map { Date().timeIntervalSince($0) } ?? 0)
}

/// Brings the count of time on screen up to date. Called at every turn of
/// the loop and right after each call that shows or hides the panel.
func lookAtThePanel() {
    let visible = panel?.isVisible == true
    if visible, onScreenSince == nil { onScreenSince = Date() }
    if !visible, let since = onScreenSince {
        onScreenBefore += Date().timeIntervalSince(since)
        onScreenSince = nil
    }
}

/// Ends the run: the turn in flight is dropped, the window goes, and the
/// two settings domains are emptied (the first copy removes their files).
func finish(_ status: Int32) -> Never {
    panel?.orderOut(nil)
    for domain in [serviceDomain, ownDomain] {
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
    UserDefaults.standard.synchronize()
    UserDefaults(suiteName: serviceDomain)?.synchronize()
    exit(status)
}

/// Runs the application's own event loop for a while: an event is taken off
/// the queue and sent, which is the path a key press takes to the service's
/// key monitor and on to the field with the caret. Timers, the main queue
/// and the web view's replies run while it waits for one.
func pump(_ seconds: TimeInterval) {
    let end = Date().addingTimeInterval(seconds)
    repeat {
        if let event = application.nextEvent(matching: .any, until: Date().addingTimeInterval(0.005),
                                             inMode: .default, dequeue: true) {
            application.sendEvent(event)
        }
        lookAtThePanel()
        if onScreen > onScreenLimit {
            panel?.orderOut(nil)
            print("FAIL  the window was on screen longer than \(onScreenLimit) s: the run ends here")
            finish(3)
        }
    } while Date() < end
}

/// The same, until `done` or for no longer than `patience`. What is waited
/// for is still checked afterwards.
func pump(until done: () -> Bool, atMost patience: TimeInterval) {
    let end = Date().addingTimeInterval(patience)
    while !done(), Date() < end { pump(0.01) }
}

/// A key press addressed to the panel, as the window server would hand one
/// to this program while the panel has the keyboard.
func key(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    guard let panel, let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: panel.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else {
        fail("could not make a key event", status: 70)
    }
    return event
}

/// Puts a key press on this program's own event queue. The next turns of
/// `pump` take it off and send it.
func press(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) {
    application.postEvent(key(characters, code: code, flags: flags), atStart: false)
}

let returnKey: (String, UInt16) = ("\r", 36)
let escapeKey: (String, UInt16) = ("\u{1B}", 53)

func allViews(_ root: NSView?) -> [NSView] {
    guard let root else { return [] }
    return [root] + root.subviews.flatMap { allViews($0) }
}

/// The placeholder of the text field the caret is in, which tells the
/// fields apart: the pill's, the follow-up bar's, the session list's filter
/// and the model name's editor. Nil when no text field has the keyboard.
func caretField() -> String? {
    guard let editor = panel?.firstResponder as? NSTextView, let field = editor.delegate as? NSTextField else {
        return nil
    }
    return field.placeholderString ?? field.placeholderAttributedString?.string ?? ""
}

func typesIntoText() -> Bool {
    let responder = panel?.firstResponder
    return (responder as? NSTextView)?.isEditable == true || (responder as? NSTextField)?.isEditable == true
}

func responderName() -> String {
    guard let responder = panel?.firstResponder else { return "none" }
    return responder === panel ? "the window itself" : String(describing: type(of: responder))
}

func said(_ text: String?) -> String {
    text.map { "\"\($0)\"" } ?? "no field has the caret"
}

/// The placeholders of the panel's editable text fields, the highest in the
/// window first, read from the views themselves.
func fieldPlaceholders() -> [String] {
    allViews(panel?.contentView)
        .compactMap { $0 as? NSTextField }
        .filter { $0.isEditable && !$0.isHiddenOrHasHiddenAncestor }
        .sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
        .map { $0.placeholderString ?? $0.placeholderAttributedString?.string ?? "" }
}

// MARK: - A diagram's page

let flowchart = "graph TD\nA[Start] --> B{Choice}\nB -->|yes| C[Done]\nB -->|no| A"

/// What a web view's answer is kept in until it arrives.
final class Answer {
    var text: String?
    var arrived = false
}

/// Runs `script` in the page and waits for what it gives back.
func evaluate(_ script: String, in webView: WKWebView) -> String? {
    let answer = Answer()
    webView.evaluateJavaScript(script) { value, error in
        answer.text = (value as? String) ?? error.map { "error: \($0.localizedDescription)" }
        answer.arrived = true
    }
    pump(until: { answer.arrived }, atMost: 3)
    return answer.text
}

func hasDrawing(_ webView: WKWebView) -> Bool {
    evaluate("String(!!document.querySelector('.mermaid svg g.node'))", in: webView) == "true"
}

/// What the page holds: the drawing, and everything the page asked the
/// network for (nothing, when it is self-contained). The questions are the
/// ones apps/desktop/nexus-agent/macos/Tests/MermaidPageTests.swift asks.
func facts(of webView: WKWebView) -> [String: Any] {
    let text = evaluate("""
    (function () {
      var svg = document.querySelector('.mermaid svg');
      return JSON.stringify({
        address: location.href,
        mermaid: typeof mermaid,
        svg: !!svg,
        nodes: svg ? svg.querySelectorAll('g.node').length : 0,
        labels: svg ? Array.from(svg.querySelectorAll('g.node')).map(function (n) { return n.textContent.trim(); }) : [],
        links: svg ? svg.querySelectorAll('path.flowchart-link').length : 0,
        requests: performance.getEntriesByType('resource').map(function (e) { return e.name; })
      });
    })()
    """, in: webView)
    guard let data = text?.data(using: .utf8),
          let found = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return ["unreadable": text ?? "nothing"]
    }
    return found
}

/// The three things a drawn flowchart is checked for, each as a line.
func checkDrawing(_ found: [String: Any], _ what: String) {
    let labels = found["labels"] as? [String] ?? []
    let requests = found["requests"] as? [String]
    check(found["svg"] as? Bool == true && found["mermaid"] as? String == "object",
          "\(what): the page ended with an <svg>, drawn by the script the app handed it")
    check(found["nodes"] as? Int == 3 && Set(labels) == ["Start", "Choice", "Done"] && found["links"] as? Int == 3,
          "\(what): the drawing is the diagram's own, three nodes and three links "
          + "(\(labels.joined(separator: ", ")); \(found["links"] as? Int ?? 0) links)")
    check(requests == [] && found["address"] as? String == "about:blank",
          "\(what): the page asked the network for nothing "
          + "(\(requests.map { "\($0.count) requests" } ?? "requests unread"), address \(found["address"] as? String ?? "unread"))")
    if let unreadable = found["unreadable"] { note("\(what): the page's answer could not be read: \(unreadable)") }
}

/// One diagram in a web view no window holds, drawn with `script`.
final class DiagramPage {
    let webView: WKWebView
    private let delegate: NexusAgentMermaidNavigationDelegate
    private(set) var errors = 0

    init(script: String?) {
        webView = NexusAgentMermaidPage.makeWebView(script: script)
        webView.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        delegate = NexusAgentMermaidNavigationDelegate(errorScheme: "window-run-error", onRenderError: {})
        webView.navigationDelegate = delegate
        delegate.onRenderError = { [weak self] in self?.errors += 1 }
        NexusAgentMermaidPage.load(source: flowchart, isDark: false, errorScheme: "window-run-error", in: webView)
    }

    /// Waits for the page to end one way or the other, and checks it drew.
    func checkItDrew(_ what: String) {
        pump(until: { self.errors > 0 || hasDrawing(self.webView) }, atMost: 60)
        check(errors == 0, "\(what): the diagram was drawn, not refused")
        checkDrawing(facts(of: webView), what)
    }
}

// MARK: - The run

/// Whether the screen is locked, as the window server's session says.
func screenIsLocked() -> Bool? {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
}

// As the app is: it has no Dock icon and may show a window and take the keyboard.
application.setActivationPolicy(.accessory)
application.finishLaunching()

// MARK: The copy of Mermaid, before anything is on screen

let scriptDirectories = NexusAgentMermaidPage.scriptDirectories(for: .main)
let ownScript = NexusAgentMermaidPage.scriptURL(in: scriptDirectories)
check(ownScript != nil && NexusAgentMermaidPage.bundledScript != nil,
      "8 lookup: the copy of Mermaid is found from this program's main bundle, where Bazel put it for the "
      + "libraries it links (\(ownScript.map { $0.path.replacingOccurrences(of: Bundle.main.bundlePath, with: "<bundle>") } ?? "not found"))")
// Drawing once here also has WebKit started before the window is shown, so
// the card's page is not waited for with the window on screen.
DiagramPage(script: NexusAgentMermaidPage.bundledScript).checkItDrew("8 off screen, this program's copy")

if let builtApp = ProcessInfo.processInfo.environment[builtAppKey] {
    if let bundle = Bundle(url: URL(fileURLWithPath: builtApp)) {
        let directories = NexusAgentMermaidPage.scriptDirectories(for: bundle)
        let url = NexusAgentMermaidPage.scriptURL(in: directories)
        let script = NexusAgentMermaidPage.script(in: directories)
        check(bundle.bundleIdentifier == appDomain,
              "8 built app: \((builtApp as NSString).lastPathComponent) is the app (\(bundle.bundleIdentifier ?? "no identifier"))")
        check(url != nil && script != nil,
              "8 built app: the app's own lookup finds the copy in it "
              + "(\(url.map { $0.path.replacingOccurrences(of: builtApp, with: "<app>") } ?? "not found"))")
        check(script != nil && script == NexusAgentMermaidPage.bundledScript,
              "8 built app: it is the same text as this program's copy (\(script?.utf8.count ?? 0) bytes)")
        DiagramPage(script: script).checkItDrew("8 built app, off screen")
    } else {
        check(false, "8 built app: \(builtApp) is not an app")
    }
} else {
    couldNotCheck("8 built app: no path of a built Vitruvian.zip or Vitruvian.app was given")
}

// MARK: The window

let rig = Rig(home: NSHomeDirectory())
rig.executables.insert(rig.agy)
rig.sessions = [
    NexusAgentSessionSummary(id: "s-1", title: "Fix the flaky login test", steps: 12, modified: nil),
    NexusAgentSessionSummary(id: "s-2", title: "Review the release notes", steps: 4, modified: nil),
]
let host = RecordingHost(defaults: rig.defaults)
let service = NexusAgentService(environment: rig.environment, host: host)
let session = service.session
var islandTold = 0
ServiceViews.install(WindowRunViews(service: service, toldTheIsland: { islandTold += 1 }))

typealias Layout = NexusAgentQuickPromptLayout
let chatStrings = NexusAgentQuickPromptView.strings(for: L10n.shared.language)
let hostStrings = host.strings
let provider = service.activeProvider
let providerWord = provider.name.components(separatedBy: " ").first ?? chatStrings.fallbackProviderName
let pillWords = chatStrings.askPrefix + providerWord + chatStrings.askSuffix
let followUpWords = chatStrings.followUpPrefix + providerWord + chatStrings.followUpSuffix
let filterWords = chatStrings.sessionsFilter
let editorWords = chatStrings.modelNamePlaceholder
let firstReply = "Here is the flow.\n\n```mermaid\n\(flowchart)\n```"

let windowChecks = [
    "1 the panel is on screen and key, and typing lands in the prompt",
    "2 Return sends the prompt and the reply arrives in the conversation",
    "3 the caret follows the conversation with no click",
    "4 Esc closes the model name's editor, then the panel, and never stops a reply",
    "5 the top field keeps the prompt's words over the open session list",
    "6 ⌘W hides the panel and showing it again brings the conversation back",
    "8 the diagram card in the window",
]

/// Shows or hides the panel by the method the global shortcut calls.
func pressTheShortcut() {
    service.toggleQuickPrompt()
    if panel == nil {
        panel = application.windows.compactMap { $0 as? NSPanel }.first { $0.isVisible && $0.title == "Vitruvian" }
    }
    lookAtThePanel()
}

/// Waits for the caret to be in the field that says `words`, and then a
/// moment for the window server's word on who has the keyboard.
func waitForTheCaret(in words: String) {
    pump(until: { caretField() == words }, atMost: 1.5)
    pump(until: { panel?.isKeyWindow == true }, atMost: 0.3)
}

/// The diagram card's web view, once it has been found and checked.
var cardInTheWindow: WKWebView?

func webViewsInThePanel() -> [WKWebView] {
    allViews(panel?.contentView).compactMap { $0 as? WKWebView }
}

/// Looks for the reply's diagram card in the panel and, the first time it
/// is there, checks what its page drew. The conversation builds a bubble
/// only once it has room to draw it, so the card is looked for each time
/// the conversation has been given its size, until it is found.
func lookForTheCard(_ when: String) {
    guard cardInTheWindow == nil else { return }
    pump(until: { !webViewsInThePanel().isEmpty }, atMost: 1)
    let cards = webViewsInThePanel()
    guard let card = cards.first else {
        note("8 card: no diagram card is drawn \(when) (the panel is \(panel?.frame.size ?? .zero))")
        return
    }
    check(cards.count == 1, "8 card, \(when): the reply's diagram card holds one web view (\(cards.count))")
    pump(until: { hasDrawing(card) || !webViewsInThePanel().contains { $0 === card } }, atMost: 4)
    check(webViewsInThePanel().contains { $0 === card },
          "8 card: the card kept its web view, so it did not fall back to showing the source")
    checkDrawing(facts(of: card), "8 card")
    cardInTheWindow = card
    markThePage()
}

/// Leaves a mark on the card's page, which a page loaded again would not have.
func markThePage() {
    guard let card = cardInTheWindow else { return }
    _ = evaluate("window.windowRunMark = 1; 'marked'", in: card)
}

/// Says whether the card's page is still the one that was marked. Not a
/// check: the page draws the same diagram either way.
func noteWhetherThePageWasLoadedAgain(by what: String) {
    guard let card = cardInTheWindow, webViewsInThePanel().contains(where: { $0 === card }) else { return }
    let kept = evaluate("String(window.windowRunMark === 1)", in: card) == "true"
    note("8 card: \(what) \(kept ? "left the diagram's page as it was" : "loaded the diagram's page again")")
}

func runTheWindow() {
    // Show.
    check(!service.isQuickPromptVisible && application.windows.filter(\.isVisible).isEmpty,
          "before: nothing of this program is on screen")
    pressTheShortcut()
    guard let panel else {
        check(false, "1 show: the service put no panel on screen")
        return
    }
    note("Reduce Motion is \(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? "on: the panel changes size at once" : "off: the panel springs to each size")")
    waitForTheCaret(in: pillWords)
    check(panel.isVisible && service.isChatVisible, "1 show: the panel is on screen, and the service says the chat is visible")
    check(panel.isKeyWindow, "1 show: the panel is the key window")
    check(typesIntoText(), "1 show: the first responder is a text input (\(responderName()))")
    check(caretField() == pillWords, "1 show: and that input is the pill's prompt (\(said(caretField())))")
    check(session.mode == .compact && fieldPlaceholders() == [pillWords],
          "1 show: the pill is all there is, with its one field (\(fieldPlaceholders()))")

    // The session list, opened as the pill's clock button opens it.
    session.toggleSessions(configuration: service.configuration)
    pump(until: { fieldPlaceholders().count == 2 }, atMost: 1.5)
    let overTheList = fieldPlaceholders()
    check(session.mode == .sessions && session.sessions.count == 2 && overTheList.count == 2,
          "5 list open: the session list is under the pill, with a field of its own (\(overTheList))")
    check(overTheList.first == pillWords && overTheList.first != filterWords,
          "5 list open: the top field still says the prompt's words, not the filter's (\(said(overTheList.first)))")
    check(overTheList.count == 2 && overTheList.last == filterWords,
          "5 list open: the filter's words are on the list's own field (\(said(overTheList.last)))")
    check(caretField() == pillWords, "5 list open: the caret stayed in the prompt (\(said(caretField())))")
    session.toggleSessions(configuration: service.configuration)
    pump(until: { fieldPlaceholders() == [pillWords] && caretField() == pillWords }, atMost: 1.5)
    check(session.mode == .compact && caretField() == pillWords,
          "5 list closed: back to the pill, the caret in it (\(said(caretField())))")

    // Typing, through the event queue.
    press("h", code: 4)
    press("i", code: 34)
    pump(until: { session.draft == "hi" }, atMost: 1)
    check(session.draft == "hi", "1 typing: two key presses landed in the prompt (draft \"\(session.draft)\")")
    // What follows needs the prompt, so it is put there if the keys did not.
    if session.draft != "hi" { session.draft = "hi" }

    // Return sends it; the stand-in agent answers with a diagram and ends.
    press(returnKey.0, code: returnKey.1)
    pump(until: { rig.agentRuns.count == 1 }, atMost: 1)
    check(rig.agentRuns.count == 1 && rig.agentRuns.last?.contains("hi") == true,
          "2 Return: the stand-in agent was started once, with the typed prompt (\(rig.agentRuns.last ?? []))")
    if rig.agentRuns.isEmpty { service.sendQuickPrompt() }
    rig.agentPrints(["event": "init", "conversation_id": "window-run-1"])
    rig.agentSays(firstReply)
    check(session.isRunning && session.messages.last?.text == firstReply,
          "2 Return: the reply arrives while the turn runs")
    rig.agentExit?(0)
    pump(until: { caretField() == followUpWords }, atMost: 2)
    check(session.mode == .chat && !session.isRunning && session.messages.map(\.text) == ["hi", firstReply],
          "2 Return: the turn ended with the prompt and its reply in the conversation")
    check(fieldPlaceholders() == [followUpWords],
          "2 Return: the view changed to the conversation, whose one prompt field is the follow-up bar (\(fieldPlaceholders()))")
    check(host.finished.count == 1 && host.finished.last?.isChatVisible == true
          && host.finished.last?.notice.failed == false && host.finished.last?.announcement.notificationTitle == nil,
          "2 Return: the host was told once of a turn that ended in sight, which is no notification")

    // The caret follows the conversation: no click, no call of this run's.
    check(typesIntoText(), "3 caret: with no click, the first responder is a text input again (\(responderName()))")
    check(caretField() == followUpWords, "3 caret: and that input is the follow-up bar (\(said(caretField())))")
    check(panel.isVisible && panel.isKeyWindow, "3 caret: the panel is still on screen and key")

    // The panel springs to the conversation's size, which is what gives
    // the conversation room to draw its bubbles in.
    pump(until: { panel.frame.size == Layout.size(for: .chat) }, atMost: 1.5)
    check(panel.frame.size == Layout.size(for: .chat),
          "2 Return: the panel took the conversation's size (\(panel.frame.size))")
    lookForTheCard("after the first reply")

    press("o", code: 31)
    press("k", code: 40)
    pump(until: { session.draft == "ok" }, atMost: 1)
    check(session.draft == "ok" && session.mode == .chat,
          "3 caret: two more key presses landed in the follow-up bar (draft \"\(session.draft)\")")
    if session.draft != "ok" { session.draft = "ok" }
    noteWhetherThePageWasLoadedAgain(by: "two letters typed in the follow-up bar")

    // A second turn, sent with Return from the follow-up bar, left running.
    press(returnKey.0, code: returnKey.1)
    pump(until: { rig.agentRuns.count == 2 }, atMost: 1)
    check(rig.agentRuns.count == 2 && rig.agentRuns.last?.contains("ok") == true
          && rig.agentRuns.last?.suffix(2) == ["--conversation", "window-run-1"],
          "3 caret: Return there started a second turn, in the same conversation (\(rig.agentRuns.last ?? []))")
    if rig.agentRuns.count < 2 { service.sendQuickPrompt() }
    rig.agentSays("First half,")
    pump(0.1)
    check(session.isRunning && session.messages.last?.text == "First half,", "4: a reply is arriving")

    // The model name's editor, opened as a click on the model's name opens
    // it: the badge's button sets this flag and does nothing else.
    session.isEditingModel = true
    pump(until: { caretField() == editorWords }, atMost: 1.5)
    check(fieldPlaceholders().contains(editorWords) && caretField() == editorWords,
          "4 editor: the model name's editor is open, with the caret in it (\(said(caretField())))")
    press(escapeKey.0, code: escapeKey.1)
    pump(until: { !session.isEditingModel && caretField() == followUpWords }, atMost: 1.5)
    check(!session.isEditingModel && !fieldPlaceholders().contains(editorWords), "4 Esc: the editor closed")
    check(panel.isVisible && service.isChatVisible, "4 Esc: the panel is still on screen")
    check(panel.isKeyWindow, "4 Esc: and still the key window")
    check(session.isRunning && rig.agentTerminations == 0, "4 Esc: the reply was not stopped")
    check(caretField() == followUpWords, "4 Esc: the caret went back to the follow-up bar (\(said(caretField())))")
    let visibleBeforeEsc = panel.isVisible
    press(escapeKey.0, code: escapeKey.1)
    pump(until: { !panel.isVisible }, atMost: 1)
    check(visibleBeforeEsc && !panel.isVisible && !service.isChatVisible,
          "4 second Esc: the panel hid, and the service says the chat is not visible")
    check(session.isRunning && rig.agentTerminations == 0, "4 second Esc: the reply was not stopped")
    rig.agentSays(" second half.")
    pump(0.1)
    check(session.isRunning && session.messages.last?.text == "First half, second half.",
          "4 hidden: the reply went on arriving with the panel hidden (\"\(session.messages.last?.text ?? "")\")")
    rig.agentExit?(0)
    pump(0.1)
    let endedHidden = host.finished.last
    let doneTitle = hostStrings.doneTitle(provider: provider.name)
    check(host.finished.count == 2 && endedHidden?.isChatVisible == false && endedHidden?.notice.failed == false
          && endedHidden?.notice.text == "First half, second half.",
          "4 hidden: the host was told once that it ended, with the chat out of sight")
    check(endedHidden?.announcement.notificationTitle == doneTitle
          && endedHidden?.announcement.notificationBody == "First half, second half.",
          "4 hidden: for which the app would notify (\(said(endedHidden?.announcement.notificationTitle)), "
          + "\(said(endedHidden?.announcement.notificationBody)))")

    // Shown again, hidden with ⌘W, shown again.
    pressTheShortcut()
    waitForTheCaret(in: followUpWords)
    check(panel.isVisible && session.mode == .chat && session.messages.count == 4,
          "6 shown after Esc: the conversation came back with the panel (\(session.messages.count) messages)")
    check(panel.frame.size == Layout.size(for: .chat),
          "6 shown after Esc: at the conversation's size (\(panel.frame.size))")
    check(panel.isKeyWindow, "6 shown after Esc: the panel is the key window")
    check(caretField() == followUpWords, "6 shown after Esc: the caret is in the follow-up bar (\(said(caretField())))")
    lookForTheCard("shown again after Esc")
    press("w", code: 13, flags: .command)
    pump(until: { !panel.isVisible }, atMost: 1)
    check(!panel.isVisible && !service.isChatVisible, "6 ⌘W: the panel hid")
    check(session.mode == .chat && session.messages.count == 4, "6 ⌘W: the conversation is kept")
    pressTheShortcut()
    waitForTheCaret(in: followUpWords)
    check(panel.isVisible && session.mode == .chat && session.messages.count == 4
          && panel.frame.size == Layout.size(for: .chat),
          "6 shown after ⌘W: the kept conversation came back, at its size (\(panel.frame.size))")
    check(panel.isKeyWindow, "6 shown after ⌘W: the panel is the key window")
    check(typesIntoText() && caretField() == followUpWords,
          "6 shown after ⌘W: the caret is in a text input, the follow-up bar (\(said(caretField())))")
    lookForTheCard("shown again after ⌘W")
    markThePage()
    press("y", code: 16)
    pump(until: { session.draft == "y" }, atMost: 1)
    check(session.draft == "y", "6 shown after ⌘W: and a key press lands in it (draft \"\(session.draft)\")")
    noteWhetherThePageWasLoadedAgain(by: "a letter typed in the follow-up bar")
    if cardInTheWindow == nil {
        check(false, "8 card: the conversation never drew the reply's diagram card, so there was no page to look at")
    }

    // The shortcut again. It hides a panel that is on screen and key; one
    // that is on screen without the keyboard it brings forward instead.
    let wasKey = panel.isKeyWindow
    pressTheShortcut()
    pump(0.1)
    check(wasKey && !panel.isVisible && !service.isChatVisible,
          "after: the shortcut's method hides a panel that is on screen and key"
          + (wasKey ? "" : " (it was not key, so it was shown again)"))
}

// A locked screen covers the window, and the window server may keep the
// keyboard from it. The checks are made all the same, each exactly as it
// is with the screen unlocked; what fails then is reported at the end as
// not checked, because the lock alone can be why.
let lockedBefore = screenIsLocked()
var windowFailures = 0
if let lockedBefore {
    if lockedBefore {
        print("THE SCREEN IS LOCKED: the window is shown under the lock screen, where nobody sees it.")
    }
    let failedBefore = failed
    runTheWindow()
    windowFailures = failed - failedBefore
} else {
    print("THERE IS NO WINDOW SERVER SESSION: no window can be shown.")
    for name in windowChecks { couldNotCheck(name) }
}
lookAtThePanel()
let underLock = lockedBefore == true || screenIsLocked() == true
// What follows is a turn the user cannot see, so a panel the checks above
// left on screen is hidden first, by the method Esc and ⌘W call.
if panel?.isVisible == true {
    note("the panel was still on screen after the window's checks, and is hidden now by the service's own method")
    service.hideQuickPrompt()
    lookAtThePanel()
}

// MARK: A turn that cannot start, with the panel hidden

// The agent's program is gone, and the service has looked again, as it
// does each time the prompt is shown or the Settings page opens.
rig.executables.remove(rig.agy)
service.load()
let missing = hostStrings.missingProgram(of: provider)
check(service.agentPath == nil && service.missingProgramText == missing,
      "7 before: the service finds no program for \(provider.name)")
let toldBefore = host.finished.count
let startedBefore = rig.agentRuns.count
session.draft = "again"
// What Return calls in either prompt field.
service.sendQuickPrompt()
pump(0.2)
check(panel?.isVisible != true && !service.isChatVisible, "7: the panel was hidden when the prompt was sent")
check(rig.agentRuns.count == startedBefore, "7: nothing was started")
check(session.messages.last?.isError == true && session.messages.last?.text == missing,
      "7: the chat's bubble says why (\(said(session.messages.last?.text)))")
check(host.finished.count == toldBefore + 1, "7: the host was told once (\(host.finished.count - toldBefore) times)")
if host.finished.count > toldBefore, let told = host.finished.last {
    let failedTitle = hostStrings.failedTitle(provider: provider.name)
    check(told.notice.failed && told.notice.failureDetail == missing && told.notice.text.isEmpty && !told.isChatVisible,
          "7: with the reason, as a failed turn the user cannot see (\(said(told.notice.failureDetail)))")
    check(told.announcement.notchTitle == failedTitle && told.announcement.notchDetail == String(missing.prefix(80))
          && told.announcement.notchSymbol == "exclamationmark.triangle.fill" && !told.announcement.playsSound,
          "7: the notch would show the failure's words under \"\(failedTitle)\" (\(said(told.announcement.notchDetail)))")
    check(told.announcement.notificationTitle == failedTitle && told.announcement.notificationBody == missing,
          "7: and the notification would say them too (\(said(told.announcement.notificationBody)))")
}

// MARK: The end

session.stop()
session.stopTranscriptFollower()
lookAtThePanel()
check(islandTold == 0, "the floating window told the island nothing (\(islandTold) times)")
check(host.approvals == 0 && rig.agentTerminations == 0, "no turn waited on an approval, and none was stopped")
check(panel?.isVisible != true, "at the end the panel is not on screen")
check(onScreen < 10, "the window was on screen for \(String(format: "%.1f", onScreen)) s in all (limit 10)")
print("\nthe window was on screen for \(String(format: "%.1f", onScreen)) s")
print("\(passed) passed, \(failed) failed, \(notChecked) not checked")
if underLock {
    print("THE SCREEN WAS LOCKED while the window was shown.")
}
if failed > windowFailures || (failed > 0 && !underLock) {
    print("FAILED")
    finish(1)
}
if windowFailures > 0 {
    // Only the window's checks failed, and the screen was locked.
    print("\(windowFailures) of the window's checks failed under the lock screen. The lock alone can be why, so they say "
          + "nothing about the app: count them as NOT CHECKED, and run again with the screen unlocked.")
    print("INCOMPLETE")
    finish(75)
}
// A run that could not show its window has not done what it is for.
if lockedBefore == nil {
    print("INCOMPLETE")
    finish(75)
}
print(notChecked == 0 ? "ALL PASSED" : "ALL THAT WAS CHECKED PASSED")
finish(0)
