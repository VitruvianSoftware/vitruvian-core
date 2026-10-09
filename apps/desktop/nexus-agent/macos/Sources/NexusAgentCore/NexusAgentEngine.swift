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
//
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian/UPSTREAM.md).

import AppKit
import Combine
import Darwin

/// Runs the Nexus Agent Telegram bot from its folder, edits the part of its
/// `.env` a settings page shows, and holds the chat with the agent's CLI.
/// Nothing runs at rest unless the user starts the bot or the app asks for
/// it at launch. The bot shares its PID file and log with the standalone
/// app, so either one sees a bot the other started.
///
/// It knows no app. Settings, text and how the user hears about a turn come
/// from a `NexusAgentHost`; the window the chat is shown in belongs to a
/// subclass, which says whether it is on screen through `isChatVisible`.
@MainActor
open class NexusAgentEngine: NSObject, ObservableObject {
    /// Why the last start or save did not happen, as the page reports it.
    public enum Problem: Equatable {
        case missingToken, missingBot, missingNode, startFailed, saveFailed
    }

    /// Everything the service touches outside itself. `live` is the real
    /// file system, processes and preferences; tests pass doubles.
    @MainActor
    public struct Environment {
        public var defaults: UserDefaults
        public var home: String
        public var processEnvironment: [String: String]
        /// Shared with the standalone app: its PID file and log live here.
        public var stateDirectory: String
        public var isExecutable: (String) -> Bool
        public var fileExists: (String) -> Bool
        public var readFile: (String) -> String?
        /// The last `limit` bytes of a file, for the log.
        public var readTail: (_ path: String, _ limit: Int) -> String?
        /// Writes atomically, readable by the user alone: the file holds a token.
        public var writePrivateFile: (_ path: String, _ content: String) -> Bool
        public var removeFile: (String) -> Void
        /// True only for a live process whose executable is Node, so a stale
        /// PID file reused by another program is never signalled.
        public var isBotProcess: (Int32) -> Bool
        public var signal: (_ pid: Int32, _ signal: Int32) -> Void
        /// Starts Node on the bot with its output appended to the log, and
        /// reports the exit on the main actor. Returns the process id.
        public var launchBot: (_ node: String, _ directory: String, _ logPath: String,
                                _ environment: [String: String],
                                _ onExit: @escaping @MainActor @Sendable (Int32) -> Void) throws -> Int32
        public var schedule: (_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void
        public var openFile: (String) -> Void
        /// Runs one agy turn in `directory`, delivering its output in order and
        /// then its exit status, both on the main actor.
        public var launchAgent: (_ path: String, _ arguments: [String], _ directory: String,
                                  _ environment: [String: String],
                                  _ onOutput: @escaping @MainActor @Sendable (Data) -> Void,
                                  _ onExit: @escaping @MainActor @Sendable (Int32) -> Void) throws -> NexusAgentRunningAgent
        /// agy's or claude's recent conversations for a folder, newest first.
        /// The last argument is the app's list of archived Claude sessions.
        public var listSessions: (_ directory: String, _ provider: NexusAgentCLIProvider,
                                   _ hiddenClaudeSessionIDs: [String]) -> [NexusAgentSessionSummary]
        /// Reads past conversation turns, if present.
        public var readTranscript: (_ id: String, _ provider: NexusAgentCLIProvider) -> [NexusAgentChatMessage]?
        /// Resolves the absolute path to a transcript file if it exists.
        public var transcriptPath: (_ id: String, _ provider: NexusAgentCLIProvider) -> String?
        /// Reads the full raw content of a transcript file.
        public var readTranscriptRaw: (_ id: String, _ provider: NexusAgentCLIProvider) -> String?
        /// Runs a program to its end and gives back what it printed to
        /// standard output, whatever its exit status; nil if it could not
        /// be started. `name` is a bare name (`ollama`) or a full path.
        /// It does not run on the main thread: the program may be slow.
        public var runProgram: @Sendable (_ name: String, _ arguments: [String]) async -> String?

        public init(defaults: UserDefaults,
                     home: String,
                     processEnvironment: [String: String],
                     stateDirectory: String,
                     isExecutable: @escaping (String) -> Bool,
                     fileExists: @escaping (String) -> Bool,
                     readFile: @escaping (String) -> String?,
                     readTail: @escaping (String, Int) -> String?,
                     writePrivateFile: @escaping (String, String) -> Bool,
                     removeFile: @escaping (String) -> Void,
                     isBotProcess: @escaping (Int32) -> Bool,
                     signal: @escaping (Int32, Int32) -> Void,
                     launchBot: @escaping (String, String, String, [String: String],
                                           @escaping @MainActor @Sendable (Int32) -> Void) throws -> Int32,
                     schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void,
                     openFile: @escaping (String) -> Void,
                     launchAgent: @escaping (String, [String], String, [String: String],
                                             @escaping @MainActor @Sendable (Data) -> Void,
                                             @escaping @MainActor @Sendable (Int32) -> Void) throws -> NexusAgentRunningAgent,
                     listSessions: @escaping (String, NexusAgentCLIProvider, [String]) -> [NexusAgentSessionSummary] = { _, _, _ in [] },
                     readTranscript: @escaping (String, NexusAgentCLIProvider) -> [NexusAgentChatMessage]? = { _, _ in nil },
                     transcriptPath: @escaping (String, NexusAgentCLIProvider) -> String? = { _, _ in nil },
                     readTranscriptRaw: @escaping (String, NexusAgentCLIProvider) -> String? = { _, _ in nil },
                     runProgram: @escaping @Sendable (String, [String]) async -> String? = { _, _ in nil }) {
            self.defaults = defaults
            self.home = home
            self.processEnvironment = processEnvironment
            self.stateDirectory = stateDirectory
            self.isExecutable = isExecutable
            self.fileExists = fileExists
            self.readFile = readFile
            self.readTail = readTail
            self.writePrivateFile = writePrivateFile
            self.removeFile = removeFile
            self.isBotProcess = isBotProcess
            self.signal = signal
            self.launchBot = launchBot
            self.schedule = schedule
            self.openFile = openFile
            self.launchAgent = launchAgent
            self.listSessions = listSessions
            self.readTranscript = readTranscript
            self.transcriptPath = transcriptPath
            self.readTranscriptRaw = readTranscriptRaw
            self.runProgram = runProgram
        }

        public static var live: Environment {
            let home = NSHomeDirectory()
            return Environment(
                defaults: .standard,
                home: home,
                processEnvironment: ProcessInfo.processInfo.environment,
                stateDirectory: (home as NSString).appendingPathComponent("Library/Application Support/NexusAgent"),
                isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                fileExists: { FileManager.default.fileExists(atPath: $0) },
                readFile: { try? String(contentsOfFile: $0, encoding: .utf8) },
                readTail: NexusAgentEngine.readTail,
                writePrivateFile: NexusAgentEngine.writePrivateFile,
                removeFile: { try? FileManager.default.removeItem(atPath: $0) },
                isBotProcess: NexusAgentEngine.isNodeProcess,
                signal: { pid, signal in _ = kill(pid, signal) },
                launchBot: NexusAgentEngine.launchNode,
                schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() } },
                openFile: { NSWorkspace.shared.open(URL(fileURLWithPath: $0)) },
                launchAgent: NexusAgentEngine.launchAgentProcess,
                listSessions: { NexusAgentEngine.readSessions(home: home, directory: $0, provider: $1, hiddenClaudeSessionIDs: $2) },
                readTranscript: { NexusAgentEngine.readTranscript(home: home, conversationID: $0, provider: $1) },
                transcriptPath: { NexusAgentEngine.transcriptPath(home: home, conversationID: $0, provider: $1) },
                readTranscriptRaw: { id, provider in
                    guard let path = NexusAgentEngine.transcriptPath(home: home, conversationID: id, provider: provider) else { return nil }
                    return try? String(contentsOfFile: path, encoding: .utf8)
                },
                runProgram: { await NexusAgentEngine.runProgram(named: $0, arguments: $1) })
        }
    }

    @Published public private(set) var isRunning = false
    @Published public private(set) var pid: Int32?
    @Published public private(set) var logLines: [String] = []
    @Published public private(set) var configuration = NexusAgentConfiguration()
    @Published public private(set) var problem: Problem?
    /// Saved while the bot runs: it reads its `.env` only at start.
    @Published public private(set) var needsRestart = false
    @Published public private(set) var agentPath: String?

    public var activeProvider: NexusAgentCLIProvider {
        get { configuration.activeProvider }
        set { updateActiveProvider(newValue) }
    }

    /// Built-in providers with the host's saved edits applied, then the
    /// host's own providers. Asked of the host each time, never kept.
    public var providers: [NexusAgentCLIProvider] {
        NexusAgentCLIProvider.available(saved: host.savedProviders)
    }

    /// A configuration as it should be held: the file knows nothing of the
    /// provider the chat uses, so whatever was just read or built gets the
    /// one the host remembers. Every assignment to `configuration` from a
    /// file goes through here, or the choice would fall back to Antigravity.
    private func withChosenProvider(_ fresh: NexusAgentConfiguration) -> NexusAgentConfiguration {
        var next = fresh
        next.activeProvider = NexusAgentCLIProvider.chosen(id: host.chosenProviderID, among: providers)
        return next
    }

    public let session: NexusAgentQuickPromptSession
    private let environment: Environment
    private let host: any NexusAgentHost
    /// The bot this app launched, as opposed to one adopted from the PID file.
    private var managedPID: Int32?
    private var pollTimer: Timer?
    private var didAutoStart = false

    /// A bot gets this long to stop on SIGTERM before it is killed.
    public static let stopGrace: TimeInterval = 3

    public init(environment: Environment, host: any NexusAgentHost) {
        self.environment = environment
        self.host = host
        session = NexusAgentQuickPromptSession(environment: environment, host: host)
        super.init()
        // Before any file is read the chat already runs the remembered provider.
        configuration = withChosenProvider(configuration)
        session.engine = self
        // The closure keeps the host itself, so a turn that outlives the
        // engine is still reported. With no engine there is no window to be
        // away from, so that report is the in-app one alone, as it is for a
        // session built without an engine.
        session.onTurnFinished = { [weak self, host] notice in
            host.turnFinished(notice, isChatVisible: self?.isChatVisible ?? true)
        }
    }

    /// Whether the user can see the chat right now. The engine has no
    /// window, so a subclass that shows one overrides this.
    open var isChatVisible: Bool { false }

    // MARK: - Paths

    public var botDirectory: String {
        NexusAgentSupport.botDirectory(configured: host.configuredBotDirectory,
                                       home: environment.home)
    }

    public var envFilePath: String { (botDirectory as NSString).appendingPathComponent(".env") }
    public var logPath: String { (environment.stateDirectory as NSString).appendingPathComponent("bot.log") }
    public var pidFilePath: String { (environment.stateDirectory as NSString).appendingPathComponent(".bot.pid") }
    private var entryPointPath: String {
        (botDirectory as NSString).appendingPathComponent(NexusAgentSupport.botEntryPoint)
    }

    public var isBotInstalled: Bool { environment.fileExists(entryPointPath) }

    /// The current problem in words, from the host's text as it is right now;
    /// nil when there is none.
    public var problemDescription: String? {
        switch problem {
        case nil: return nil
        case .missingToken?: return host.strings.problemMissingToken
        case .missingBot?: return host.strings.problemMissingBot
        case .missingNode?: return host.strings.problemMissingNode
        case .startFailed?: return host.strings.problemStartFailed
        case .saveFailed?: return host.strings.problemSaveFailed
        }
    }

    // MARK: - App lifecycle

    /// The app took the feature away: nothing stays resident, the bot included.
    public func stopAfterUninstall() {
        stopPolling()
        session.stop()
        if isRunning || managedPID != nil { stop() }
        didAutoStart = false
    }

    /// Once per launch, and only when asked for: a bot already running
    /// (started by the standalone app, say) is adopted instead.
    public func startOncePerLaunch() {
        if !didAutoStart {
            didAutoStart = true
            refreshStatus()
            if host.startsBotAtLaunch, !isRunning {
                start()
            }
        }
    }

    /// The bot outlives the app, as it does the standalone one; only the
    /// reply in flight belongs to this process.
    public func stopForQuit() {
        session.stop()
        stopPolling()
    }

    // MARK: - Configuration

    /// Reads the bot's `.env` and finds the agent, for the page.
    public func load() {
        configuration = withChosenProvider(
            environment.readFile(envFilePath).map(NexusAgentEnvFile.parse) ?? NexusAgentConfiguration())
        agentPath = NexusAgentSupport.locateAgent(named: configuration.activeProvider.executableName,
                                                  environment: environment.processEnvironment,
                                                  home: environment.home,
                                                  isExecutable: environment.isExecutable)
    }

    /// Switches the chat to `provider` and has the host remember it.
    public func updateActiveProvider(_ provider: NexusAgentCLIProvider) {
        host.chosenProviderID = provider.id
        configuration.activeProvider = provider
        agentPath = NexusAgentSupport.locateAgent(named: provider.executableName,
                                                  environment: environment.processEnvironment,
                                                  home: environment.home,
                                                  isExecutable: environment.isExecutable)
        session.refreshSessions(configuration: configuration)
    }

    /// Writes the page's values into the `.env`, keeping the rest of it.
    @discardableResult
    public func save(_ next: NexusAgentConfiguration) -> Bool {
        guard environment.fileExists(botDirectory) else {
            problem = .missingBot
            return false
        }
        let content = NexusAgentEnvFile.render(next, over: environment.readFile(envFilePath))
        guard environment.writePrivateFile(envFilePath, content) else {
            problem = .saveFailed
            return false
        }
        configuration = withChosenProvider(NexusAgentEnvFile.parse(content))
        problem = nil
        if isRunning { needsRestart = true }
        return true
    }

    // MARK: - Bot

    /// Brings `isRunning` in line with the processes: the one this app
    /// launched, or the one the PID file names if it is still Node.
    public func refreshStatus() {
        if let managedPID {
            setRunning(managedPID)
            return
        }
        if let text = environment.readFile(pidFilePath),
           let recorded = NexusAgentSupport.processID(fromPIDFile: text),
           environment.isBotProcess(recorded) {
            setRunning(recorded)
            return
        }
        if environment.fileExists(pidFilePath) { environment.removeFile(pidFilePath) }
        setRunning(nil)
    }

    public func start() {
        refreshStatus()
        guard !isRunning else { return }
        load()
        guard isBotInstalled else { problem = .missingBot; return }
        guard configuration.isConfigured else { problem = .missingToken; return }
        guard let node = NexusAgentSupport.locateNode(home: environment.home,
                                                      isExecutable: environment.isExecutable) else {
            problem = .missingNode
            return
        }
        let childEnvironment = NexusAgentSupport.childEnvironment(base: environment.processEnvironment,
                                                                  home: environment.home)
        do {
            let launched = try environment.launchBot(node, botDirectory, logPath, childEnvironment) { [weak self] exited in
                self?.botDidExit(exited)
            }
            managedPID = launched
            _ = environment.writePrivateFile(pidFilePath, "\(launched)")
            problem = nil
            needsRestart = false
            setRunning(launched)
            readLog()
        } catch {
            problem = .startFailed
        }
    }

    /// SIGTERM, then SIGKILL if the bot is still there after the grace
    /// period. Only the recorded bot is signalled, never a match by name.
    public func stop(then next: (@MainActor () -> Void)? = nil) {
        refreshStatus()
        guard let target = pid else {
            next?()
            return
        }
        environment.signal(target, SIGTERM)
        managedPID = nil
        environment.removeFile(pidFilePath)
        needsRestart = false
        setRunning(nil)
        awaitExit(of: target, remaining: Self.stopGrace, then: next)
    }

    public func restart() {
        stop { [weak self] in self?.start() }
    }

    public func openLog() {
        guard environment.fileExists(logPath) else { return }
        environment.openFile(logPath)
    }

    private func awaitExit(of target: Int32, remaining: TimeInterval, then next: (@MainActor () -> Void)?) {
        guard environment.isBotProcess(target) else {
            next?()
            return
        }
        guard remaining > 0 else {
            environment.signal(target, SIGKILL)
            next?()
            return
        }
        let step = 0.25
        environment.schedule(step) { [weak self] in
            self?.awaitExit(of: target, remaining: remaining - step, then: next)
        }
    }

    private func botDidExit(_ exited: Int32) {
        guard managedPID == exited else { return }
        managedPID = nil
        if let text = environment.readFile(pidFilePath),
           NexusAgentSupport.processID(fromPIDFile: text) == exited {
            environment.removeFile(pidFilePath)
        }
        setRunning(nil)
        readLog()
    }

    private func setRunning(_ next: Int32?) {
        if pid != next { pid = next }
        if isRunning != (next != nil) { isRunning = next != nil }
    }

    // MARK: - Polling

    /// Only while the page is up: nothing polls at rest.
    public func startPolling() {
        load()
        refreshStatus()
        readLog()
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStatus()
                self?.readLog()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func readLog() {
        let next = environment.readTail(logPath, 16 * 1024).map { NexusAgentSupport.tail($0) } ?? []
        if next != logLines { logLines = next }
    }

    // MARK: - Live effects

    nonisolated private static func readTail(_ path: String, _ limit: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(limit) ? end - UInt64(limit) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        // A cut first line is noise; drop it unless the read began at the top.
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return text
    }

    nonisolated private static func writePrivateFile(_ path: String, _ content: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func isNodeProcess(_ pid: Int32) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return (String(cString: buffer) as NSString).lastPathComponent == "node"
    }

    nonisolated private static func launchNode(_ node: String, _ directory: String, _ logPath: String,
                                               _ environment: [String: String],
                                               _ onExit: @escaping @MainActor @Sendable (Int32) -> Void) throws -> Int32 {
        let logURL = URL(fileURLWithPath: logPath)
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // A fresh log per start, as the standalone app keeps it: bounded,
        // and the page's tail is this run's.
        guard FileManager.default.createFile(atPath: logPath, contents: nil),
              let log = FileHandle(forWritingAtPath: logPath) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [NexusAgentSupport.botEntryPoint]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { finished in
            let exited = finished.processIdentifier
            try? log.close()
            DispatchQueue.main.async { onExit(exited) }
        }
        do {
            try process.run()
        } catch {
            try? log.close()
            throw error
        }
        return process.processIdentifier
    }

    /// Runs a program on a background queue and returns its standard
    /// output; what it prints to standard error is dropped and its exit
    /// status is not looked at, as the standalone app has it. A bare name
    /// is looked for where that app looks; one found nowhere is still tried
    /// in Homebrew's folder, where it then fails to start and gives nil.
    nonisolated private static func runProgram(named name: String, arguments: [String]) async -> String? {
        let files = FileManager.default
        let path = NexusAgentSupport.executablePath(
            named: name,
            pathVariable: ProcessInfo.processInfo.environment["PATH"] ?? "",
            isExecutable: { files.isExecutableFile(atPath: $0) },
            fileExists: { files.fileExists(atPath: $0) })
            ?? (name.hasPrefix("/") ? name : "/opt/homebrew/bin/" + name)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    /// Output is read on a thread of its own until EOF, and each chunk is
    /// queued to the main thread before the exit is, so the session sees the
    /// whole reply before the turn ends.
    nonisolated private static func launchAgentProcess(_ path: String, _ arguments: [String], _ directory: String,
                                                       _ environment: [String: String],
                                                       _ onOutput: @escaping @MainActor @Sendable (Data) -> Void,
                                                       _ onExit: @escaping @MainActor @Sendable (Int32) -> Void) throws -> NexusAgentRunningAgent {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Only the child keeps the write end, so its exit reaches the reader as EOF.
        try? pipe.fileHandleForWriting.close()
        let reader = pipe.fileHandleForReading
        Thread.detachNewThread {
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                DispatchQueue.main.async { onOutput(chunk) }
            }
            process.waitUntilExit()
            let status = process.terminationStatus
            try? reader.close()
            DispatchQueue.main.async { onExit(status) }
        }
        let pid = process.processIdentifier
        return NexusAgentRunningAgent(terminate: {
            // agy leads a process group of its own; signalling the group
            // also ends the tools it started, which hold the pipe open.
            if getpgid(pid) == pid { _ = kill(-pid, SIGTERM) }
            process.terminate()
        })
    }
}

