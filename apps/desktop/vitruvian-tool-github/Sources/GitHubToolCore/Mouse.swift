// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

/// Where the GravaStar mouse command lives on this Mac. It is built from
/// `packages/peripherals` in vitruvian-core; the Vitruvian app carries a
/// copy in `Contents/Helpers`, Homebrew installs one
/// (`brew install vitruviansoftware/tap/gravastar-mouse`), and the package's
/// README puts one in `~/.local/bin`.
public enum MouseCommand {
    public static let name = "gravastar-mouse"
    /// The app's own copy, when the app is where it is usually installed.
    public static let appCopy = "/Applications/Vitruvian.app/Contents/Helpers/gravastar-mouse"

    /// Install locations a program started by the app does not have on its
    /// PATH, in the order they are tried.
    public static func searchDirectories(home: String) -> [String] {
        [(home as NSString).appendingPathComponent(".local/bin"), "/opt/homebrew/bin", "/usr/local/bin",
         (home as NSString).appendingPathComponent("bin")]
    }

    /// The configured path first (`~` expanded), then the app's own copy,
    /// then each absolute PATH entry, then the usual install locations. Nil
    /// when none is executable, so the mouse is simply left alone.
    public static func locate(configured: String, appCopy: String = appCopy, environment: [String: String],
                              home: String, isExecutable: (String) -> Bool) -> String? {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let explicit = expandingTilde(trimmed, home: home)
            if isExecutable(explicit) { return explicit }
        }
        if isExecutable(appCopy) { return appCopy }
        // A relative PATH entry would resolve against the tool's working
        // directory, so only absolute ones count.
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var seen = Set<String>()
        return (path + searchDirectories(home: home))
            .filter { seen.insert($0).inserted }
            .map { ($0 as NSString).appendingPathComponent(name) }
            .first(where: isExecutable)
    }

    /// True when a path is configured and does not run, so `locate` passed
    /// over it.
    public static func configuredIsIgnored(configured: String, home: String, isExecutable: (String) -> Bool) -> Bool {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !isExecutable(expandingTilde(trimmed, home: home))
    }

    private static func expandingTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return (home as NSString).appendingPathComponent(String(path.dropFirst(2))) }
        return path
    }
}

/// One light, as the person writes it in a mouse setting and as the mouse
/// command takes it: `green`, `breathe orange`, or `breathe blue 9` (a
/// breathe speed of 0 to 9). A word the mouse command does not know is
/// passed to it as written; the command refuses it and the mouse keeps its
/// light.
public struct MouseLight: Equatable, Sendable {
    public let color: String
    public let breathes: Bool
    public let speed: Int?

    public init(color: String, breathes: Bool = false, speed: Int? = nil) {
        self.color = color
        self.breathes = breathes
        self.speed = speed
    }

    /// Nil for empty text, or text with more words than a light has.
    public static func parse(_ text: String) -> MouseLight? {
        var words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        let breathes = words.first == "breathe"
        if breathes { words.removeFirst() }
        var speed: Int?
        if words.count == 2, breathes, let number = Int(words[1]) {
            speed = min(9, max(0, number))
            words.removeLast()
        }
        guard words.count == 1 else { return nil }
        return MouseLight(color: words[0], breathes: breathes, speed: speed)
    }

    /// The mouse command's arguments: `breathe <colour> [--speed n]` or
    /// `color <colour>`.
    public var arguments: [String] {
        guard breathes else { return ["color", color] }
        var arguments = ["breathe", color]
        if let speed { arguments += ["--speed", String(speed)] }
        return arguments
    }
}

/// How the mouse shows each verdict: the five preferences the manifest
/// declares, read as the person typed them. One that cannot be read as a
/// light falls back to the default for its verdict.
public struct MouseSettings: Equatable, Sendable {
    public static let defaults = MouseSettings()

    public var success = "green"
    public var running = "breathe orange"
    public var failure = "breathe red"
    /// While a check waits for approval. It outranks every verdict.
    public var approval = "breathe blue 9"
    /// `restore` puts the person's own lighting back when nothing is
    /// watched; `off` turns the light off.
    public var idle = "restore"

