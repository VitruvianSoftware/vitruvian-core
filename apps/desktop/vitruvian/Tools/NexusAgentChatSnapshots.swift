// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

// Draws the Nexus Agent chat in a set of fixed states and writes each one as
// a PNG, so that a change which is meant to leave the chat looking the same
// can be checked: run this before the change and after it, and compare the
// files byte for byte.
//
//   bazel run --config=macos-app //apps/desktop/vitruvian:nexus_agent_chat_snapshots -- <output folder>
//
// The folder is an absolute path; it is created. Each state is drawn as the
// floating window and as the notch shows it, in the light and the dark
// appearance, at two pixels per point. Two runs of the same code on the same
// Mac write identical files. Files from two Macs, or two macOS versions, are
// not expected to match: fonts, colour handling and the first letter of the
// user's name (the avatar beside a prompt) differ.
//
// What it never does: show a window, start an agent or the bot, post a
// notice, play a sound, or read the user's own files and settings.
// - The service it draws is built over files held in memory, as the unit
//   tests' `Rig` is, and no turn is ever let finish, because a finished turn
//   is announced through the notch, a sound and a notification.
// - The whole run happens in a second copy of this program whose home folder
//   is a throwaway one (CFFIXED_USER_HOME), so a path built from the home
//   folder cannot reach the user's files. That copy refuses to draw anything
//   if its home is still the user's.
// - Settings cannot be sent to the throwaway home: the system keeps every
//   program's settings in the account's real Library/Preferences whatever
//   home the program is given (bazel/run_unit_tests.sh meets the same
//   thing). So the tool uses two settings domains of its own and never the
//   app's: one handed to the service, and this program's own, which is what
//   `L10n.shared` and `@AppStorage` read here. It refuses to run if its own
//   domain would be the app's. Both are emptied at the end and their two
//   files removed, by name.
//
// What the images are not:
// - Hovered, focused or expanded. The pill's round buttons come in under the
//   pointer, and the tool steps, the "Thinking process" text, the token
//   details, the archived sessions and the subagent list each open on a
//   click; the view keeps those switches to itself, so each is drawn closed.
// - Moving. Animations are switched off for the drawing, which leaves the
//   sparkle, the typing dots and the loading shimmer at the far end of their
//   cycle. The subagent banner's spinner is the system's own and cannot be
//   held still from here; off screen it has come out the same on every run.
// - Blurred. The floating window's backdrop is a behind-window material,
//   which has nothing behind it here; a flat plate stands in for the desktop.
// - The notch itself. The notch's size follows the screen and the user's
//   layout, so one representative size is used, and its page header is not
//   drawn. The notch is always dark; its light image is a check on colours
//   only and shows nothing the app can show.
// - A session list by provider. A row does not say which agent it belongs
//   to, so the drawer's rows differ by title alone.

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

// MARK: - A home of its own

let scratchKey = "NEXUS_AGENT_CHAT_SNAPSHOTS_SCRATCH"