extension NexusAgentEngine {
    /// Sends the draft as one Quick Prompt turn with the bot's settings.
    public func sendQuickPrompt() {
        session.send(session.draft, configuration: configuration, agentPath: agentPath)
    }

    /// Retries the last failed prompt if any.
    public func retryQuickPrompt() {
        guard let prompt = session.lastFailedPrompt else { return }
        session.send(prompt, configuration: configuration, agentPath: agentPath)
    }

    /// Reads agy or claude conversation index; empty when provider has none.
    nonisolated static func readSessions(home: String, directory: String, provider: NexusAgentCLIProvider = .antigravity,
                                         hiddenClaudeSessionIDs: [String]) -> [NexusAgentSessionSummary] {
        if provider.id == NexusAgentCLIProvider.claude.id {
            return NexusAgentSessionSummary.parseClaudeSessions(home: home, directory: directory,
                                                                appHidden: hiddenClaudeSessionIDs)
        }
        if provider.id == NexusAgentCLIProvider.ollama.id {
            return []
        }
        guard let database = NexusAgentSessionSummary.antigravitySummariesDatabase(home: home) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", database, NexusAgentSessionSummary.query]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let filterDirectory = (directory.isEmpty || directory == home) ? "" : directory
        return NexusAgentSessionSummary.parse(
            data, directory: filterDirectory,
            archivedIds: NexusAgentSessionSummary.antigravityArchivedSessionIds(home: home))
    }

