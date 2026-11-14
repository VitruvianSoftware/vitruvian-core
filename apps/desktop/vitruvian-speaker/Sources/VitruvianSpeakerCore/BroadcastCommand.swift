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
import os

/// Shared detection of non-interactive / subagent coding sessions where
/// `speaker-broadcast` speech should be suppressed cleanly.
public enum SubagentDetection {
    public static let suppressedMessage = "Subagent / non-interactive session detected. Broadcast suppressed."

    public static func isClaudeSubagent(environment: [String: String]) -> Bool {
        environment["CLAUDE_CODE_CHILD_SESSION"] == "1"
            || environment["CLAUDE_CODE_SESSION_ATTENDED"] == "0"
            || environment["CLAUDE_CODE_ENTRYPOINT"] == ClaudeStopHook.sdkCliEntrypoint
    }

    public static func isAntigravitySubagent(
        environment: [String: String],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let conversationID = environment["ANTIGRAVITY_CONVERSATION_ID"], !conversationID.isEmpty else {
            return false
        }
        let appDataDirectory: URL
        if let rawAppData = environment["ANTIGRAVITY_APP_DATA_DIR"], !rawAppData.isEmpty {
            appDataDirectory = URL(fileURLWithPath: rawAppData, isDirectory: true)
        } else {
            appDataDirectory = home.appendingPathComponent(".gemini/antigravity", isDirectory: true)
        }
        let brainDirectory = appDataDirectory.appendingPathComponent("brain", isDirectory: true)
        return AntigravityHook.hasSubagentMarker(
            conversationID: conversationID,
            brainDirectory: brainDirectory,
            fileManager: fileManager
        )
    }

    public static func isSuppressed(
        environment: [String: String],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        isClaudeSubagent(environment: environment)
            || isAntigravitySubagent(environment: environment, home: home, fileManager: fileManager)
    }
}

/// Front-end for Vitruvian Speaker when invoked under the `speaker-broadcast` name.
public enum BroadcastCommand {
    public static let commandName = "speaker-broadcast"
    public static let explicitInvocationFlag = "--broadcast-cli"

    public struct OptionSpec: Sendable, Equatable {
        public enum Category: Sendable, Equatable {
            case positional
            case speaking
            case command
        }

        public let syntax: String
        public let summary: String
        public let isPositional: Bool
        public let category: Category

        public init(syntax: String, summary: String, isPositional: Bool = false, category: Category) {
            self.syntax = syntax
            self.summary = summary
            self.isPositional = isPositional
            self.category = category
        }
    }

    public static let optionSpecs: [OptionSpec] = [
        OptionSpec(
            syntax: "\"<message>\"",
            summary: "Speak <message> on the active target speaker",
            isPositional: true,
            category: .positional
        ),
        OptionSpec(
            syntax: "-t, --target <alias>",
            summary: "Speak once on another speaker without changing the default",
            category: .speaking
        ),
        OptionSpec(
            syntax: "-f, --force",
            summary: "Speak even during quiet hours or snooze",
            category: .speaking
        ),
        OptionSpec(
            syntax: "--on",
            summary: "Turn broadcasting ON",
            category: .command
        ),
        OptionSpec(
            syntax: "--off",
            summary: "Turn broadcasting OFF",
            category: .command
        ),
        OptionSpec(
            syntax: "--toggle",
            summary: "Toggle broadcasting ON/OFF",
            category: .command
        ),
        OptionSpec(
            syntax: "-s, --set-target <alias>",
            summary: "Change the persistent default speaker (exact or loose match)",
            category: .command
        ),
        OptionSpec(
            syntax: "-l, --list",
            summary: "List configured speakers and rooms (* = default)",
            category: .command
        ),
        OptionSpec(
            syntax: "--status",
            summary: "Show current enabled state, active target, voices, and quiet hours",
            category: .command
        ),
        OptionSpec(
            syntax: "-h, --help",
            summary: "Show this help text and exit",
            category: .command
        ),
    ]

    public enum ToggleAction: String, Equatable, Sendable {
        case on
        case off
        case toggle
    }

    public enum Request: Equatable, Sendable {
        case help
        case status
        case showDefaultStatus
        case list
        case setEnabled(ToggleAction)
        case setTarget(String)
        case speak(message: String, target: String?, force: Bool)
    }