func fail(_ message: String, status: Int32) -> Never {
    FileHandle.standardError.write(Data("nexus_agent_chat_snapshots: \(message)\n".utf8))
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

guard CommandLine.arguments.count == 2, CommandLine.arguments[1].hasPrefix("/") else {
    fail("usage: nexus_agent_chat_snapshots <absolute path of the output folder>", status: 64)
}
let outputFolder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

/// The app's settings, which this tool must never read or write; the domain
/// the service is handed; and this program's own, which `UserDefaults.standard`
/// is here.
let appDomain = "com.vitruviansoftware.vitruvian"
let snapshotDomain = appDomain + ".snapshots.nexus-agent"
let ownDomain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
guard ownDomain != appDomain, !ownDomain.contains("/") else {
    fail("refusing to run: this program's settings domain is \(ownDomain), which would be the app's", status: 78)
}

/// Removes the two settings files this tool leaves in the account's real
/// Library/Preferences. The settings daemon writes an emptied domain to
/// disk when it gets round to it, which was two to three seconds after the
/// second copy ended when measured, so a file removed at once comes back.
/// This keeps looking until none has been there for four seconds.
func removeOwnSettingsFiles() {
    let folder = usersOwnHome() + "/Library/Preferences/"
    let files = [snapshotDomain, ownDomain].map { folder + $0 + ".plist" }
    let look: TimeInterval = 0.25
    var quiet: TimeInterval = 0
    var waited: TimeInterval = 0
    while quiet < 4, waited < 20 {
        let present = files.filter { FileManager.default.fileExists(atPath: $0) }
        for file in present { try? FileManager.default.removeItem(atPath: file) }
        quiet = present.isEmpty ? quiet + look : 0
        Thread.sleep(forTimeInterval: look)
        waited += look
    }
    if quiet < 4 {
        FileHandle.standardError.write(Data("nexus_agent_chat_snapshots: its settings files in \(folder) did not stay removed\n".utf8))
    }
}

guard let scratch = ProcessInfo.processInfo.environment[scratchKey] else {
    // The first copy only makes the throwaway home, runs the second copy in
    // it, and clears up. It reads no settings and draws nothing.
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-agent-chat-snapshots-\(getpid())", isDirectory: true)
    let home = scratch.appendingPathComponent("home", isDirectory: true)
    guard let program = Bundle.main.executableURL else { fail("cannot find its own program file", status: 70) }
    do {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var environment = ProcessInfo.processInfo.environment
        environment[scratchKey] = scratch.path
        environment["CFFIXED_USER_HOME"] = home.path
        environment["HOME"] = home.path
        let copy = Process()
        copy.executableURL = program
        copy.arguments = [outputFolder.path]
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

// From here on this is the second copy. It draws only if every way of
// asking for the home folder gives the throwaway one.
let privateHome = resolved(scratch + "/home")
let ownHome = usersOwnHome()
guard resolved(NSHomeDirectory()) == privateHome,
      resolved(FileManager.default.homeDirectoryForCurrentUser.path) == privateHome,
      privateHome != ownHome, !privateHome.hasPrefix(ownHome + "/"), !ownHome.hasPrefix(privateHome + "/") else {
    fail("refusing to run: the home folder is \(NSHomeDirectory()), not the throwaway \(privateHome)", status: 78)
}
print("home: \(NSHomeDirectory())")
print("settings domains: \(snapshotDomain), \(ownDomain)")

// MARK: - A Mac in memory

/// The files, sessions and transcripts the service is shown, and the agent
/// it believes it started. Nothing here reaches a disk or a process.
final class Rig {
    let defaults: UserDefaults
    let home: String
    var files: [String: String] = [:]
    var sessions: [NexusAgentSessionSummary] = []
    /// A conversation's transcript by its id, as Claude Code writes one.
    var transcripts: [String: String] = [:]
    private var read: [String: [NexusAgentChatMessage]] = [:]
    var agentOutput: (@MainActor @Sendable (Data) -> Void)?

    var bot: String { home + "/.config/nexus-agent" }

    init(home: String) {
        self.home = home
        guard let defaults = UserDefaults(suiteName: snapshotDomain) else {
            fail("could not open a settings domain of its own", status: 70)
        }
        defaults.removePersistentDomain(forName: snapshotDomain)
        self.defaults = defaults
    }

    /// Read once, so that the follower, which reads again every second and
    /// a half, is handed equal messages and leaves the chat alone.
    private func messages(_ id: String) -> [NexusAgentChatMessage]? {
        if let known = read[id] { return known }
        guard let raw = transcripts[id], let parsed = NexusAgentService.parseClaudeTranscript(raw) else { return nil }
        read[id] = parsed
        return parsed
    }

    var environment: NexusAgentService.Environment {
        NexusAgentService.Environment(
            defaults: defaults,
            home: home,
            processEnvironment: ["PATH": "/usr/bin"],
            stateDirectory: home + "/Library/Application Support/NexusAgent",
            isExecutable: { _ in false },
            fileExists: { [unowned self] in files[$0] != nil },
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
            launchAgent: { [unowned self] _, _, _, _, onOutput, _ in
                // The exit is never delivered: see the note on finished turns above.
                agentOutput = onOutput
                return NexusAgentRunningAgent(terminate: {})
            },
            listSessions: { [unowned self] _, _, _ in sessions },
            readTranscript: { [unowned self] id, _ in messages(id) },
            // A name is all the follower needs to go on to read the text;
            // no file is there, which it takes as "changed, read again".
            transcriptPath: { [unowned self] id, _ in
                transcripts[id] == nil ? nil : home + "/transcripts/\(id).jsonl"
            },
            readTranscriptRaw: { [unowned self] id, _ in transcripts[id] })
    }

    /// One line of agy's stream, as the agent would print it.
    func agentPrints(_ line: String) {
        agentOutput?(Data((line + "\n").utf8))
    }
}

// MARK: - The states

func fixedID(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID()
}

/// A day far enough back that "3 years ago" stays "3 years ago" for months.
func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
}

/// Opens the chat on a conversation that has already happened. The prompt
/// is sent with no agent to run it, which opens the chat and tells the host
/// nothing; the messages are then the ones given.
func showChat(_ service: NexusAgentService, _ messages: [NexusAgentChatMessage]) {
    service.session.send("snapshot", configuration: service.configuration, agentPath: nil)
    service.session.messages = messages
}

/// Starts a turn that stays in flight.
func startTurn(_ rig: Rig, _ service: NexusAgentService, prompt: String, tool: String) {
    service.session.send(prompt, configuration: service.configuration, agentPath: "/opt/snapshot/agy")
    rig.agentPrints(#"{"event":"init","conversation_id":"snapshot-turn"}"#)
    rig.agentPrints(#"{"event":"step_update","step_update":{"step_type":"tool","tool_name":"\#(tool)","state":"RUNNING"}}"#)
}

let markdownReply = """
## Release checklist

Before tagging, run `bazel test //...` and check these:

- Unit tests pass
- The changelog has an entry

1. Tag the commit
2. Publish the build

```sh
git tag v1.2.3
git push --tags
```

> Never tag from a dirty tree.
"""

func markdownChat(_ rig: Rig, _ service: NexusAgentService) {
    rig.files[rig.bot] = ""
    rig.files[rig.bot + "/.env"] = "AGY_MODEL=gemini-2.5-pro\n"
    service.load()
    showChat(service, [
        NexusAgentChatMessage(id: fixedID(1), role: .user, text: "Summarise the release checklist"),
        NexusAgentChatMessage(id: fixedID(2), role: .agent, text: markdownReply,
                              durationMs: 2200, inputTokens: 850, outputTokens: 320, cachedTokens: 120,
                              numTurns: 1, toolCalls: 2, modelName: "gemini-2.5-pro", stopReason: "end_turn",
                              totalCostUSD: 0.045),
    ])
}

struct Scenario {
    var name: String
    var language: AppLanguage = .enUS
    /// A turn in flight shows its clock; the image is taken while it reads this.
    var elapsed: Int?
    var build: (Rig, NexusAgentService) -> Void
    /// The images taken, in order, of the one view on screen: the first as
    /// built, each later one after its change. A later image that did not
    /// change shows a view that stopped following its session.
    var steps: [(suffix: String, change: (Rig, NexusAgentService) -> Void)] = [("", { _, _ in })]
}

let scenarios: [Scenario] = [
    Scenario(name: "01-empty-pill", build: { _, _ in }),

    Scenario(name: "02-sessions-drawer", build: { rig, service in
        rig.sessions = [
            NexusAgentSessionSummary(id: "s-1", title: "Fix the flaky login test", preview: "", steps: 12,
                                     modified: day(2024, 1, 15)),
            NexusAgentSessionSummary(id: "s-2", title: "Review the Claude pull request", preview: "", steps: 4,
                                     modified: day(2023, 6, 1)),
            NexusAgentSessionSummary(
                id: "s-3",
                title: "Investigate why the nightly build of the desktop app takes forty minutes longer on the "
                    + "new runners than it did on the old ones",
                preview: "", steps: 30, modified: day(2022, 3, 10)),
            NexusAgentSessionSummary(id: "s-4", title: "", preview: "", steps: 1, modified: day(2021, 9, 2)),
            NexusAgentSessionSummary(id: "s-5", title: "Old migration notes", preview: "", steps: 7,
                                     modified: day(2020, 2, 20), isArchived: true),
        ]
        service.session.toggleSessions(configuration: service.configuration)
    }),

    Scenario(name: "03-chat-markdown", build: markdownChat),

    Scenario(name: "04-running-turn", elapsed: 2, build: { rig, service in
        // An earlier answer, read from a transcript, is what carries a tool
        // step and a thinking block; the turn in flight follows it.
        rig.transcripts["earlier"] = """
        {"type":"user","message":{"role":"user","content":"Is the tree clean?"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"I should look at git status first."},{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"git status --porcelain"}},{"type":"text","text":"Yes, nothing is modified."}]}}
        """
        service.session.resume(NexusAgentSessionSummary(id: "earlier", title: "Tree check", preview: "", steps: 2,
                                                        modified: nil),
                               configuration: service.configuration)
        startTurn(rig, service, prompt: "Then run the tests", tool: "bazel test")
    }, steps: [
        ("-tool", { _, _ in }),
        ("-reply-arrives", { rig, _ in
            rig.agentPrints(#"{"event":"step_update","step_update":{"step_type":"agent_response","text_delta":"All 214 tests pass."}}"#)
        }),
    ]),

    Scenario(name: "05-approval", elapsed: 2, build: { rig, service in
        startTurn(rig, service, prompt: "Clear the build cache", tool: "Bash")
        // Set on the reply as the stream would, without the stream's notice
        // to the host, which shows in the notch.
        let reply = service.session.messages.count - 1
        service.session.messages[reply].approvalRequest = NexusAgentApprovalRequest(
            id: "request-1", toolName: "Bash", commandOrPath: "rm -rf /tmp/build-cache")
    }, steps: [
        ("-pending", { _, _ in }),
        ("-allowed", { _, service in
            // What the card's Allow button calls.
            guard let card = service.session.messages.last else { return }
            service.session.decideApproval(messageID: card.id, decision: .approved)
        }),
    ]),

    Scenario(name: "06-failed-turn", build: { _, service in
        let failed = FeatureStrings.nexusAgent(L10n.shared.language).agentFailed
        showChat(service, [
            NexusAgentChatMessage(id: fixedID(1), role: .user, text: "Deploy to staging"),
            NexusAgentChatMessage(id: fixedID(2), role: .agent, text: failed + "\nagy: not logged in", isError: true),
        ])
        service.session.lastFailedPrompt = "Deploy to staging"
    }),

    Scenario(name: "07-plan-and-worktree", build: { rig, service in
        // The worktree switch is offered for a git folder under an agent
        // other than agy. The view looks for `.git` on the real disk, so
        // this one folder exists, inside the throwaway home.
        let project = rig.home + "/project"
        try? FileManager.default.createDirectory(atPath: project + "/.git", withIntermediateDirectories: true)
        rig.files[project] = ""
        rig.files[rig.bot] = ""
        rig.files[rig.bot + "/.env"] = "AGY_WORKING_DIR=~/project\n"
        service.load()
        service.updateActiveProvider(.claude)
        service.session.planMode = true
        service.session.worktreeMode = true
        showChat(service, [
            NexusAgentChatMessage(id: fixedID(1), role: .user, text: "How would you split this module?"),
            NexusAgentChatMessage(id: fixedID(2), role: .agent, text: "In three steps, each one buildable on its own."),
        ])
    }),

    Scenario(name: "08-subagents", build: { rig, service in
        rig.transcripts["with-subagents"] = """
        {"type":"user","message":{"role":"user","content":"Watch CI and review the diff"}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_task_1","name":"Task","input":{"subagent_type":"scout","description":"Watch CI checks","prompt":"Keep polling the checks until they are green"}},{"type":"tool_use","id":"toolu_task_2","name":"Task","input":{"subagent_type":"reviewer","description":"Review the diff","prompt":"Read the change for mistakes"}},{"type":"text","text":"Two helpers are on it."}]}}
        """
        service.updateActiveProvider(.claude)
        service.session.resume(NexusAgentSessionSummary(id: "with-subagents", title: "CI and review", preview: "",
                                                        steps: 2, modified: nil),
                               configuration: service.configuration)
    }),

    Scenario(name: "09-chat-markdown-german", language: .de, build: markdownChat),
]

// MARK: - Drawing

enum Form: String, CaseIterable {
    case floating, notch

    /// The floating window is the size the service gives its panel for the
    /// mode. The notch's page is the "spacious" island's width less its side
    /// insets, at a height a tall custom island leaves under its header.
    /// It is tall enough that the running turn fits without scrolling: a
    /// chat that scrolls to a new message does so over several frames, and
    /// an image caught on the way would differ from run to run.
    func size(for mode: NexusAgentQuickPromptMode) -> CGSize {
        switch self {
        case .floating: return NexusAgentQuickPromptLayout.size(for: mode)
        case .notch: return CGSize(width: 504, height: 480)
        }
    }
}

enum Look: String, CaseIterable {
    case light, dark

    var appearance: NSAppearance? { NSAppearance(named: self == .dark ? .darkAqua : .aqua) }

    /// What stands behind the view: the notch's black, or a plain plate
    /// where the desktop would show through the floating window.
    func backing(_ form: Form) -> Color {
        switch (form, self) {
        case (.notch, .dark): return .black
        case (_, .dark): return Color(white: 0.14)
        case (_, .light): return Color(white: 0.93)
        }
    }
}

let pixelsPerPoint: CGFloat = 2

/// Lets the main run loop turn for a while, so the view lays itself out
/// and takes in what its session published.
func settle(_ seconds: TimeInterval) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    CATransaction.flush()
}

func picture(of view: NSView, size: CGSize) -> Data {
    view.layoutSubtreeIfNeeded()
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * pixelsPerPoint),
        pixelsHigh: Int(size.height * pixelsPerPoint), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        fail("could not make a bitmap of \(size)", status: 70)
    }
    bitmap.size = size
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fail("could not encode a PNG", status: 70)
    }
    return png
}

var rigs: [Rig] = []

struct Picture {
    var name: String
    var size: CGSize
    var png: Data
}

/// One scenario in one form and look. Nil when a turn's clock moved on
/// while its images were being taken, which the caller answers by starting
/// the scenario again.
func pictures(of scenario: Scenario, form: Form, look: Look) -> [Picture]? {
    let rig = Rig(home: NSHomeDirectory())
    // A service can outlive this function (a timer of its session's may
    // still be due), and its environment reaches back into its rig.
    rigs.append(rig)
    let service = NexusAgentService(environment: rig.environment)
    scenario.build(rig, service)
    defer {
        // Stops the clocks. A stopped turn is told to end, which this
        // rig's agent ignores, so it is still never reported as finished.
        service.session.stop()
        service.session.stopTranscriptFollower()
    }

    let size = form.size(for: service.session.mode)
    let content = NexusAgentQuickPromptView(embeddedInNotch: form == .notch, service: service)
        // No animation, whether a view asked for it in `withAnimation` or
        // with `.animation`: a frame caught part-way would differ each run.
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .frame(width: size.width, height: size.height)
        .background(look.backing(form))
    // The window gives the view somewhere to live. It is never put on screen.
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = look.appearance
    let host = NSHostingView(rootView: content)
    host.frame = NSRect(origin: .zero, size: size)
    window.contentView = host
    defer {
        window.contentView = nil
        window.close()
    }

    settle(0.25)
    if let elapsed = scenario.elapsed {
        let patience = Date().addingTimeInterval(TimeInterval(elapsed) + 3)
        while service.session.elapsedSeconds < elapsed, Date() < patience { settle(0.01) }
    }
    var taken: [Picture] = []
    for step in scenario.steps {
        step.change(rig, service)
        settle(0.12)
        taken.append(Picture(name: "\(scenario.name)\(step.suffix)-\(form.rawValue)-\(look.rawValue).png",
                             size: size, png: picture(of: host, size: size)))
    }
    if let elapsed = scenario.elapsed, service.session.elapsedSeconds != elapsed { return nil }
    return taken
}

// MARK: - The run

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

do {
    try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
} catch {
    fail("could not create \(outputFolder.path): \(error.localizedDescription)", status: 73)
}

let languageBefore = L10n.shared.language
for scenario in scenarios {
    L10n.shared.language = scenario.language
    for form in Form.allCases {
        for look in Look.allCases {
            var taken: [Picture]?
            for _ in 0..<4 where taken == nil {
                taken = pictures(of: scenario, form: form, look: look)
            }
            guard let taken else {
                fail("\(scenario.name): the turn's clock would not hold still for the image", status: 70)
            }
            for picture in taken {
                do {
                    try picture.png.write(to: outputFolder.appendingPathComponent(picture.name))
                } catch {
                    fail("could not write \(picture.name): \(error.localizedDescription)", status: 73)
                }
                print("\(picture.name)  \(Int(picture.size.width * pixelsPerPoint))x\(Int(picture.size.height * pixelsPerPoint)) px")
            }
        }
    }
}
L10n.shared.language = languageBefore
// Nothing is kept: the first copy removes the emptied files.
for domain in [snapshotDomain, ownDomain] {
    UserDefaults.standard.removePersistentDomain(forName: domain)
}
UserDefaults.standard.synchronize()
exit(0)
