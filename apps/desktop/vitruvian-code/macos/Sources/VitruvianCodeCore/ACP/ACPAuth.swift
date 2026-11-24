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
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).


import Darwin
import Foundation

// Signing in to an agent from the app (design: docs/designs/vitruvian-code-acp.md, step 5).
//
// When a live connection says the agent needs sign-in, the failure card lists the agent's own
// sign-in methods, from `initialize`'s `authMethods`:
//
// * an **agent** method (no `type`, or `agent`): the next connection sends ACP `authenticate`
//   with its ID right after `initialize`, then opens the session and retries the turn;
// * a **terminal** method: the app runs the agent's own program with the method's `args` added,
//   as separate arguments (never a shell line), in a pseudo-terminal as T3 Code does, and shows
//   what it prints in a sheet. Exit
//   status 0 is success: the app reconnects and retries the turn. Anything else, or Cancel, is
//   a failure and nothing is retried (ACP: protocol/authentication).
//
// Claude on the Agent SDK advertises no methods (the helper's `authMethods` is empty). For it
// the card offers `claude auth login`, the command T3 Code gives for Claude
// (`apps/web/src/onboarding/providerReadiness.logic.ts`, `resolveOnboardingProviderLoginCommand`),
// run with the chat's `CLAUDE_CONFIG_DIR` as T3 Code's docs say (`docs/user/providers-claude.md`).
//
// Credentials stay with the agent: the app never reads, keeps or shows a token. The sign-in
// program gets only a short list of the app's own variables (home, user, PATH, locale, proxy
// and certificate settings) plus
// what the method names, so no stored API key or token reaches it, and nothing it prints is
// logged. The app never types into its prompts: the user does any browser step, and the
// sheet's reply field sends only what the user types.