    public init() {}

    public init(success: String, running: String, failure: String, approval: String, idle: String) {
        self.success = success
        self.running = running
        self.failure = failure
        self.approval = approval
        self.idle = idle
    }
}

/// Turns a verdict into one `gravastar-mouse` command, and sends it once:
/// a repeated state writes nothing, unless forced, because the mouse keeps
/// its last light across runs and the first snapshot after a start must
/// always write.
public final class MouseDriver {
    public typealias Executor = ([String]) -> Void

    private enum Shown: Equatable {
        case awaitingApproval
        case verdict(Verdict)
    }

    private var lastShown: Shown?
    private let executor: Executor

    /// `executor` runs one command, such as `["color", "green"]`.
    public init(executor: @escaping Executor) {
        self.executor = executor
    }

    /// The command for a verdict. A check waiting for approval outranks
    /// every verdict, red included.
    public static func arguments(verdict: Verdict, awaitingApproval: Bool, settings: MouseSettings) -> [String] {
        func light(_ text: String, or fallback: String) -> [String] {
            (MouseLight.parse(text) ?? MouseLight.parse(fallback) ?? MouseLight(color: "green")).arguments
        }
        if awaitingApproval { return light(settings.approval, or: MouseSettings.defaults.approval) }
        switch verdict {
        case .green: return light(settings.success, or: MouseSettings.defaults.success)
        case .amber: return light(settings.running, or: MouseSettings.defaults.running)
        case .red: return light(settings.failure, or: MouseSettings.defaults.failure)
        case .grey: return settings.idle.trimmingCharacters(in: .whitespaces).lowercased() == "off" ? ["off"] : ["restore"]
        }
    }

    /// Shows what a summary comes to.
    public func update(summary: GitHubSummary, settings: MouseSettings, force: Bool = false) {
        update(verdict: summary.aggregate, awaitingApproval: summary.awaitingApproval, settings: settings, force: force)
    }

    public func update(verdict: Verdict, awaitingApproval: Bool = false, settings: MouseSettings, force: Bool = false) {
        let shown: Shown = awaitingApproval ? .awaitingApproval : .verdict(verdict)
        guard force || shown != lastShown else { return }
        lastShown = shown
        executor(Self.arguments(verdict: verdict, awaitingApproval: awaitingApproval, settings: settings))
    }

    /// Shows one test's light now, as Settings' test buttons ask, and
    /// forgets what was shown, so the next snapshot writes the real state
    /// back over it.
    public func test(_ test: MouseTest, settings: MouseSettings) {
        lastShown = nil
        executor(test.arguments(settings: settings))
    }

    /// Puts the person's own lighting back, and forgets what was shown.
    public func restore() {
        lastShown = nil
        executor(["restore"])
    }

    /// Runs the command at `binary` with `arguments`, and does not wait for
    /// it. The tool's one thread stays free; the mouse answers in its own
    /// time.
    public static func run(binary: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

/// One of Settings' mouse test buttons: the light the mouse shows for one
/// state, on demand. The raw value is the button's id.
public enum MouseTest: String, CaseIterable, Sendable {
    case approval = "testApproval"
    case success = "testSuccess"
    case running = "testRunning"
    case failure = "testFailure"
    case idle = "testIdle"

    /// The verdict, and whether a check waits for approval, it stands for.
    public var verdict: Verdict {
        switch self {
        case .approval, .success: return .green
        case .running: return .amber
        case .failure: return .red
        case .idle: return .grey
        }
    }

    public var awaitingApproval: Bool { self == .approval }

    /// The words on its button, a key of `Words`.
    public var wordKey: String {
        switch self {
        case .approval: return "awaitingApproval"
        case .success: return "checkPassed"
        case .running: return "checkRunning"
        case .failure: return "checkFailed"
        case .idle: return "idle"
        }
    }

    /// The mouse command's arguments for it, from the person's settings.
    public func arguments(settings: MouseSettings) -> [String] {
        MouseDriver.arguments(verdict: verdict, awaitingApproval: awaitingApproval, settings: settings)
    }
}