    public enum TargetMatch: Equatable, Sendable {
        case matched(key: String, device: SpeakerDevice)
        case ambiguous([(key: String, device: SpeakerDevice)])
        case notFound(String)

        public static func == (lhs: TargetMatch, rhs: TargetMatch) -> Bool {
            switch (lhs, rhs) {
            case (.matched(let lk, let ld), .matched(let rk, let rd)):
                return lk == rk && ld == rd
            case (.ambiguous(let lm), .ambiguous(let rm)):
                return lm.count == rm.count && zip(lm, rm).allSatisfy { $0.key == $1.key && $0.device == $1.device }
            case (.notFound(let lq), .notFound(let rq)):
                return lq == rq
            default:
                return false
            }
        }
    }

    /// True when `argv0`'s basename is `speaker-broadcast` (without following symlinks).
    public static func isInvocation(argv0: String?) -> Bool {
        guard let argv0, !argv0.isEmpty else { return false }
        return (argv0 as NSString).lastPathComponent == commandName
    }

    /// Returns the `speaker-broadcast` arguments when invoked either via `speaker-broadcast`
    /// symlink (`argv[0]` basename) or via the explicit `--broadcast-cli` shim flag.
    public static func invocationArguments(argv: [String] = CommandLine.arguments) -> [String]? {
        if isInvocation(argv0: argv.first) {
            return Array(argv.dropFirst())
        }
        if argv.dropFirst().first == explicitInvocationFlag {
            return Array(argv.dropFirst(2))
        }
        return nil
    }

    // MARK: - Parsing

    /// Parses CLI arguments passed after `argv[0]` into a `Request`.
    public static func parse(_ arguments: [String]) -> Result<Request, UsageError> {
        if arguments.isEmpty {
            return .success(.showDefaultStatus)
        }

        enum ModeFlag {
            case help
            case status
            case list
            case enabled(ToggleAction)
            case setTarget(String)
        }

        var mode: ModeFlag?
        var targetOverride: String?
        var force = false
        var messageWords: [String] = []
        var sawMessageTokens = false
        var literalOnly = false

        var index = 0
        while index < arguments.count {
            let arg = arguments[index]

            if !literalOnly {
                if arg == "--" {
                    literalOnly = true
                    index += 1
                    continue
                }
                if arg == "-h" || arg == "--help" {
                    return .success(.help)
                }
                if arg == "--status" {
                    if mode != nil { return .failure(UsageError("conflicting options: \(arg)")) }
                    mode = .status
                    index += 1
                    continue
                }
                if arg == "-l" || arg == "--list" {
                    if mode != nil { return .failure(UsageError("conflicting options: \(arg)")) }
                    mode = .list
                    index += 1
                    continue
                }
                if arg == "--on" {
                    if mode != nil { return .failure(UsageError("conflicting options: \(arg)")) }
                    mode = .enabled(.on)
                    index += 1
                    continue
                }
                if arg == "--off" {
                    if mode != nil { return .failure(UsageError("conflicting options: \(arg)")) }
                    mode = .enabled(.off)
                    index += 1
                    continue
                }
                if arg == "--toggle" {
                    if mode != nil { return .failure(UsageError("conflicting options: \(arg)")) }
                    mode = .enabled(.toggle)
                    index += 1
                    continue
                }
                if arg == "-f" || arg == "--force" {
                    force = true
                    index += 1
                    continue
                }
                if arg == "-s" || arg == "--set-target" {
                    if mode != nil { return .failure(UsageError("conflicting options: \(arg)")) }
                    guard index + 1 < arguments.count else {
                        return .failure(UsageError("\(arg) requires a speaker alias or room"))
                    }
                    let value = arguments[index + 1]
                    guard !value.isEmpty else {
                        return .failure(UsageError("\(arg) requires a speaker alias or room"))
                    }
                    mode = .setTarget(value)
                    index += 2
                    continue
                }
                if arg.hasPrefix("--set-target=") {
                    if mode != nil { return .failure(UsageError("conflicting options: --set-target")) }
                    let value = String(arg.dropFirst("--set-target=".count))
                    guard !value.isEmpty else {
                        return .failure(UsageError("--set-target requires a speaker alias or room"))
                    }
                    mode = .setTarget(value)
                    index += 1
                    continue
                }
                if arg == "-t" || arg == "--target" {
                    guard index + 1 < arguments.count else {
                        return .failure(UsageError("\(arg) requires a speaker alias or room"))
                    }
                    let value = arguments[index + 1]
                    guard !value.isEmpty else {
                        return .failure(UsageError("\(arg) requires a speaker alias or room"))
                    }
                    targetOverride = value
                    index += 2
                    continue
                }
                if arg.hasPrefix("--target=") {
                    let value = String(arg.dropFirst("--target=".count))
                    guard !value.isEmpty else {
                        return .failure(UsageError("--target requires a speaker alias or room"))
                    }
                    targetOverride = value
                    index += 1
                    continue
                }
                if arg.hasPrefix("-") && arg != "-" {
                    return .failure(UsageError("unknown option: \(arg)"))
                }
            }

            sawMessageTokens = true
            messageWords.append(arg)
            index += 1
        }

        if let mode {
            if sawMessageTokens || targetOverride != nil || force {
                return .failure(UsageError("mode flags (--status, --list, --on, --off, --toggle, --set-target) cannot be combined with a message or --target/--force"))
            }
            switch mode {
            case .help: return .success(.help)
            case .status: return .success(.status)
            case .list: return .success(.list)
            case .enabled(let toggle): return .success(.setEnabled(toggle))
            case .setTarget(let alias): return .success(.setTarget(alias))
            }
        }

        let joined = messageWords.joined(separator: " ")
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if targetOverride != nil {
                return .failure(UsageError("-t/--target requires a message (use --set-target to change the default)"))
            }
            if force {
                return .failure(UsageError("--force requires a message"))
            }
            return .failure(UsageError("message cannot be empty"))
        }

