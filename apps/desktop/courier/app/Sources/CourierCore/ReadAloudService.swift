// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import AVFoundation
import Foundation

/// Pure spoken-text builder for Courier's Read Aloud actions (`docs/read-aloud.md` §1).
public enum ReadAloudText {
    /// Maximum characters spoken in a single Read Aloud utterance.
    public static let maxCharacters = 1_000

    /// Spoken text for a timeline message, or `nil` when the message has no speakable text
    /// (for example an uncaptioned photo, sticker, untranscribed voice note, deleted message,
    /// undecryptable event, unopened view-once item, or timeline note).
    public static func forMessage(
        _ message: TimelineMessage,
        transcript: String? = nil,
        chatTitle: String = ""
    ) -> String? {
        guard !message.isNote else { return nil }
        switch message.kind {
        case .deleted, .undecryptable, .sticker:
            return nil
        default:
            break
        }
        if message.viewOnce, !message.played {
            return nil
        }

        let rawContent: String
        if message.kind == .voiceNote {
            let trimmedTranscript = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedTranscript.isEmpty {
                rawContent = trimmedTranscript
            } else {
                rawContent = messageText(of: message)
            }
        } else {
            rawContent = messageText(of: message)
        }

        let cleaned = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return prefixed(cleaned, mine: message.mine, senderName: message.senderName, senderFallback: chatTitle.isEmpty ? message.sender : chatTitle)
    }

    /// Spoken text for an explicit voice-note transcript ("<Sender> says: <transcript>" or "You said: <transcript>").
    public static func forTranscript(
        _ transcript: String,
        mine: Bool,
        senderName: String,
        chatTitle: String = ""
    ) -> String? {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return prefixed(cleaned, mine: mine, senderName: senderName, senderFallback: chatTitle)
    }

    /// Spoken text for an AI chat summary (the summary text itself, trimmed to 1,000 characters).
    public static func forSummary(_ summary: String) -> String? {
        let cleaned = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return trim(cleaned)
    }

    private static func messageText(of message: TimelineMessage) -> String {
        let richText = message.rich.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !richText.isEmpty {
            return richText
        }
        return message.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prefixed(
        _ text: String,
        mine: Bool,
        senderName: String,
        senderFallback: String
    ) -> String {
        let spoken: String
        if mine {
            spoken = String(localized: "You said: \(text)")
        } else {
            let trimmedSender = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = senderFallback.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedSender = !trimmedSender.isEmpty
                ? trimmedSender
                : (!fallback.isEmpty ? fallback : String(localized: "Someone"))
            spoken = String(localized: "\(resolvedSender) says: \(text)")
        }
        return trim(spoken)
    }

    public static func trim(_ text: String) -> String {
        guard text.count > maxCharacters else { return text }
        return String(text.prefix(maxCharacters))
    }
}

/// Locates and launches the HomeSpeaker macOS app (`com.vitruviansoftware.homespeaker`).
public protocol HomeSpeakerLocating: Sendable {
    func applicationURL() -> URL?
    func binaryURL() -> URL?
    func openApplication(at url: URL) async -> Bool
}

public extension HomeSpeakerLocating {
    func binaryURL() -> URL? {
        guard let appURL = applicationURL() else { return nil }
        let executableURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("HomeSpeaker", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return nil
        }
        return executableURL
    }
}

/// Finds the HomeSpeaker a person actually uses: the Vitruvian extension's `bin/tool` or `HomeSpeaker.app` in an
/// Applications folder. Both take `--say` and `--state` and hand the speaking to whichever HomeSpeaker is in use.
/// A copy anywhere else (a development build in a checkout, say) is never used.
public struct WorkspaceHomeSpeakerLocator: HomeSpeakerLocating {
    public static let bundleIdentifier = "com.vitruviansoftware.homespeaker"
    /// The Vitruvian app, which hosts HomeSpeaker as an extension.
    public static let vitruvianBundleIdentifier = "com.vitruviansoftware.vitruvian"
    /// The extension's binary, relative to the home folder.
    public static let extensionToolPath =
        "Library/Application Support/com.vitruviansoftware.vitruvian/Tools/dev.vitruvian.homespeaker/bin/tool"