    /// Reads conversation transcript from ~/.gemini/antigravity/brain/<id>/.system_generated/logs/transcript.jsonl
    /// or ~/.claude/projects/*/<id>.jsonl
    public nonisolated static func readTranscript(home: String, conversationID: String, provider: NexusAgentCLIProvider = .antigravity) -> [NexusAgentChatMessage]? {
        let fileManager = FileManager.default
        if provider.id == NexusAgentCLIProvider.claude.id {
            let claudeProjectsDir = (home as NSString).appendingPathComponent(".claude/projects")
            if let subdirs = try? fileManager.contentsOfDirectory(atPath: claudeProjectsDir) {
                for subdir in subdirs {
                    let candidatePath = (claudeProjectsDir as NSString).appendingPathComponent(subdir).appending("/\(conversationID).jsonl")
                    if fileManager.fileExists(atPath: candidatePath),
                       let content = try? String(contentsOfFile: candidatePath, encoding: .utf8) {
                        return parseClaudeTranscript(content)
                    }
                }
            }
            let agyPath = (home as NSString).appendingPathComponent(".gemini/antigravity/brain/\(conversationID)/.system_generated/logs/transcript.jsonl")
            if fileManager.fileExists(atPath: agyPath),
               let content = try? String(contentsOfFile: agyPath, encoding: .utf8) {
                return parseTranscript(content)
            }
            return nil
        }

        let agyPath = (home as NSString).appendingPathComponent(".gemini/antigravity/brain/\(conversationID)/.system_generated/logs/transcript.jsonl")
        if fileManager.fileExists(atPath: agyPath),
           let content = try? String(contentsOfFile: agyPath, encoding: .utf8) {
            return parseTranscript(content)
        }

        let claudeProjectsDir = (home as NSString).appendingPathComponent(".claude/projects")
        if let subdirs = try? fileManager.contentsOfDirectory(atPath: claudeProjectsDir) {
            for subdir in subdirs {
                let candidatePath = (claudeProjectsDir as NSString).appendingPathComponent(subdir).appending("/\(conversationID).jsonl")
                if fileManager.fileExists(atPath: candidatePath),
                   let content = try? String(contentsOfFile: candidatePath, encoding: .utf8) {
                    return parseClaudeTranscript(content)
                }
            }
        }
        return nil
    }

