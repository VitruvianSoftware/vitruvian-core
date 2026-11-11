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

/// Brings what a person had in Nexus Agent over to Vitruvian Code, once, on
/// the new app's first launch.
///
/// The app was renamed, and macOS keys everything about an app to its bundle
/// ID, so the new app starts with an empty settings domain and empty folders.
/// Nothing the person made is lost, though: this copies it across. It is the
/// one place in the repository that still names Nexus Agent, because it has to
/// (docs/superpowers/specs/2026-11-10-vitruvian-code-rename-design.md).
///
/// - Settings: every saved setting of the old app that the new one lacks.
/// - Folders: Application Support and the bot's home, with file modes kept
///   (the bot's `.env` is private to its owner). Nothing is overwritten, and
///   the old folders are left where they are.
/// - Automations: each `nexus-agent.automation.*` LaunchAgent is unloaded,
///   written again under its new label and the new program's path, loaded,
///   and the old file removed.
/// - Privacy grants: macOS will not carry these across. They are recorded so
///   the app can say so once, and point at each setting.
///
/// Every step can be run again without changing anything it already did. A
/// step that fails says so in the `Outcome` and keeps the done flag unset,
/// so the next launch tries again; a step is never skipped without a word.
///
/// The home folder, the settings, `launchctl` and the log are handed in, so
/// the tests run it over a temporary home with a launchctl that only writes
/// down what it was asked.
public struct VitruvianCodeLegacyMigration {
    // MARK: - The old names, which only this file may know

    /// The old app's bundle ID, which is also its settings domain.
    public static let legacyBundleID = "com.vitruviansoftware.nexusagent"
    static let legacyStateFolder = "Library/Application Support/NexusAgent"
    static let legacyBotFolder = ".config/nexus-agent"
    static let legacyLaunchdPrefix = "nexus-agent.automation."
    static let legacyKeyPrefix = "nexusAgent."
    static let newKeyPrefix = "vitruvianCode."
    /// Written while the old bot runs; a process id means nothing to the new app.
    static let runtimeFiles: Set<String> = [".bot.pid"]

    // MARK: - What the new app keeps about it

    /// Set once every step has worked. Until then each launch tries again.
    public static let doneKey = "migratedFromNexusAgent"
    /// The permissions the old app relied on, by `Permission.rawValue`.
    public static let permissionsKey = "legacyPermissionsToRegrant"
    /// Set when the person has read the notice about them.
    public static let permissionsExplainedKey = "legacyPermissionsExplained"

    // MARK: - Types

    public enum Step: String, CaseIterable, Sendable {
        case settings, folders, automations

        public var title: String {
            switch self {
            case .settings: return "Settings"
            case .folders: return "Folders"
            case .automations: return "Scheduled automations"
            }
        }
    }

    public struct Failure: Equatable, Sendable {
        public let step: Step
        /// What it was working on: a key, a path, a label.
        public let item: String
        public let message: String

        public init(step: Step, item: String, message: String) {
            self.step = step
            self.item = item
            self.message = message
        }

        public var line: String { "\(step.title): \(item): \(message)" }
    }

    /// What one step did.
    public struct Report: Equatable, Sendable {
        public let step: Step
        public var changes: [String] = []
        public var failures: [Failure] = []

        public init(step: Step) { self.step = step }
    }

    /// A macOS privacy grant the old app used and the new one has to be given.
    public enum Permission: String, CaseIterable, Sendable {
        case accessibility, notifications, filesAndFolders

        public var title: String {
            switch self {
            case .accessibility: return "Accessibility"
            case .notifications: return "Notifications"
            case .filesAndFolders: return "Files and Folders"
            }
        }

        /// What it was for, in the words the notice uses.
        public var reason: String {
            switch self {
            case .accessibility: return "Lets the Quick Prompt shortcut work from any app."
            case .notifications: return "Tells you when a turn is done or needs your approval."
            case .filesAndFolders: return "Lets the agent read and change your Documents, Desktop or Downloads."
            }
        }

        /// The pane of System Settings where it is given.
        public var settingsURL: String {
            switch self {
            case .accessibility:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case .notifications:
                return "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            case .filesAndFolders:
                return "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
            }
        }
    }

    /// The new app's saved settings, as two functions: the shared code names
    /// no app's storage, so the app hands in the storage it keeps them in.
    public struct Settings {
        public var value: (_ key: String) -> Any?
        public var set: (_ value: Any, _ key: String) -> Void

        public init(value: @escaping (String) -> Any?, set: @escaping (Any, String) -> Void) {
            self.value = value
            self.set = set
        }

        func bool(_ key: String) -> Bool { value(key) as? Bool ?? false }
        func strings(_ key: String) -> [String] { value(key) as? [String] ?? [] }