        return .success(.speak(message: joined, target: targetOverride, force: force))
    }

    // MARK: - Target Resolution

    private static func normalizeAlias(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    /// Resolves `query` against `config.targets`:
    /// 1. Exact key match
    /// 2. Exact match after lower-casing and converting spaces to underscores (key, name, or room)
    /// 3. Substring match against normalized key, name, or room
    public static func resolveTarget(_ query: String, in config: SpeakerConfig) -> TargetMatch {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notFound(query) }

        if let exact = config.targets[trimmed] {
            return .matched(key: trimmed, device: exact)
        }

        let normalized = normalizeAlias(trimmed)
        guard !normalized.isEmpty else { return .notFound(query) }

        if let normExact = config.targets[normalized] {
            return .matched(key: normalized, device: normExact)
        }

        let sortedEntries: [(key: String, device: SpeakerDevice)] = config.targets
            .map { (key: $0.key, device: $0.value) }
            .sorted { $0.key < $1.key }

        let exactFieldMatches = sortedEntries.filter { key, device in
            normalizeAlias(key) == normalized
                || normalizeAlias(device.name) == normalized
                || SpeakerDevice.alias(for: device.name) == normalized
                || (device.room.map { normalizeAlias($0) == normalized } ?? false)
        }
        if let resolved = collapseAliasMatches(exactFieldMatches, defaultTarget: config.defaultTarget) {
            return resolved
        }

        let substringMatches = sortedEntries.filter { key, device in
            normalizeAlias(key).contains(normalized)
                || normalizeAlias(device.name).contains(normalized)
                || (device.room.map { normalizeAlias($0).contains(normalized) } ?? false)
        }
        if let resolved = collapseAliasMatches(substringMatches, defaultTarget: config.defaultTarget) {
            return resolved
        }

        return .notFound(query)
    }

    private static func collapseAliasMatches(
        _ matches: [(key: String, device: SpeakerDevice)],
        defaultTarget: String
    ) -> TargetMatch? {
        guard !matches.isEmpty else { return nil }
        if matches.count == 1 {
            return .matched(key: matches[0].key, device: matches[0].device)
        }
        let distinctDeviceIDs = Set(matches.map { $0.device.id })
        if distinctDeviceIDs.count == 1 {
            if let currentDefault = matches.first(where: { $0.key == defaultTarget }) {
                return .matched(key: currentDefault.key, device: currentDefault.device)
            }
            let shortest = matches.min {
                if $0.key.count != $1.key.count { return $0.key.count < $1.key.count }
                return $0.key < $1.key
            }!
            return .matched(key: shortest.key, device: shortest.device)
        }
        return .ambiguous(matches)
    }

    // MARK: - Output Formatting

    public static func helpLines() -> [String] {
        let speaking = optionSpecs.filter { $0.category == .speaking }
        let commands = optionSpecs.filter { $0.category == .command }
        let padWidth = (speaking + commands).map(\.syntax.count).max() ?? 24

        var lines = [
            "Usage:",
            "  speaker-broadcast \"<message>\"            Broadcast a message",
            "  speaker-broadcast [OPTIONS] \"<message>\"  Broadcast with options",
            "  speaker-broadcast [COMMAND]",
            "",
            "Speaking options:",
        ]
        for spec in speaking {
            lines.append("  \(spec.syntax.padding(toLength: padWidth, withPad: " ", startingAt: 0))  \(spec.summary)")
        }
        lines.append("")
        lines.append("Commands:")
        for spec in commands {
            lines.append("  \(spec.syntax.padding(toLength: padWidth, withPad: " ", startingAt: 0))  \(spec.summary)")
        }
        lines.append("")
        lines.append("With no arguments, prints --status and a hint.")
        return lines
    }

    public static func formatList(config: SpeakerConfig) -> [String] {
        guard !config.targets.isEmpty else {
            return ["No speakers configured. Open Vitruvian Speaker to discover speakers."]
        }
        var lines = ["Available speakers:"]
        let sorted = config.targets.sorted { $0.key < $1.key }
        for (key, device) in sorted {
            let marker = (key == config.defaultTarget) ? "*" : " "
            let roomSuffix = device.room.flatMap { $0.isEmpty ? nil : $0 }.map { " (Room: \($0))" } ?? ""
            lines.append("  \(marker) \(key.padding(toLength: 20, withPad: " ", startingAt: 0)) \(device.name)\(roomSuffix)")
        }
        return lines
    }

    public static func formatStatus(
        config: SpeakerConfig,
        systemVoices: [LocalVoice] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        var lines: [String] = []
        lines.append("Speaker Broadcast Status: \(config.enabled ? "ENABLED" : "DISABLED")")

        if config.isSnoozed(at: now), let until = config.snoozeUntil {
            lines.append("Snoozed: until \(SpeakerConfig.localTimeHHmm(until, calendar: calendar))")
        }

        if let device = config.defaultDevice {
            if let room = device.room, !room.isEmpty {
                lines.append("Active Target: \(config.defaultTarget) (\(device.name), Room: \(room))")
            } else {
                lines.append("Active Target: \(config.defaultTarget) (\(device.name))")
            }
        } else if config.defaultTarget.isEmpty {
            lines.append("Active Target: none")
        } else {
            lines.append("Active Target: \(config.defaultTarget) (not found)")
        }

        lines.append("Home Speakers: \(config.effectiveSpeakHome ? "ON" : "OFF")")

        let voiceDescription: String
        if config.effectiveLocalEngine == .gemini {
            voiceDescription = "Gemini (\(config.geminiVoiceDisplayName()))"
        } else {
            let matched = systemVoices.first(where: { $0.id == config.effectiveLocalVoice })
            voiceDescription = matched?.pickerLabel ?? config.effectiveLocalVoice
        }
        lines.append("This Mac: \(config.effectiveSpeakLocal ? "ON" : "OFF") (voice: \(voiceDescription))")

        var outputs: [String] = []
        if config.effectiveSpeakHome {
            let targetLabel = config.defaultDevice?.name ?? (config.defaultTarget.isEmpty ? "home speaker" : config.defaultTarget)
            outputs.append("\(targetLabel) (home speaker)")
        }
        if config.effectiveSpeakLocal {
            outputs.append("This Mac (voice: \(voiceDescription))")
        }
        if config.effectiveSpeakPhone {
            outputs.append(SettingsCatalog.macPhoneOutputLabel)
        }
        lines.append("Speaks On: \(outputs.isEmpty ? "nothing (home speakers and this Mac are both off)" : outputs.joined(separator: " + "))")

        let quietStart = config.quietHoursStart.flatMap { $0.isEmpty ? nil : $0 } ?? SettingsCatalog.defaultQuietHoursStart
        let quietEnd = config.quietHoursEnd.flatMap { $0.isEmpty ? nil : $0 } ?? SettingsCatalog.defaultQuietHoursEnd
        let quietStatus: String
        if config.quietHoursEnabled == true {
            quietStatus = config.isInQuietHours(at: now, calendar: calendar)
                ? "ACTIVE (\(quietStart) - \(quietEnd))"
                : "CONFIGURED (\(quietStart) - \(quietEnd))"
        } else {
            quietStatus = "OFF (\(quietStart) - \(quietEnd))"
        }
        lines.append("Quiet Hours: \(quietStatus)")

        return lines
    }

    // MARK: - Execution

    @MainActor
    public static func run(
        _ arguments: [String],
        engine: VitruvianSpeakerEngine,
        parts: VitruvianSpeakerCommandLine.Parts
    ) -> Never {
        let extendsQueue: Bool
        if case .success(.speak) = parse(arguments) {
            extendsQueue = true
        } else {
            extendsQueue = false
        }
        VitruvianSpeakerCommandLine.perform(
            action(
                for: arguments,
                engine: engine,
                parts: parts,
                environment: ProcessInfo.processInfo.environment
            ),
            extendsForSpeechQueue: extendsQueue
        )
    }

    @MainActor
    public static func action(
        for arguments: [String],
        engine: VitruvianSpeakerEngine,
        parts: VitruvianSpeakerCommandLine.Parts,
        environment: [String: String] = [:],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        systemVoices: @Sendable () -> [LocalVoice] = { LocalSpeaker.shared.englishVoices() },
        announcerOverride: Announcer? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> VitruvianSpeakerCommandLine.Action {
        let request: Request
        switch parse(arguments) {
        case .success(let parsed):
            request = parsed
        case .failure(let usage):
            return .now(CLIOutput(stderr: [usage.message, "Try speaker-broadcast --help"], exitCode: 2))
        }

        if case .help = request {
            return .now(CLIOutput(stdout: helpLines(), exitCode: 0))
        }

        let targetEngine = parts.inUseEngine() ?? engine
        let configFile = SpeakerConfigFile(url: targetEngine.profile.settingsURL)

        switch request {
        case .help:
            return .now(CLIOutput(stdout: helpLines(), exitCode: 0))

        case .status, .showDefaultStatus:
            let config: SpeakerConfig
            switch configFile.read() {
            case .loaded(let loaded):
                config = loaded
            case .missing:
                config = parts.inUseSettings() ?? SpeakerConfig()
            case .unreadable(let err):
                return .now(CLIOutput(stderr: [err.localizedDescription], exitCode: 1))
            }
            var lines = formatStatus(config: config, systemVoices: systemVoices(), now: now, calendar: calendar)
            if case .showDefaultStatus = request {
                lines.append("")
                lines.append("Use --help for usage details.")
            }
            return .now(CLIOutput(stdout: lines, exitCode: 0))

        case .list:
            let config: SpeakerConfig
            switch configFile.read() {
            case .loaded(let loaded):
                config = loaded
            case .missing:
                config = parts.inUseSettings() ?? SpeakerConfig()
            case .unreadable(let err):
                return .now(CLIOutput(stderr: [err.localizedDescription], exitCode: 1))
            }
            return .now(CLIOutput(stdout: formatList(config: config), exitCode: 0))

        case .setEnabled(let toggle):
            let currentEnabled: Bool
            switch configFile.read() {
            case .loaded(let loaded):
                currentEnabled = loaded.enabled
            case .missing:
                currentEnabled = (parts.inUseSettings() ?? SpeakerConfig()).enabled
            case .unreadable(let err):
                return .now(CLIOutput(stderr: [err.localizedDescription], exitCode: 1))
            }
            let nextValue: Bool
            switch toggle {
            case .on: nextValue = true
            case .off: nextValue = false
            case .toggle: nextValue = !currentEnabled
            }
            do {
                let result = try SettingsActions.set(
                    key: .enabled,
                    value: .bool(nextValue),
                    in: configFile,
                    secrets: targetEngine.secrets,
                    systemVoices: systemVoices()
                )
                let state = result.config.enabled ? "ENABLED" : "DISABLED"
                return .now(CLIOutput(stdout: ["Speaker Broadcast has been \(state)."], exitCode: 0))
            } catch {
                return .now(CLIOutput(stderr: [error.localizedDescription], exitCode: 1))
            }

        case .setTarget(let alias):
            let current: SpeakerConfig
            switch configFile.read() {
            case .loaded(let loaded):
                current = loaded
            case .missing:
                current = parts.inUseSettings() ?? SpeakerConfig()
            case .unreadable(let err):
                return .now(CLIOutput(stderr: [err.localizedDescription], exitCode: 1))
            }
            switch resolveTarget(alias, in: current) {
            case .notFound:
                return .now(CLIOutput(stderr: ["Target '\(alias)' not found. Use --list to view valid targets."], exitCode: 1))
            case .ambiguous(let matches):
                let names = matches.map { "\($0.key) (\($0.device.name))" }.joined(separator: ", ")
                return .now(CLIOutput(stderr: ["Ambiguous speaker '\(alias)'; matches: \(names)"], exitCode: 1))
            case .matched(let key, let device):
                do {
                    _ = try SettingsActions.set(
                        key: .defaultTarget,
                        value: .string(key),
                        in: configFile,
                        secrets: targetEngine.secrets,
                        systemVoices: systemVoices()
                    )
                    return .now(CLIOutput(stdout: ["Default broadcast target set to: \(key) (\(device.name))"], exitCode: 0))
                } catch {
                    return .now(CLIOutput(stderr: [error.localizedDescription], exitCode: 1))
                }
            }

        case .speak(let message, let targetOverride, let force):
            if SubagentDetection.isSuppressed(environment: environment, home: home, fileManager: fileManager) {
                return .now(CLIOutput(stderr: [SubagentDetection.suppressedMessage], exitCode: 0))
            }

            let loadedConfig: SpeakerConfig
            switch configFile.read() {
            case .loaded(let loaded):
                loadedConfig = loaded
            case .missing:
                loadedConfig = parts.inUseSettings() ?? targetEngine.config.config
            case .unreadable(let err):
                return .now(CLIOutput(stderr: [err.localizedDescription], exitCode: 1))
            }

            // Never mutate disk when `--target` is passed; only adjust an in-memory value.
            var effectiveConfig = loadedConfig
            if let targetOverride {
                switch resolveTarget(targetOverride, in: loadedConfig) {
                case .notFound:
                    return .now(CLIOutput(stderr: ["Target '\(targetOverride)' not found. Use --list to view valid targets."], exitCode: 1))
                case .ambiguous(let matches):
                    let names = matches.map { "\($0.key) (\($0.device.name))" }.joined(separator: ", ")
                    return .now(CLIOutput(stderr: ["Ambiguous speaker '\(targetOverride)'; matches: \(names)"], exitCode: 1))
                case .matched(let key, _):
                    effectiveConfig.defaultTarget = key
                }
            }

            let timeoutSeconds = VitruvianSpeakerCommandLine.announceTimeout(message, config: effectiveConfig)
            let source = BroadcastSource.inferred(from: environment)
            let session = SessionOrigin.fromEnvironment(environment, agent: source.agent)
            let announcer = announcerOverride ?? targetEngine.announcer
            let history = targetEngine.history
            let standsAside = parts.standsAside()
            let door = engine.profile.door
            let asideNote = parts.asideNote()
            let sayConfig = effectiveConfig

            return .headless(timeout: timeoutSeconds, timedOut: CLIOutput.failure("timed out")) {
                await VitruvianSpeakerCommandLine.say(
                    message,
                    config: sayConfig,
                    announcer: announcer,
                    history: history,
                    standsAside: standsAside,
                    door: door,
                    note: asideNote,
                    source: source,
                    session: session,
                    inUse: sayConfig,
                    records: true,
                    force: force,
                    at: now
                )
            }
        }
    }
}