    public nonisolated static func parseClaudeTranscript(_ content: String) -> [NexusAgentChatMessage]? {
        var messages: [NexusAgentChatMessage] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            if type == "user" {
                var userText = ""
                if let message = json["message"] as? [String: Any] {
                    if let strContent = message["content"] as? String {
                        userText = strContent
                    } else if let blocks = message["content"] as? [[String: Any]] {
                        userText = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    }
                } else if let strContent = json["content"] as? String {
                    userText = strContent
                }
                let cleaned = extractUserPrompt(userText)
                if !cleaned.isEmpty {
                    messages.append(NexusAgentChatMessage(role: .user, text: cleaned))
                }
            } else if type == "assistant" {
                var assistantText = ""
                var thinkingParts: [String] = []
                var steps: [NexusAgentToolStep] = []

                let contentBlocks: [[String: Any]]
                if let message = json["message"] as? [String: Any] {
                    if let blocks = message["content"] as? [[String: Any]] {
                        contentBlocks = blocks
                    } else if let strContent = message["content"] as? String {
                        assistantText = strContent
                        contentBlocks = []
                    } else {
                        contentBlocks = []
                    }
                } else if let blocks = json["content"] as? [[String: Any]] {
                    contentBlocks = blocks
                } else if let strContent = json["content"] as? String {
                    assistantText = strContent
                    contentBlocks = []
                } else {
                    contentBlocks = []
                }

                for block in contentBlocks {
                    let blockType = block["type"] as? String ?? ""
                    if blockType == "text", let text = block["text"] as? String {
                        if !assistantText.isEmpty { assistantText += "\n" }
                        assistantText += text
                    } else if blockType == "thinking", let thinking = block["thinking"] as? String {
                        thinkingParts.append(thinking)
                    } else if blockType == "tool_use" {
                        let name = block["name"] as? String ?? "tool"
                        let input = block["input"] as? [String: Any]
                        var summary: String?
                        if name == "Bash" {
                            if let command = input?["command"] as? String {
                                let firstLine = command.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? command
                                summary = String(firstLine.prefix(80))
                            }
                        } else if name == "Task" {
                            summary = input?["description"] as? String ?? input?["prompt"] as? String
                        } else if name == "Read" || name == "Edit" {
                            summary = input?["file_path"] as? String
                        } else {
                            summary = input?["description"] as? String ?? name
                        }
                        steps.append(NexusAgentToolStep(title: summary ?? name, detail: name, isFinished: true))
                    }
                }

                let trimmedText = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
                let thinkingText = thinkingParts.isEmpty ? nil : thinkingParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty || !steps.isEmpty || thinkingText != nil {
                    messages.append(NexusAgentChatMessage(
                        role: .agent,
                        text: trimmedText,
                        toolSteps: steps.isEmpty ? nil : steps,
                        thinkingText: thinkingText
                    ))
                }
            }
        }
        return messages.isEmpty ? nil : messages
    }

    public nonisolated static func parseTranscript(_ content: String) -> [NexusAgentChatMessage]? {
        var messages: [NexusAgentChatMessage] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            if type == "USER_INPUT", let rawContent = json["content"] as? String {
                let cleaned = extractUserPrompt(rawContent)
                if !cleaned.isEmpty {
                    messages.append(NexusAgentChatMessage(role: .user, text: cleaned))
                }
            } else if type == "PLANNER_RESPONSE" {
                let text = (json["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let thinking = json["thinking"] as? String
                var steps: [NexusAgentToolStep] = []
                if let toolCalls = json["tool_calls"] as? [[String: Any]] {
                    for call in toolCalls {
                        if let name = call["name"] as? String {
                            let summary = (call["args"] as? [String: Any])?["toolSummary"] as? String
                            steps.append(NexusAgentToolStep(title: summary ?? name, detail: summary != nil ? name : nil, isFinished: true))
                        }
                    }
                }
                if !text.isEmpty || !steps.isEmpty || thinking != nil {
                    messages.append(NexusAgentChatMessage(role: .agent, text: text, toolSteps: steps.isEmpty ? nil : steps, thinkingText: thinking))
                }
            }
        }
        return messages.isEmpty ? nil : messages
    }

    public nonisolated static func transcriptPath(home: String, conversationID: String, provider: NexusAgentCLIProvider) -> String? {
        let fileManager = FileManager.default
        if provider.id == NexusAgentCLIProvider.claude.id {
            let claudeProjectsDir = (home as NSString).appendingPathComponent(".claude/projects")
            if let subdirs = try? fileManager.contentsOfDirectory(atPath: claudeProjectsDir) {
                for subdir in subdirs {
                    let candidatePath = (claudeProjectsDir as NSString).appendingPathComponent(subdir).appending("/\(conversationID).jsonl")
                    if fileManager.fileExists(atPath: candidatePath) {
                        return candidatePath
                    }
                }
            }
            let agyPath = (home as NSString).appendingPathComponent(".gemini/antigravity/brain/\(conversationID)/.system_generated/logs/transcript.jsonl")
            if fileManager.fileExists(atPath: agyPath) {
                return agyPath
            }
            return nil
        }

        let agyPath = (home as NSString).appendingPathComponent(".gemini/antigravity/brain/\(conversationID)/.system_generated/logs/transcript.jsonl")
        if fileManager.fileExists(atPath: agyPath) {
            return agyPath
        }

        let claudeProjectsDir = (home as NSString).appendingPathComponent(".claude/projects")
        if let subdirs = try? fileManager.contentsOfDirectory(atPath: claudeProjectsDir) {
            for subdir in subdirs {
                let candidatePath = (claudeProjectsDir as NSString).appendingPathComponent(subdir).appending("/\(conversationID).jsonl")
                if fileManager.fileExists(atPath: candidatePath) {
                    return candidatePath
                }
            }
        }
        return nil
    }

    public nonisolated static func parseActiveSubagents(from transcriptContent: String) -> [NexusAgentActiveSubagent] {
        var spawned: [NexusAgentActiveSubagent] = []
        var completedSubagents: Set<String> = []

        for line in transcriptContent.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            var textContent = ""
            if let content = json["content"] as? String {
                textContent = content
            } else if let message = json["message"] as? [String: Any] {
                if let content = message["content"] as? String {
                    textContent = content
                } else if let blocks = message["content"] as? [[String: Any]] {
                    textContent = blocks.compactMap { $0["text"] as? String ?? $0["content"] as? String }.joined(separator: " ")
                }
            }

            if !textContent.isEmpty {
                if textContent.contains("sender=") || textContent.contains("Message sent to") || textContent.contains("Completed At:") || textContent.contains("Completed") {
                    for s in spawned {
                        if textContent.contains("sender=\(s.typeName)") || textContent.contains("sender=\(s.id)") || textContent.contains(s.id) || (textContent.contains(s.role) && textContent.contains("Completed")) {
                            completedSubagents.insert(s.id)
                        }
                    }
                }
            }

            if let type = json["type"] as? String, type == "SYSTEM_MESSAGE" || type == "USER_INPUT" {
                if let content = json["content"] as? String {
                    for s in spawned {
                        if content.contains("sender=\(s.typeName)") || content.contains("sender=\(s.id)") {
                            completedSubagents.insert(s.id)
                        }
                    }
                }
            }

            // Claude tool_result completion checking
            if let directToolUseID = json["tool_use_id"] as? String {
                completedSubagents.insert(directToolUseID)
            }
            let checkBlocks: [[String: Any]]
            if let message = json["message"] as? [String: Any], let blocks = message["content"] as? [[String: Any]] {
                checkBlocks = blocks
            } else if let blocks = json["content"] as? [[String: Any]] {
                checkBlocks = blocks
            } else {
                checkBlocks = []
            }
            for block in checkBlocks {
                if (block["type"] as? String) == "tool_result" {
                    if let toolUseID = block["tool_use_id"] as? String {
                        completedSubagents.insert(toolUseID)
                    }
                }
            }

            // Antigravity invoke_subagent tool calls
            if let toolCalls = json["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    guard let name = call["name"] as? String, name == "invoke_subagent",
                          let args = call["args"] as? [String: Any] else { continue }

                    var subagentsRaw: [[String: Any]] = []
                    if let rawArray = args["Subagents"] as? [[String: Any]] {
                        subagentsRaw = rawArray
                    } else if let rawString = args["Subagents"] as? String,
                              let subData = rawString.data(using: .utf8),
                              let decoded = try? JSONSerialization.jsonObject(with: subData) as? [[String: Any]] {
                        subagentsRaw = decoded
                    }

                    for sub in subagentsRaw {
                        let typeName = sub["TypeName"] as? String ?? "subagent"
                        let role = sub["Role"] as? String ?? typeName
                        let prompt = sub["Prompt"] as? String ?? ""
                        let model = sub["Model"] as? String ?? "inherit"
                        let id = "\(typeName)-\(role)-\(spawned.count)"
                        let active = NexusAgentActiveSubagent(id: id, typeName: typeName, role: role, prompt: prompt, model: model, isRunning: true)
                        spawned.append(active)
                    }
                }
            }

            // Claude Code Task tool calls in assistant turns
            let lineType = json["type"] as? String
            if lineType == "assistant" {
                let assistantBlocks: [[String: Any]]
                if let message = json["message"] as? [String: Any], let blocks = message["content"] as? [[String: Any]] {
                    assistantBlocks = blocks
                } else if let blocks = json["content"] as? [[String: Any]] {
                    assistantBlocks = blocks
                } else {
                    assistantBlocks = []
                }
                for block in assistantBlocks {
                    if (block["type"] as? String) == "tool_use", (block["name"] as? String) == "Task" {
                        let toolId = block["id"] as? String ?? UUID().uuidString
                        let input = block["input"] as? [String: Any]
                        let subagentType = input?["subagent_type"] as? String ?? "subagent"
                        let description = input?["description"] as? String ?? subagentType
                        let prompt = input?["prompt"] as? String ?? ""
                        let active = NexusAgentActiveSubagent(id: toolId, typeName: subagentType, role: description, prompt: prompt, model: "claude", isRunning: true)
                        spawned.append(active)
                    }
                }
            }
        }

        return spawned.filter { !completedSubagents.contains($0.id) }
    }

    public nonisolated static func extractUserPrompt(_ raw: String) -> String {
        NexusAgentSessionSummary.extractUserPrompt(raw)
    }

    // MARK: - Session Archiving

    public func archiveSession(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration) {
        Self.archiveSession(home: environment.home, id: summary.id, provider: configuration.activeProvider, host: host)
    }

    public func unarchiveSession(_ summary: NexusAgentSessionSummary, configuration: NexusAgentConfiguration) {
        Self.unarchiveSession(home: environment.home, id: summary.id, provider: configuration.activeProvider, host: host)
    }

    /// Archives with the host's list of hidden Claude sessions. Static, so a
    /// session built without an engine does the same work.
    public static func archiveSession(home: String, id: String, provider: NexusAgentCLIProvider,
                                       host: any NexusAgentHost) {
        archiveSession(home: home, id: id, provider: provider,
                       hiddenClaudeSessionIDs: { host.hiddenClaudeSessionIDs },
                       saveHiddenClaudeSessionIDs: { host.hiddenClaudeSessionIDs = $0 })
    }

    public static func unarchiveSession(home: String, id: String, provider: NexusAgentCLIProvider,
                                         host: any NexusAgentHost) {
        unarchiveSession(home: home, id: id, provider: provider,
                         hiddenClaudeSessionIDs: { host.hiddenClaudeSessionIDs },
                         saveHiddenClaudeSessionIDs: { host.hiddenClaudeSessionIDs = $0 })
    }

    /// The list of hidden Claude sessions is the app's to keep, so it is
    /// read and saved through the two closures, and only for Claude.
    nonisolated public static func archiveSession(home: String, id: String, provider: NexusAgentCLIProvider,
                                                   hiddenClaudeSessionIDs: () -> [String],
                                                   saveHiddenClaudeSessionIDs: ([String]) -> Void) {
        if provider.id == NexusAgentCLIProvider.antigravity.id {
            setAntigravityArchived(home: home, id: id, archived: true)
        } else if provider.id == NexusAgentCLIProvider.claude.id {
            var hidden = hiddenClaudeSessionIDs()
            if !hidden.contains(id) {
                hidden.append(id)
                saveHiddenClaudeSessionIDs(hidden)
            }
            updateClaudeVSCodeHiddenState(home: home, id: id, isArchived: true)
        }
    }

    nonisolated public static func unarchiveSession(home: String, id: String, provider: NexusAgentCLIProvider,
                                                     hiddenClaudeSessionIDs: () -> [String],
                                                     saveHiddenClaudeSessionIDs: ([String]) -> Void) {
        if provider.id == NexusAgentCLIProvider.antigravity.id {
            setAntigravityArchived(home: home, id: id, archived: false)
        } else if provider.id == NexusAgentCLIProvider.claude.id {
            var hidden = hiddenClaudeSessionIDs()
            if hidden.contains(id) {
                hidden.removeAll { $0 == id }
                saveHiddenClaudeSessionIDs(hidden)
            }
            updateClaudeVSCodeHiddenState(home: home, id: id, isArchived: false)
        }
    }

    /// Records the archive state where agy itself reads it: the annotation
    /// beside the conversation, `annotations/<id>.pbtxt`. The index's `killed`
    /// column means an aborted run, so it is left alone.
    nonisolated private static func setAntigravityArchived(home: String, id: String, archived: Bool,
                                                          now: Date = Date()) {
        guard !id.isEmpty, id == (id as NSString).lastPathComponent, id != ".", id != ".." else { return }
        let files = FileManager.default
        let roots = NexusAgentSessionSummary.antigravityDataDirectories
            .map { (home as NSString).appendingPathComponent($0) }
        let annotation = { (root: String) in root + "/annotations/\(id).pbtxt" }
        let existing = roots.filter { files.fileExists(atPath: annotation($0)) }
        // Unarchiving clears every copy, since any one of them archives the session.
        let targets = archived
            ? [roots.first { files.fileExists(atPath: $0 + "/conversations/\(id).db") } ?? existing.first ?? roots[0]]
            : existing
        for root in targets {
            let path = annotation(root)
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            try? files.createDirectory(atPath: root + "/annotations", withIntermediateDirectories: true)
            try? NexusAgentSessionSummary.antigravityAnnotation(text, archived: archived, now: now)
                .write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    nonisolated private static func runSqlite(database: String, sql: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database, sql]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    nonisolated private static func updateClaudeVSCodeHiddenState(home: String, id: String, isArchived: Bool) {
        let appSupport = (home as NSString).appendingPathComponent("Library/Application Support")
        let dbPaths = [
            (appSupport as NSString).appendingPathComponent("Code/User/globalStorage/state.vscdb"),
            (appSupport as NSString).appendingPathComponent("Code - Insiders/User/globalStorage/state.vscdb"),
        ]
        for dbPath in dbPaths where FileManager.default.fileExists(atPath: dbPath) {
            let queryProcess = Process()
            queryProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            queryProcess.arguments = [
                "-json",
                dbPath,
                "SELECT value FROM ItemTable WHERE key = 'Anthropic.claude-code';"
            ]
            let pipe = Pipe()
            queryProcess.standardOutput = pipe
            queryProcess.standardError = FileHandle.nullDevice
            guard (try? queryProcess.run()) != nil else { continue }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            queryProcess.waitUntilExit()
            guard queryProcess.terminationStatus == 0,
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = rows.first,
                  let valueStr = first["value"] as? String,
                  let valueData = valueStr.data(using: .utf8),
                  var stateObj = try? JSONSerialization.jsonObject(with: valueData) as? [String: Any] else { continue }

            var hiddenList = stateObj["hiddenSessionIds"] as? [String] ?? []
            if isArchived {
                if !hiddenList.contains(id) { hiddenList.append(id) }
            } else {
                hiddenList.removeAll { $0 == id }
            }
            stateObj["hiddenSessionIds"] = hiddenList

            guard let updatedData = try? JSONSerialization.data(withJSONObject: stateObj),
                  let updatedStr = String(data: updatedData, encoding: .utf8) else { continue }

            let safeValue = updatedStr.replacingOccurrences(of: "'", with: "''")
            let updateSql = "UPDATE ItemTable SET value = '\(safeValue)' WHERE key = 'Anthropic.claude-code';"
            runSqlite(database: dbPath, sql: updateSql)
        }
    }
}