        /// Saves nothing and has nothing: for a caller that only moves folders.
        public static var none: Settings { Settings(value: { _ in nil }, set: { _, _ in }) }
    }

    public struct LaunchctlResult {
        public var status: Int32
        public var output: String

        public init(status: Int32, output: String = "") {
            self.status = status
            self.output = output
        }
    }

    public struct Outcome {
        /// True when an earlier launch had already finished the move.
        public var alreadyDone: Bool
        /// True when there was any sign of the old app on this Mac.
        public var oldInstallFound: Bool
        public var reports: [Report]
        /// What the person has to be asked to give again.
        public var permissions: [Permission]
        /// True once the person has read the notice about `permissions`.
        public var permissionsExplained: Bool

        public var failures: [Failure] { reports.flatMap(\.failures) }
        public var changes: [String] { reports.flatMap(\.changes) }
        /// True when every step worked.
        public var completed: Bool { failures.isEmpty }

        /// Whether the app has something to tell the person: a step that
        /// failed, or permissions they have not been told about yet.
        public var needsNotice: Bool {
            !failures.isEmpty || (!permissions.isEmpty && !permissionsExplained)
        }
    }

    public struct Environment {
        public var home: String
        public var userID: UInt32
        /// The new app's program, which the rewritten LaunchAgents run.
        public var executablePath: String
        /// The new app's saved settings.
        public var settings: Settings
        /// What the old app saved, read without opening its domain as a suite.
        public var readLegacyDefaults: () -> [String: Any]
        public var launchctl: (_ arguments: [String]) -> LaunchctlResult
        public var log: (String) -> Void

        public init(home: String,
                    userID: UInt32,
                    executablePath: String,
                    settings: Settings,
                    readLegacyDefaults: @escaping () -> [String: Any],
                    launchctl: @escaping ([String]) -> LaunchctlResult,
                    log: @escaping (String) -> Void) {
            self.home = home
            self.userID = userID
            self.executablePath = executablePath
            self.settings = settings
            self.readLegacyDefaults = readLegacyDefaults
            self.launchctl = launchctl
            self.log = log
        }
    }

    public var environment: Environment

    public init(environment: Environment) {
        self.environment = environment
    }

    private var fileManager: FileManager { .default }

    // MARK: - Running it

    /// Does whatever is left to do. Safe on every launch: once the done flag
    /// is set it only reports what the person still has to be told.
    public func run() -> Outcome {
        let settings = environment.settings
        let explained = settings.bool(Self.permissionsExplainedKey)

        if settings.bool(Self.doneKey) {
            let stored = settings.strings(Self.permissionsKey).compactMap(Permission.init(rawValue:))
            return Outcome(alreadyDone: true, oldInstallFound: !stored.isEmpty, reports: [],
                           permissions: stored, permissionsExplained: explained)
        }

        let found = oldInstallExists()
        environment.log(found ? "found an earlier Nexus Agent install; moving it over"
                              : "no earlier Nexus Agent install; nothing to move")

        var reports: [Report] = []
        if found {
            reports.append(migrateSettings())
            reports.append(migrateFolders())
            reports.append(migrateAutomations())
        }
        let permissions = found ? permissionsRelied() : []

        let outcome = Outcome(alreadyDone: false, oldInstallFound: found, reports: reports,
                              permissions: permissions, permissionsExplained: explained)
        if !permissions.isEmpty && !explained {
            settings.set(permissions.map(\.rawValue), Self.permissionsKey)
        }
        if outcome.completed {
            settings.set(true, Self.doneKey)
            environment.log("done: \(outcome.changes.count) change(s)")
        } else {
            for failure in outcome.failures { environment.log("FAILED, will retry next launch: \(failure.line)") }
        }
        return outcome
    }

    /// Records that the person has read the notice about the permissions.
    public func markPermissionsExplained() {
        environment.settings.set(true, Self.permissionsExplainedKey)
    }

    /// The folder step alone, for the Code tool inside Vitruvian, which may be
    /// the first program to run after the rename. The same copy, the same rule
    /// that nothing is overwritten.
    public static func moveFolders(home: String = NSHomeDirectory(), log: @escaping (String) -> Void) -> Report {
        VitruvianCodeLegacyMigration(environment: Environment(
            home: home, userID: getuid(), executablePath: "", settings: .none,
            readLegacyDefaults: { [:] }, launchctl: { _ in LaunchctlResult(status: 0) }, log: log)).migrateFolders()
    }

    // MARK: - Where things live

    func path(_ relative: String) -> String {
        (environment.home as NSString).appendingPathComponent(relative)
    }