    private let home: URL
    private let isExecutable: @Sendable (String) -> Bool
    private let appLookup: @Sendable (String) -> URL?

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        appLookup: @escaping @Sendable (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    ) {
        self.home = home
        self.isExecutable = isExecutable
        self.appLookup = appLookup
    }

    /// True for an app in `/Applications` or `~/Applications` (or a folder inside them).
    func isInstalledApp(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let roots = ["/Applications/", home.appendingPathComponent("Applications").standardizedFileURL.path + "/"]
        return roots.contains { path.hasPrefix($0) }
    }

    private func installedApp(_ bundleIdentifier: String) -> URL? {
        guard let url = appLookup(bundleIdentifier), isInstalledApp(url) else { return nil }
        return url
    }

    /// `HomeSpeaker.app` when installed; otherwise the Vitruvian app when HomeSpeaker is its extension.
    public func applicationURL() -> URL? {
        if let app = installedApp(Self.bundleIdentifier) { return app }
        if extensionToolURL() != nil { return installedApp(Self.vitruvianBundleIdentifier) }
        return nil
    }

    private func extensionToolURL() -> URL? {
        let tool = home.appendingPathComponent(Self.extensionToolPath)
        return isExecutable(tool.path) ? tool : nil
    }

    /// The extension's `bin/tool` first, then the installed app's binary.
    public func binaryURL() -> URL? {
        if let tool = extensionToolURL() { return tool }
        guard let app = installedApp(Self.bundleIdentifier) else { return nil }
        let binary = app.appendingPathComponent("Contents/MacOS/HomeSpeaker")
        return isExecutable(binary.path) ? binary : nil
    }

    public func openApplication(at url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                continuation.resume(returning: app != nil && error == nil)
            }
        }
    }
}

/// Captured exit status and streams from running `Contents/MacOS/HomeSpeaker`.
public struct HomeSpeakerCommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data
    public var timedOut: Bool

    public init(exitCode: Int32, stdout: Data = Data(), stderr: Data = Data(), timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

/// Runs the HomeSpeaker binary directly with an argument array (never `/bin/sh`) off the main actor.
public protocol HomeSpeakerCommandRunning: Sendable {
    func run(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws -> HomeSpeakerCommandResult
}

/// `Foundation.Process` runner executing off the main actor with a hard timeout and no shell interpolation.
public struct FoundationHomeSpeakerCommandRunner: HomeSpeakerCommandRunning {
    public init() {}

    /// How long a timed-out HomeSpeaker gets after SIGTERM before SIGKILL, and how long its pipes are waited on.
    static let killGrace: TimeInterval = 2

    /// The variables HomeSpeaker reads to credit a `--say` to a coding agent (`BroadcastSource.inferred`). Courier
    /// started from an agent's shell inherits them, and its Read Aloud would then be named as that agent's reply,
    /// so they are left out of HomeSpeaker's environment: a Read Aloud is the person's own.
    public static let agentMarkers: Set<String> = ["CLAUDECODE", "ANTIGRAVITY_AGENT", "OPENCODE", "AI_AGENT"]

    /// `environment` without `agentMarkers`.
    public static func childEnvironment(_ environment: [String: String]) -> [String: String] {
        environment.filter { !agentMarkers.contains($0.key) }
    }

    public func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> HomeSpeakerCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                process.environment = Self.childEnvironment(ProcessInfo.processInfo.environment)
                process.standardInput = FileHandle.nullDevice

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                /// What a pipe gave, read on its own thread and taken once the process is done (or given up on).
                final class Collected: @unchecked Sendable {
                    private let lock = NSLock()
                    private var data = Data()
                    func set(_ new: Data) { lock.lock(); data = new; lock.unlock() }
                    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
                }

                let outputGroup = DispatchGroup()
                let stdoutData = Collected()
                let stderrData = Collected()

                outputGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stdoutData.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                    outputGroup.leave()
                }

                outputGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stderrData.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                    outputGroup.leave()
                }

                do {
                    try process.run()
                } catch {
                    try? stdoutPipe.fileHandleForWriting.close()
                    try? stderrPipe.fileHandleForWriting.close()
                    continuation.resume(throwing: error)
                    return
                }

                final class TimeoutFlag: @unchecked Sendable {
                    private let lock = NSLock()
                    private var value = false
                    func markTimedOut() {
                        lock.lock()
                        value = true
                        lock.unlock()
                    }
                    var isTimedOut: Bool {
                        lock.lock()
                        defer { lock.unlock() }
                        return value
                    }
                }

                let timeoutFlag = TimeoutFlag()
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                timer.schedule(deadline: .now() + max(0.05, timeout))
                timer.setEventHandler {
                    guard process.isRunning else { return }
                    timeoutFlag.markTimedOut()
                    process.terminate()
                    // A program that ignores SIGTERM is killed after a short grace period.
                    let pid = process.processIdentifier
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.killGrace) {
                        if process.isRunning { kill(pid, SIGKILL) }
                    }
                }
                timer.resume()

                process.waitUntilExit()
                timer.cancel()
                // A child the program left behind can hold the pipes open: don't wait on them for long.
                _ = outputGroup.wait(timeout: .now() + Self.killGrace)

                continuation.resume(
                    returning: HomeSpeakerCommandResult(
                        exitCode: process.terminationStatus,
                        stdout: stdoutData.value,
                        stderr: stderrData.value,
                        timedOut: timeoutFlag.isTimedOut
                    )
                )
            }
        }
    }
}