/// Manages installing and updating the `~/.local/bin/speaker-broadcast` symlink
/// to point at the active Vitruvian Speaker executable.
public enum BroadcastCommandLink {
    public static let logger = Logger(subsystem: "com.vitruviansoftware.speaker", category: "broadcast-command-link")

    public enum ExistingEntry: Equatable, Sendable {
        case missing
        case symlink(destination: String, targetExists: Bool)
        case otherFile
    }

    public enum Decision: Equatable, Sendable {
        case alreadyCurrent
        case create
        case replace(reason: String)
        case leaveAlone(reason: String)
    }

    public static func linkURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".local/bin", isDirectory: true)
            .appendingPathComponent(BroadcastCommand.commandName, isDirectory: false)
    }

    /// True when `path` looks like a Vitruvian Speaker or legacy HomeSpeaker executable
    /// (either `.../Tools/dev.vitruvian.speaker/bin/tool`, `.../Tools/dev.vitruvian.homespeaker/bin/tool`,
    /// or inside a `Vitruvian Speaker.app`, `VitruvianSpeaker.app`, or `HomeSpeaker.app` bundle).
    public static func isSpeakerOrLegacyProgram(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).standardized.pathComponents
        if components.contains("Vitruvian Speaker.app")
            || components.contains("VitruvianSpeaker.app")
            || components.contains("HomeSpeaker.app") {
            return true
        }
        if components.count >= 4 {
            let suffix = Array(components.suffix(4))
            if suffix == ["Tools", "dev.vitruvian.speaker", "bin", "tool"]
                || suffix == ["Tools", "dev.vitruvian.homespeaker", "bin", "tool"] {
                return true
            }
        }
        return false
    }

    public static func decide(
        existing: ExistingEntry,
        targetPath: String,
        linkDirectory: URL
    ) -> Decision {
        let normalizedTarget = URL(fileURLWithPath: targetPath).standardizedFileURL.path
        switch existing {
        case .missing:
            return .create
        case .otherFile:
            return .leaveAlone(reason: "~/.local/bin/speaker-broadcast exists and is not a symlink")
        case .symlink(let destination, let targetExists):
            let resolvedDestination = URL(fileURLWithPath: destination, relativeTo: linkDirectory)
                .standardizedFileURL.path
            if targetExists && resolvedDestination == normalizedTarget {
                return .alreadyCurrent
            }
            if !targetExists {
                return .replace(reason: "dangling symlink to \(destination)")
            }
            if isSpeakerOrLegacyProgram(resolvedDestination) {
                return .replace(reason: "symlink points to another Speaker program (\(destination))")
            }
            return .leaveAlone(reason: "~/.local/bin/speaker-broadcast points to \(destination)")
        }
    }

    public static func inspect(at url: URL, fileManager: FileManager = .default) throws -> ExistingEntry {
        var st = stat()
        if lstat(url.path, &st) != 0 {
            let code = errno
            if code == ENOENT || code == ENOTDIR {
                return .missing
            }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        if (st.st_mode & S_IFMT) == S_IFLNK {
            let destination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
            let resolved = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent())
                .standardizedFileURL
            let targetExists = fileManager.fileExists(atPath: resolved.path)
            return .symlink(destination: destination, targetExists: targetExists)
        }
        return .otherFile
    }

    /// Ensures `~/.local/bin/speaker-broadcast` points at `targetPath` according to `decide(...)`.
    /// Failures are logged, never fatal.
    @discardableResult
    public static func ensureInstalled(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        targetPath: String,
        fileManager: FileManager = .default,
        log: (String) -> Void = { logger.notice("\($0, privacy: .public)") }
    ) -> Decision? {
        guard !targetPath.isEmpty,
              !OtherDoorPresence.isInTrash(targetPath),
              !OtherDoorPresence.isOnTemporaryVolume(targetPath) else {
            return nil
        }

        let url = linkURL(home: home)
        let directory = url.deletingLastPathComponent()

        do {
            let existing = try inspect(at: url, fileManager: fileManager)
            let decision = decide(existing: existing, targetPath: targetPath, linkDirectory: directory)
            switch decision {
            case .alreadyCurrent:
                return decision
            case .leaveAlone(let reason):
                log("leaving ~/.local/bin/speaker-broadcast unchanged: \(reason)")
                return decision
            case .create:
                if !fileManager.fileExists(atPath: directory.path) {
                    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: targetPath)
                return decision
            case .replace:
                if !fileManager.fileExists(atPath: directory.path) {
                    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                let stagingURL = directory.appendingPathComponent(".\(BroadcastCommand.commandName).\(UUID().uuidString).tmp")
                try fileManager.createSymbolicLink(atPath: stagingURL.path, withDestinationPath: targetPath)
                if Darwin.rename(stagingURL.path, url.path) != 0 {
                    let err = errno
                    try? fileManager.removeItem(at: stagingURL)
                    throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
                }
                return decision
            }
        } catch {
            log("could not install ~/.local/bin/speaker-broadcast -> \(targetPath): \(error.localizedDescription)")
            return nil
        }
    }
}