    var launchAgentsDirectory: String { path("Library/LaunchAgents") }

    private func legacyLaunchAgentFiles() -> [String] {
        let names = (try? fileManager.contentsOfDirectory(atPath: launchAgentsDirectory)) ?? []
        return names.filter { $0.hasPrefix(Self.legacyLaunchdPrefix) && $0.hasSuffix(".plist") }.sorted()
    }

    private func oldInstallExists() -> Bool {
        !environment.readLegacyDefaults().isEmpty
            || fileManager.fileExists(atPath: path(Self.legacyStateFolder))
            || fileManager.fileExists(atPath: path(Self.legacyBotFolder))
            || !legacyLaunchAgentFiles().isEmpty
    }

    // MARK: - Settings

    /// The key a legacy key is kept under now. Most keep their name; the two
    /// that carried the old app's name in it are renamed.
    public static func newKey(forLegacy key: String) -> String {
        key.hasPrefix(legacyKeyPrefix) ? newKeyPrefix + key.dropFirst(legacyKeyPrefix.count) : key
    }

    func migrateSettings() -> Report {
        var report = Report(step: .settings)
        let old = environment.readLegacyDefaults()
        let settings = environment.settings
        for key in old.keys.sorted() {
            // The system's own keys (languages, locale) are not the app's.
            if key.hasPrefix("Apple") { continue }
            let target = Self.newKey(forLegacy: key)
            if settings.value(target) != nil { continue }
            settings.set(old[key] as Any, target)
            if settings.value(target) == nil {
                report.failures.append(Failure(step: .settings, item: target, message: "could not be saved"))
            } else {
                report.changes.append("copied setting \(target)")
            }
        }
        for change in report.changes { environment.log(change) }
        return report
    }

    // MARK: - Folders

    public func migrateFolders() -> Report {
        var report = Report(step: .folders)
        let pairs = [
            (path(Self.legacyStateFolder), VitruvianCodeSupport.defaultStateDirectory(home: environment.home)),
            (path(Self.legacyBotFolder), VitruvianCodeSupport.defaultBotDirectory(home: environment.home)),
        ]
        for (source, destination) in pairs {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            copyTree(from: source, to: destination, isTop: true, report: &report)
        }
        for change in report.changes { environment.log(change) }
        return report
    }