/// System speech synthesis fallback when HomeSpeaker is not installed.
@MainActor
public protocol SpeechSynthesizing: AnyObject {
    var isSpeaking: Bool { get }
    func speak(_ text: String)
    func stop()
}

/// `AVSpeechSynthesizer` wrapper used when HomeSpeaker is not installed on this Mac.
@MainActor
public final class SystemSpeechSynthesizer: SpeechSynthesizing {
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    public var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    public func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

/// Status shown in `Settings ▸ Integrations ▸ HomeSpeaker` (`docs/read-aloud.md` §3).
public enum HomeSpeakerIntegrationStatus: Equatable, Sendable {
    /// HomeSpeaker is installed and `courier_enabled` is `true` in `--state --json`.
    case installedReading
    /// HomeSpeaker is installed and `courier_enabled` is `false` in `--state --json`.
    case installedNotReading
    /// HomeSpeaker is installed, before `--state --json` is read or when reading it fails.
    case installed
    /// HomeSpeaker is not installed; Read Aloud speaks with this Mac's system voice.
    case notInstalled

    public var statusLine: String {
        switch self {
        case .installedReading:
            String(localized: "Installed · reads Courier messages aloud")
        case .installedNotReading:
            String(localized: "Installed · not reading Courier (turn it on in HomeSpeaker)")
        case .installed:
            String(localized: "Installed")
        case .notInstalled:
            String(localized: "Not installed · Read Aloud uses this Mac’s voice")
        }
    }

    /// Parses `HomeSpeaker --state --json` output (shape in `apps/desktop/home-speaker/testdata/state_v1.json`).
    /// Falls back to `.installed` if the JSON cannot be decoded or lacks a boolean `courier_enabled` setting.
    public static func parseStateJSON(_ data: Data) -> HomeSpeakerIntegrationStatus {
        guard !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = root["settings"] as? [[String: Any]] else {
            return .installed
        }
        for entry in settings {
            guard (entry["key"] as? String) == "courier_enabled" else { continue }
            if let enabled = entry["value"] as? Bool {
                return enabled ? .installedReading : .installedNotReading
            }
            return .installed
        }
        return .installed
    }
}

/// Coordinates Read Aloud across HomeSpeaker (`--say`) and this Mac's fallback voice (`AVSpeechSynthesizer`),
/// and probes `HomeSpeaker --state --json` for Settings ▸ Integrations.
@MainActor
public final class ReadAloudService: ObservableObject {
    public static let sayTimeout: TimeInterval = 60
    public static let stateTimeout: TimeInterval = 10

    /// Number of in-flight `HomeSpeaker --say` runs; while > 0, the message menu shows disabled `"Reading Aloud…"`.
    @Published public private(set) var activeHomeSpeakerCount: Int = 0

    public var isReadingOnHomeSpeaker: Bool {
        activeHomeSpeakerCount > 0
    }

    public var isHomeSpeakerInstalled: Bool {
        locator.binaryURL() != nil
    }

    /// Receives calm failure notices (`"HomeSpeaker couldn’t read it aloud."` plus HomeSpeaker's error text).
    public var onNotice: @MainActor (String) -> Void = { _ in }