/// What a terminal sign-in runs: a program and its arguments, each its own string. No shell
/// reads them.
public struct AgentSignInCommand: Equatable, Sendable, Codable {
    public var executable: String
    public var arguments: [String]
    /// The whole environment the program gets: the app's short list, `TERM`, and the method's own.
    public var environment: [String: String]
    public var workingDirectory: String?
    /// The variables the method set, by name, so the sheet can show them before it runs.
    public var methodVariableNames: [String]
    /// Variables the method asked for that change how programs are found or loaded
    /// (`PATH`, `DYLD_*`, `LD_*`, `NODE_OPTIONS`); the app leaves them out.
    public var refusedVariableNames: [String]

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String? = nil,
        methodVariableNames: [String] = [],
        refusedVariableNames: [String] = []
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.methodVariableNames = methodVariableNames
        self.refusedVariableNames = refusedVariableNames
    }

    /// The command as the sheet shows it. Display only: it is never run through a shell.
    public var displayLine: String {
        ([executable] + arguments).map(Self.quotedForDisplay).joined(separator: " ")
    }

    private static func quotedForDisplay(_ word: String) -> String {
        let plain = word.allSatisfy { $0.isLetter || $0.isNumber || "-_./:=@+,".contains($0) }
        if plain && !word.isEmpty { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// One way to sign in that the failure card offers.
public struct AgentSignInMethod: Equatable, Sendable, Codable, Identifiable {
    public enum Kind: Equatable, Sendable, Codable {
        /// The agent signs in itself when sent ACP `authenticate` with this method's ID.
        case agent
        /// The app runs this command and waits for it to end.
        case terminal(AgentSignInCommand)
    }

    public var id: String
    public var name: String
    public var description: String?
    public var kind: Kind

    public init(id: String, name: String, description: String? = nil, kind: Kind) {
        self.id = id
        self.name = name
        self.description = description
        self.kind = kind
    }

    public var command: AgentSignInCommand? {
        if case .terminal(let command) = kind { return command }
        return nil
    }
}

public enum ACPAuth {
    /// T3 Code keeps at most 32 methods, each with an ID of at most 128 characters
    /// (`packages/provider-acp-registry/src/server/auth.ts`).
    public static let maxMethods = 32
    public static let maxMethodIDLength = 128
    /// How much of the sign-in program's output the sheet keeps (T3 Code keeps 16 KB).
    public static let outputLimit = 16_384
    /// The ID the card uses for Claude's `claude auth login`.
    public static let claudeLoginMethodID = "claude-auth-login"

    /// The app's own variables a sign-in program gets. Nothing else is passed on: no API key,
    /// token or other secret the app or the agent was started with.
    public static let inheritedVariables: Set<String> = [
        "HOME", "USER", "LOGNAME", "SHELL", "PATH", "TMPDIR",
        "LANG", "LC_ALL", "LC_CTYPE", "LC_MESSAGES", "__CF_USER_TEXT_ENCODING",
        // What a sign-in needs to reach the network from behind a proxy or a company CA.
        "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "ALL_PROXY",
        "http_proxy", "https_proxy", "no_proxy", "all_proxy",
        "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS",
    ]

    /// The terminal type the sign-in program sees, as node-pty's `name` gives T3 Code's
    /// (`apps/server/src/terminal/NodePtyAdapter.ts`).
    public static let terminalType = "xterm-256color"

    /// A method may not set these: they change which programs run or what they load, and ACP
    /// says not to apply them without the user's approval.
    public static func isRefusedMethodVariable(_ name: String) -> Bool {
        let upper = name.uppercased()
        return upper == "PATH" || upper.hasPrefix("DYLD_") || upper.hasPrefix("LD_")
            || upper == "NODE_OPTIONS" || upper == "NODE_PATH"
    }

    /// The methods the card offers for what the agent advertised. Agent methods always; terminal
    /// methods only when the app told the agent it can run them; `env_var` and unknown types
    /// never (those belong in the provider's environment settings, as in T3 Code).
    public static func signInMethods(
        advertised: [ACPAuthMethod],
        launchSpec: AgentProcessLaunchSpec,
        terminalAdvertised: Bool
    ) -> [AgentSignInMethod] {
        var result: [AgentSignInMethod] = []
        var seen = Set<String>()
        for method in advertised {
            let id = method.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, id.count <= maxMethodIDLength, seen.insert(id).inserted else { continue }
            let name = method.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let shownName = name.isEmpty ? id : name
            switch method.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case nil, "", "agent":
                result.append(AgentSignInMethod(id: id, name: shownName, description: method.description, kind: .agent))
            case "terminal" where terminalAdvertised:
                let command = terminalCommand(
                    launchSpec: launchSpec,
                    methodArguments: method.args ?? [],
                    methodEnvironment: method.env ?? [:]
                )
                result.append(AgentSignInMethod(id: id, name: shownName, description: method.description, kind: .terminal(command)))
            default:
                continue
            }
            if result.count == maxMethods { break }
        }
        return result
    }

    /// A terminal method's command: the agent's own program and launch arguments with the
    /// method's arguments added after them (ACP: "the descriptor cannot provide a command").
    public static func terminalCommand(
        launchSpec: AgentProcessLaunchSpec,
        methodArguments: [String],
        methodEnvironment: [String: String]
    ) -> AgentSignInCommand {
        let (environment, refused) = signInEnvironment(base: launchSpec.environment, method: methodEnvironment)
        return AgentSignInCommand(
            executable: launchSpec.executable,
            arguments: launchSpec.arguments + methodArguments,
            environment: environment,
            workingDirectory: launchSpec.workingDirectory,
            methodVariableNames: methodEnvironment.keys.filter { !isRefusedMethodVariable($0) }.sorted(),
            refusedVariableNames: refused
        )
    }

    /// The sign-in program's whole environment: `inheritedVariables` from `base`, then the
    /// method's variables on top, less the refused ones.
    public static func signInEnvironment(
        base: [String: String],
        method: [String: String]
    ) -> (environment: [String: String], refused: [String]) {
        var environment: [String: String] = [:]
        for (key, value) in base where inheritedVariables.contains(key) {
            environment[key] = value
        }
        environment["TERM"] = terminalType
        var refused: [String] = []
        for (key, value) in method {
            if isRefusedMethodVariable(key) {
                refused.append(key)
            } else {
                environment[key] = value
            }
        }
        return (environment, refused.sorted())
    }

    /// Claude on the Agent SDK: `claude auth login`, with the chat's `CLAUDE_CONFIG_DIR` when
    /// one is set, so the login lands where the helper's `claude` reads it.
    public static func claudeSignInMethods(
        claudePath: String?,
        helperEnvironment: [String: String],
        workingDirectory: String?
    ) -> [AgentSignInMethod] {
        guard let claudePath = claudePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !claudePath.isEmpty else { return [] }
        var methodEnvironment: [String: String] = [:]
        if let folder = helperEnvironment[ClaudeSDKSupport.configDirectoryKey], !folder.isEmpty {
            methodEnvironment[ClaudeSDKSupport.configDirectoryKey] = folder
        }
        let (environment, _) = signInEnvironment(base: helperEnvironment, method: methodEnvironment)
        let command = AgentSignInCommand(
            executable: claudePath,
            arguments: ["auth", "login"],
            environment: environment,
            workingDirectory: workingDirectory,
            methodVariableNames: methodEnvironment.keys.sorted()
        )
        return [AgentSignInMethod(id: claudeLoginMethodID, name: "Claude Code", kind: .terminal(command))]
    }

    /// Terminal colour and cursor codes taken out, so the sheet shows plain text.
    public static func plainOutput(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil
        func next() -> Unicode.Scalar? {
            if let scalar = pending { pending = nil; return scalar }
            return iterator.next()
        }
        while let scalar = next() {
            if scalar == "\u{1B}" {
                guard let kind = next() else { break }
                if kind == "[" {
                    // CSI: parameters, then one final byte in @...~.
                    while let byte = next(), !(0x40...0x7E).contains(byte.value) {}
                } else if kind == "]" {
                    // OSC: up to BEL or ESC \.
                    while let byte = next() {
                        if byte == "\u{07}" { break }
                        if byte == "\u{1B}" { _ = next(); break }
                    }
                }
                continue
            }
            if scalar == "\r" {
                if let following = next(), following != "\n" { pending = following }
                result.unicodeScalars.append("\n")
                continue
            }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    /// Runs a sign-in command in a pseudo-terminal, in its own session and process group.
    public static let liveLauncher: ACPSignInLauncher = { spec in
        try ACPPtySignInProcess(spec)
    }
}

// MARK: - Running a terminal sign-in

/// A running sign-in program, as `ACPSignInRun` sees it. Tests pass fakes.
public protocol ACPSignInProcess: AnyObject, Sendable {
    /// What it prints on standard output and standard error, together, as it comes.
    var output: AsyncStream<Data> { get }
    /// Writes to its standard input: only text the user typed in the sheet.
    func sendInput(_ data: Data)
    func waitForExit() async -> AgentProcessExit
    /// Ends its whole process group: `SIGTERM`, then `SIGKILL` to anything left.
    func terminate() async
}

public typealias ACPSignInLauncher = @Sendable (AgentProcessLaunchSpec) throws -> any ACPSignInProcess

/// Why a pseudo-terminal sign-in program could not start.
public enum ACPSignInProcessError: Error, Equatable, Sendable, LocalizedError {
    case terminalUnavailable(Int32)
    case spawnFailed(executable: String, errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .terminalUnavailable(let code):
            return "Could not open a terminal for sign-in (\(String(cString: strerror(code))))."
        case .spawnFailed(let executable, let code):
            return "Failed to launch \(executable): \(String(cString: strerror(code)))."
        }
    }
}

/// A sign-in program in a pseudo-terminal, as T3 Code runs one (`node-pty` behind
/// `packages/shared/src/PtyAdapter.ts`, `apps/server/src/terminal/NodePtyAdapter.ts`, spawned
/// 80 by 24 from `packages/provider-acp-registry/src/server/auth.ts`). Sign-in tools check
/// `isatty`, print prompts with no newline and read single keys, so pipes are not enough.
///
/// The program is started with `posix_spawn` and its argv as given: no shell. It gets a new
/// session (`POSIX_SPAWN_SETSID`), so it leads its own process group, and opens the terminal's
/// far end as standard input, which makes it its controlling terminal; standard output and
/// standard error are that same terminal. `terminate()` ends the whole group.
public final class ACPPtySignInProcess: ACPSignInProcess, @unchecked Sendable {
    public static let columns: UInt16 = 80
    public static let rows: UInt16 = 24

    public let pid: pid_t
    public var processGroupID: pid_t { pid }
    public let output: AsyncStream<Data>

    private let masterFD: Int32
    private let lock = NSLock()
    private var exit: AgentProcessExit?
    private var exitWaiters: [CheckedContinuation<AgentProcessExit, Never>] = []
    private var masterClosed = false

    public init(_ spec: AgentProcessLaunchSpec) throws {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { throw ACPSignInProcessError.terminalUnavailable(errno) }
        guard grantpt(master) == 0, unlockpt(master) == 0, let namePointer = ptsname(master) else {
            let code = errno
            Darwin.close(master)
            throw ACPSignInProcessError.terminalUnavailable(code)
        }
        let slavePath = String(cString: namePointer)
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        var size = winsize(ws_row: Self.rows, ws_col: Self.columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &size)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        // Opened by the new session's leader, without O_NOCTTY: the terminal becomes its
        // controlling terminal, so `/dev/tty` works too.
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, slavePath, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDERR_FILENO)
        if let directory = spec.workingDirectory, !directory.isEmpty {
            posix_spawn_file_actions_addchdir_np(&actions, directory)
        }

        var argv: [UnsafeMutablePointer<CChar>?] = ([spec.executable] + spec.arguments).map { strdup($0) }
        argv.append(nil)
        defer { for pointer in argv { free(pointer) } }
        var envp: [UnsafeMutablePointer<CChar>?] = spec.environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer { for pointer in envp { free(pointer) } }

        var child: pid_t = 0
        let rc = spec.executable.contains("/")
            ? posix_spawn(&child, spec.executable, &actions, &attr, &argv, &envp)
            : posix_spawnp(&child, spec.executable, &actions, &attr, &argv, &envp)
        guard rc == 0 else {
            Darwin.close(master)
            throw ACPSignInProcessError.spawnFailed(executable: spec.executable, errno: rc)
        }
        self.pid = child
        self.masterFD = master

        self.output = AsyncStream { continuation in
            Thread.detachNewThread {
                var buffer = [UInt8](repeating: 0, count: 16_384)
                while true {
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(master, $0.baseAddress, $0.count) }
                    if count > 0 {
                        continuation.yield(Data(buffer[0..<count]))
                    } else if count < 0 && errno == EINTR {
                        continue
                    } else {
                        // EIO once every holder of the far end has closed it.
                        break
                    }
                }
                continuation.finish()
            }
        }

        Thread.detachNewThread { [self] in
            var status: Int32 = 0
            while Darwin.waitpid(child, &status, 0) < 0 && errno == EINTR {}
            let low = status & 0x7f
            let ended = low == 0
                ? AgentProcessExit(exitCode: (status >> 8) & 0xff)
                : AgentProcessExit(exitCode: nil, signal: low)
            let waiters: [CheckedContinuation<AgentProcessExit, Never>] = lock.withLock {
                exit = ended
                defer { exitWaiters.removeAll() }
                return exitWaiters
            }
            for waiter in waiters { waiter.resume(returning: ended) }
        }
    }

    deinit {
        closeMaster()
    }

    public func sendInput(_ data: Data) {
        let closed = lock.withLock { masterClosed }
        guard !closed else { return }
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(masterFD, raw.baseAddress! + offset, raw.count - offset)
                if written > 0 { offset += written } else if errno != EINTR { break }
            }
        }
    }

    public func waitForExit() async -> AgentProcessExit {
        await withCheckedContinuation { waiter in
            let ended: AgentProcessExit? = lock.withLock {
                if let exit { return exit }
                exitWaiters.append(waiter)
                return nil
            }
            if let ended { waiter.resume(returning: ended) }
        }
    }

    /// `SIGHUP` and `SIGTERM` to the whole group, then `SIGKILL` to anything left after a second.
    /// The terminal stays open until this object goes, so output already written is still read;
    /// the reader ends once nothing holds the far end.
    public func terminate() async {
        let group = pid
        _ = Darwin.kill(-group, SIGHUP)
        _ = Darwin.kill(-group, SIGTERM)
        let deadline = ProcessInfo.processInfo.systemUptime + AgentProcess.defaultTerminationGrace
        while AgentProcess.processGroupExists(group) && ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        if AgentProcess.processGroupExists(group) {
            _ = Darwin.kill(-group, SIGKILL)
            let killDeadline = ProcessInfo.processInfo.systemUptime + 0.5
            while AgentProcess.processGroupExists(group) && ProcessInfo.processInfo.systemUptime < killDeadline {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    private func closeMaster() {
        let shouldClose = lock.withLock { () -> Bool in
            if masterClosed { return false }
            masterClosed = true
            return true
        }
        if shouldClose { Darwin.close(masterFD) }
    }
}

/// One terminal sign-in, from the sheet's Run button to its end.
@MainActor
public final class ACPSignInRun: ObservableObject, Identifiable {
    public enum State: Equatable, Sendable {
        /// Shown, not yet started: the sheet shows the command first.
        case ready
        case running
        /// Exit status 0.
        case succeeded
        /// Any other end: the status as a shell reports it (128 + signal for a signal).
        case failed(exitStatus: Int32)
        case couldNotStart
        case cancelled

        public var isFinished: Bool {
            switch self {
            case .ready, .running: return false
            case .succeeded, .failed, .couldNotStart, .cancelled: return true
            }
        }
    }

    public let id = UUID()
    public let method: AgentSignInMethod
    public let command: AgentSignInCommand
    @Published public private(set) var state: State = .ready
    @Published public private(set) var output = ""
    /// Called once, when the run ends in any way.
    public var onFinished: (@MainActor (State) -> Void)?

    private let launcher: ACPSignInLauncher
    private let log: @MainActor (String) -> Void
    private var process: (any ACPSignInProcess)?
    private var outputBytes = Data()
    private var waiters: [CheckedContinuation<State, Never>] = []

    /// Nil for a method the app does not run itself.
    public init?(
        method: AgentSignInMethod,
        launcher: @escaping ACPSignInLauncher = ACPAuth.liveLauncher,
        log: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        guard let command = method.command else { return nil }
        self.method = method
        self.command = command
        self.launcher = launcher
        self.log = log
    }

    /// Starts the program. Does nothing unless the run is `.ready`.
    public func start() {
        guard state == .ready else { return }
        let spec = AgentProcessLaunchSpec(
            executable: command.executable,
            arguments: command.arguments,
            environment: command.environment,
            workingDirectory: command.workingDirectory
        )
        let launched: any ACPSignInProcess
        do {
            launched = try launcher(spec)
        } catch {
            log("Sign-in program could not start: \((command.executable as NSString).lastPathComponent).")
            finish(.couldNotStart)
            return
        }
        process = launched
        state = .running
        // Names and counts only: never an argument, a variable's value or anything it prints.
        log("Sign-in started: \((command.executable as NSString).lastPathComponent), \(command.arguments.count) arguments, variables \(command.environment.keys.sorted().joined(separator: ",")).")
        let stream = launched.output
        Task { @MainActor [weak self] in
            let reader = Task { @MainActor [weak self] in
                for await chunk in stream {
                    self?.append(chunk)
                }
            }
            let exit = await launched.waitForExit()
            // Anything the program left running in its group is ended too, which also closes
            // the pipes so the reader finishes.
            await launched.terminate()
            await reader.value
            self?.processEnded(exit)
        }
    }

    /// Ends the program's whole process group. Nothing is retried after a cancel.
    public func cancel() async {
        guard !state.isFinished else { return }
        let running = process
        finish(.cancelled)
        if let running {
            await running.terminate()
        }
    }

    /// Sends one line the user typed to the program. Never logged.
    public func send(_ text: String) {
        guard state == .running, let process else { return }
        process.sendInput(Data((text + "\n").utf8))
    }

    /// Waits for the run to end and returns how it ended.
    public func waitUntilFinished() async -> State {
        if state.isFinished { return state }
        return await withCheckedContinuation { waiters.append($0) }
    }

    private func append(_ chunk: Data) {
        outputBytes.append(chunk)
        if outputBytes.count > ACPAuth.outputLimit {
            outputBytes = Data(outputBytes.suffix(ACPAuth.outputLimit))
        }
        output = ACPAuth.plainOutput(String(decoding: outputBytes, as: UTF8.self))
    }

    private func processEnded(_ exit: AgentProcessExit) {
        guard !state.isFinished else { return }
        if exit.exitCode == 0 && exit.signal == nil {
            log("Sign-in program ended with status 0.")
            finish(.succeeded)
        } else {
            log("Sign-in program ended with status \(exit.terminationStatus).")
            finish(.failed(exitStatus: exit.terminationStatus))
        }
    }

    private func finish(_ final: State) {
        guard !state.isFinished else { return }
        state = final
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume(returning: final) }
        let callback = onFinished
        onFinished = nil
        callback?(final)
    }
}