    /// Copies what `destination` does not have. A file that is there is left
    /// as it is, whatever it holds: it is the new app's, or an earlier run's.
    private func copyTree(from source: String, to destination: String, isTop: Bool, report: inout Report) {
        let fm = fileManager
        do {
            let attributes = try fm.attributesOfItem(atPath: source)
            let type = attributes[.type] as? FileAttributeType
            let mode = attributes[.posixPermissions] as? NSNumber

            switch type {
            case .typeDirectory:
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: destination, isDirectory: &isDirectory) {
                    guard isDirectory.boolValue else {
                        report.failures.append(Failure(step: .folders, item: destination,
                                                       message: "is a file, but the old one is a folder"))
                        return
                    }
                } else {
                    try fm.createDirectory(atPath: destination, withIntermediateDirectories: true,
                                           attributes: mode.map { [.posixPermissions: $0] })
                    report.changes.append("created folder \(destination)")
                }
                let names = try fm.contentsOfDirectory(atPath: source).sorted()
                for name in names {
                    if isTop && Self.runtimeFiles.contains(name) { continue }
                    copyTree(from: (source as NSString).appendingPathComponent(name),
                             to: (destination as NSString).appendingPathComponent(name),
                             isTop: false, report: &report)
                }

            case .typeSymbolicLink:
                if (try? fm.attributesOfItem(atPath: destination)) != nil { return }
                let target = try fm.destinationOfSymbolicLink(atPath: source)
                try fm.createSymbolicLink(atPath: destination, withDestinationPath: target)
                report.changes.append("linked \(destination)")

            case .typeRegular:
                if (try? fm.attributesOfItem(atPath: destination)) != nil { return }
                // Copied under another name and then moved in, so a launch that
                // stops half way leaves no half-written file that later runs
                // would take for the real one.
                let partial = destination + ".migrating-" + UUID().uuidString
                do {
                    try fm.copyItem(atPath: source, toPath: partial)
                    if let mode { try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: partial) }
                    try fm.moveItem(atPath: partial, toPath: destination)
                } catch {
                    try? fm.removeItem(atPath: partial)
                    throw error
                }
                report.changes.append("copied \(destination)")

            default:
                environment.log("left \(source) alone: not a file or folder")
            }
        } catch {
            report.failures.append(Failure(step: .folders, item: source, message: error.localizedDescription))
        }
    }

    // MARK: - Automations

    func migrateAutomations() -> Report {
        var report = Report(step: .automations)
        for file in legacyLaunchAgentFiles() {
            migrateAutomation(file: file, report: &report)
        }
        for change in report.changes { environment.log(change) }
        return report
    }

    private func migrateAutomation(file: String, report: inout Report) {
        let fm = fileManager
        let oldPath = (launchAgentsDirectory as NSString).appendingPathComponent(file)
        func fail(_ message: String) {
            report.failures.append(Failure(step: .automations, item: file, message: message))
        }

        guard let data = fm.contents(atPath: oldPath),
              let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              var plist = parsed as? [String: Any]
        else {
            fail("the property list could not be read")
            return
        }

        let base = String(file.dropLast(".plist".count))
        let oldLabel = (plist["Label"] as? String) ?? base
        let identifier = oldLabel.hasPrefix(Self.legacyLaunchdPrefix)
            ? String(oldLabel.dropFirst(Self.legacyLaunchdPrefix.count))
            : String(base.dropFirst(Self.legacyLaunchdPrefix.count))
        let newLabel = VitruvianCodeAutomationManager.launchdLabelPrefix + identifier
        let newPath = (launchAgentsDirectory as NSString).appendingPathComponent(newLabel + ".plist")

        plist["Label"] = newLabel
        if var arguments = plist["ProgramArguments"] as? [Any], !arguments.isEmpty {
            arguments[0] = environment.executablePath
            plist["ProgramArguments"] = arguments
        }

        do {
            let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try xml.write(to: URL(fileURLWithPath: newPath), options: .atomic)
            try fm.setAttributes([.posixPermissions: NSNumber(value: 0o644)], ofItemAtPath: newPath)
        } catch {
            fail("could not write \(newLabel).plist: \(error.localizedDescription)")
            return
        }

        let domain = "gui/\(environment.userID)"

        // The old one first: left loaded, it and the new one would both run.
        let unloaded = environment.launchctl(["bootout", "\(domain)/\(oldLabel)"])
        guard Self.isUnloaded(unloaded) else {
            fail("could not unload \(oldLabel): \(unloaded.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            return
        }
        // The new one may be loaded already, by a run that stopped before the
        // old file went; load it afresh so it holds what was just written.
        _ = environment.launchctl(["bootout", "\(domain)/\(newLabel)"])
        let loaded = environment.launchctl(["bootstrap", domain, newPath])
        guard loaded.status == 0 else {
            fail("could not load \(newLabel): \(loaded.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            return
        }

        do {
            try fm.removeItem(atPath: oldPath)
        } catch {
            fail("could not remove \(file): \(error.localizedDescription)")
            return
        }
        report.changes.append("moved automation \(oldLabel) to \(newLabel)")
    }

    /// launchctl says a job that is not loaded is an error too (3, or 113);
    /// for a job being unloaded that is the state we wanted.
    static func isUnloaded(_ result: LaunchctlResult) -> Bool {
        if result.status == 0 || result.status == 3 || result.status == 113 { return true }
        let text = result.output.lowercased()
        return text.contains("could not find service") || text.contains("no such process")
    }

    /// Runs `/bin/launchctl`.
    public static func runLaunchctl(_ arguments: [String]) -> LaunchctlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return LaunchctlResult(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return LaunchctlResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    // MARK: - Privacy grants

    /// macOS keeps no list an app may read of what another app was given,
    /// so this is what the old app did, not what it was granted: it asked
    /// for Accessibility (the Quick Prompt shortcut) and for Notifications at
    /// every launch, and it ran the agent in the folder the person chose, which
    /// needs Files and Folders when that is one macOS guards.
    func permissionsRelied() -> [Permission] {
        var permissions: [Permission] = [.accessibility, .notifications]
        let env = VitruvianCodeSupport.defaultBotDirectory(home: environment.home) + "/.env"
        let legacyEnv = path(Self.legacyBotFolder) + "/.env"
        for candidate in [env, legacyEnv] {
            if let text = try? String(contentsOfFile: candidate, encoding: .utf8) {
                let folder = VitruvianCodeEnvFile.parse(text).workingDirectory
                if isGuardedFolder(folder) { permissions.append(.filesAndFolders) }
                break
            }
        }
        return permissions
    }

    private func isGuardedFolder(_ folder: String) -> Bool {
        let trimmed = folder.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let expanded = trimmed == "~" ? environment.home
            : trimmed.hasPrefix("~/") ? path(String(trimmed.dropFirst(2))) : trimmed
        let guarded = [path("Documents"), path("Desktop"), path("Downloads"),
                       path("Library/Mobile Documents"), "/Volumes"]
        return guarded.contains { expanded == $0 || expanded.hasPrefix($0 + "/") }
    }
}