    private let locator: any HomeSpeakerLocating
    private let runner: any HomeSpeakerCommandRunning
    private let synthesizer: any SpeechSynthesizing

    public init(
        locator: any HomeSpeakerLocating = WorkspaceHomeSpeakerLocator(),
        runner: any HomeSpeakerCommandRunning = FoundationHomeSpeakerCommandRunner(),
        synthesizer: (any SpeechSynthesizing)? = nil
    ) {
        self.locator = locator
        self.runner = runner
        self.synthesizer = synthesizer ?? SystemSpeechSynthesizer()
    }

    /// Reads `text` aloud (trimmed to 1,000 characters) via HomeSpeaker when installed, or this Mac's system voice.
    public func readAloud(
        _ text: String,
        onFailureNotice: (@MainActor (String) -> Void)? = nil
    ) async {
        let trimmed = ReadAloudText.trim(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { return }
        let notify = onFailureNotice ?? onNotice

        if let binaryURL = locator.binaryURL() {
            activeHomeSpeakerCount += 1
            defer { activeHomeSpeakerCount = max(0, activeHomeSpeakerCount - 1) }

            do {
                let result = try await runner.run(
                    executableURL: binaryURL,
                    arguments: ["--say", trimmed],
                    timeout: Self.sayTimeout
                )
                if result.timedOut || result.exitCode != 0 {
                    let detail = Self.extractFailureDetail(stdout: result.stdout, stderr: result.stderr)
                    notify(Self.failureNotice(detail: detail))
                }
            } catch {
                let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                notify(Self.failureNotice(detail: detail.isEmpty ? nil : detail))
            }
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stop()
        }
        synthesizer.speak(trimmed)
    }

    /// Probes `HomeSpeaker --state --json` off the main actor when HomeSpeaker is installed.
    public func fetchIntegrationStatus() async -> HomeSpeakerIntegrationStatus {
        guard let binaryURL = locator.binaryURL() else {
            return .notInstalled
        }
        let runner = self.runner
        do {
            let result = try await runner.run(
                executableURL: binaryURL,
                arguments: ["--state", "--json"],
                timeout: Self.stateTimeout
            )
            guard !result.timedOut, result.exitCode == 0 else {
                return .installed
            }
            return HomeSpeakerIntegrationStatus.parseStateJSON(result.stdout)
        } catch {
            return .installed
        }
    }

    /// Launches or activates HomeSpeaker (`Open HomeSpeaker` in Settings ▸ Integrations).
    @discardableResult
    public func openHomeSpeaker() async -> Bool {
        guard let appURL = locator.applicationURL() else { return false }
        return await locator.openApplication(at: appURL)
    }

    public static func failureNotice(detail: String?) -> String {
        guard let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else {
            return String(localized: "HomeSpeaker couldn’t read it aloud.")
        }
        return String(localized: "HomeSpeaker couldn’t read it aloud. \(detail)")
    }

    /// Extracts HomeSpeaker's own error text from JSON or plain-text `stderr` / `stdout`.
    public static func extractFailureDetail(stdout: Data, stderr: Data) -> String? {
        for stream in [stderr, stdout] {
            if let jsonError = parseJSONError(from: stream) {
                return jsonError
            }
        }
        if let stderrText = cleanPlainError(from: stderr) {
            return stderrText
        }
        if let stdoutText = cleanPlainError(from: stdout) {
            return stdoutText
        }
        return nil
    }

    private static func parseJSONError(from data: Data) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let errorString = object["error"] as? String {
            let trimmed = errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let errorDict = object["error"] as? [String: Any],
           let nestedMessage = errorDict["message"] as? String {
            let trimmed = nestedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let message = object["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func cleanPlainError(from data: Data) -> String? {
        guard !data.isEmpty, let raw = String(data: data, encoding: .utf8) else { return nil }
        let lines = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let nonAdvisory = lines.filter { line in
            let lower = line.lowercased()
            return !lower.hasPrefix("note:") && !lower.hasPrefix("warning:")
        }
        let chosen = (nonAdvisory.isEmpty ? lines : nonAdvisory).joined(separator: " ")
        if chosen.lowercased().hasPrefix("error:") {
            let stripped = chosen.dropFirst("error:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? chosen : stripped
        }
        return chosen
    }
}
