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
import Foundation

/// HomeSpeaker's command line, on any engine: `--say`, the volume flags,
/// `--sign-in`, the app-identity commands, `--chat-monitor`, the Claude Code
/// Stop hook and its detached `--announce`, `--help` and `--version`.
///
/// The app's program runs it on `HomeSpeakerEngine.app`, so what it prints
/// and how it exits is exactly what it always was. Each flag's work is an
/// `async` function that returns a `CLIOutput`, so tests drive it with
/// stand-ins; `run` only reads the arguments, wires the engine's real parts
/// and prints.
public enum HomeSpeakerCommandLine {
    /// One run of the command line, parsed. Anything else is not the
    /// command line's: the app's program starts the menu bar app.
    public enum Command: Equatable, Sendable {
        /// `--announce <text> [--source <agent>]`: an end-of-turn hook's
        /// detached announcement, for the agent it ran for.
        case announce(String, CodingAgent)
        /// `--claude-stop-hook`, `--antigravity-hook` or `--opencode-hook`,
        /// with the hook's JSON on standard input.
        case stopHook(CodingAgent)
        /// `--sign-out`, `--discover`, `--login-item`, `--test-media-pause`.
        case app(Result<AppCommand, UsageError>)
        /// `--chat-monitor start|stop`.
        case chatMonitor(Result<ChatMonitorAction, UsageError>)
        /// `--say <text>`.
        case say(String)
        /// `--volume`, `--set-volume N`, `--mute`, `--unmute`.
        case volume(VolumeRequest)
        /// `--sign-in [--chat]`.
        case signIn(GoogleAuth.Purpose)
        /// `--help` or `-h`.
        case help
        /// `--version`.
        case version
        /// `--where`: the profile's data folder. Hidden from `--help`; the
        /// conformance test asks it which folder a program uses.
        case location
    }

    /// What a volume flag asks for.
    public enum VolumeRequest: Equatable, Sendable {
        case read
        case set(Int)
        /// `--set-volume` without a whole number from 0 to 100.
        case invalidLevel
        case mute
        case unmute
    }

    public static let whereFlag = "--where"
    static let volumeFlags = ["--volume", "--set-volume", "--mute", "--unmute"]

    /// The command in `arguments` (the program's, without its own path), in
    /// the order the app's program has always tried them; nil when there is
    /// none.
    public static func parse(_ arguments: [String]) -> Command? {
        // The Stop hook's detached announcement: exactly `--announce <text>`,
        // so a reply that happens to contain a flag name is never mistaken
        // for one.
        if arguments.first == ClaudeStopHook.announceArgument {
            if arguments.count == 2 { return .announce(arguments[1], .claudeCode) }
            if arguments.count == 4, arguments[2] == BroadcastSource.flag,
               let agent = BroadcastSource(name: arguments[3])?.agent {
                return .announce(arguments[1], agent)
            }
        }
        if let agent = CodingAgent.allCases.first(where: { arguments.contains($0.hookArgument) }) { return .stopHook(agent) }
        if let parsed = AppCommandParser.parse(arguments) { return .app(parsed) }
        if let parsed = ChatMonitorControlNotice.parse(arguments) { return .chatMonitor(parsed) }
        if let i = arguments.firstIndex(of: "--say") {
            return .say(arguments[arguments.index(after: i)...].joined(separator: " "))
        }
        if let flag = volumeFlags.first(where: { arguments.contains($0) }) {
            switch flag {
            case "--set-volume":
                guard let i = arguments.firstIndex(of: "--set-volume"), arguments.index(after: i) < arguments.endIndex,
                      let n = Int(arguments[arguments.index(after: i)]), (0...100).contains(n) else {
                    return .volume(.invalidLevel)
                }
                return .volume(.set(n))
            case "--mute": return .volume(.mute)
            case "--unmute": return .volume(.unmute)
            default: return .volume(.read)
            }
        }
        if arguments.contains("--sign-in") { return .signIn(arguments.contains("--chat") ? .chat : .home) }
        if arguments.contains("--help") || arguments.contains("-h") { return .help }
        if arguments.contains("--version") { return .version }
        if arguments.first == whereFlag { return .location }
        return nil
    }

    /// True when `arguments` are the command line's to run; false when the
    /// program should start its long-lived self instead.
    public static func recognizes(_ arguments: [String]) -> Bool {
        parse(arguments) != nil
    }

    // MARK: - What the real run injects

    /// The parts of a run that differ between the app and the extension.
    public struct Parts {
        /// The app's own login item, or why there is none.
        public enum LoginItem {
            case control(LoginItemControlling)
            case none(reason: String)
        }

        /// Opens the Google sign-in page.
        public var openBrowser: @Sendable (URL) -> Void
        public var loginItem: LoginItem
        /// True when the other HomeSpeaker is the one chosen, and installed:
        /// the Stop hook and its `--announce` then do nothing, so a stale
        /// hook entry never says a reply twice. `--say` still speaks.
        public var standsAside: @Sendable () -> Bool
        /// What `--say` notes while this side stands aside; nil for the
        /// usual "the other one is in use".
        public var asideNote: @Sendable () -> String?
        /// The other HomeSpeaker's sign-ins, while it is installed:
        /// `--sign-out` never revokes a login it shares
        /// (`HomeSpeakerEngine.signOut`). Nil when there is no other.
        public var otherSecrets: @Sendable () -> Secrets?
        /// Tells a running HomeSpeaker its login was removed.
        public var postSignedOut: @Sendable (_ chatOnly: Bool, Notification.Name) -> Void
        /// The settings of the HomeSpeaker in use when that is the other
        /// one; nil when it is this one, or they do not read. `--say` and
        /// `--announce` read their time limit, switches and outputs from
        /// these: `speaker-broadcast` always runs the app's program, while
        /// the settings the person turns are the side in use's.
        public var inUseSettings: @Sendable () -> SpeakerConfig?
        /// The engine of the HomeSpeaker in use when that is the other one
        /// (its `Announcer`, `SecretStore` and `BroadcastHistory`); nil when
        /// it is this one. `--say` speaks through and records into this
        /// engine so the active door's Gemini API key, Google Home login and
        /// history file are used.
        public var inUseEngine: @MainActor @Sendable () -> HomeSpeakerEngine?

        public init(
            openBrowser: @escaping @Sendable (URL) -> Void,
            loginItem: LoginItem,
            standsAside: @escaping @Sendable () -> Bool,
            asideNote: @escaping @Sendable () -> String? = { nil },
            otherSecrets: @escaping @Sendable () -> Secrets? = { nil },
            postSignedOut: @escaping @Sendable (_ chatOnly: Bool, Notification.Name) -> Void = {
                SignOutNotice.post(chatOnly: $0, name: $1)
            },
            inUseSettings: @escaping @Sendable () -> SpeakerConfig? = { nil },
            inUseEngine: @escaping @MainActor @Sendable () -> HomeSpeakerEngine? = { nil }
        ) {
            self.openBrowser = openBrowser
            self.loginItem = loginItem
            self.standsAside = standsAside
            self.asideNote = asideNote
            self.otherSecrets = otherSecrets
            self.postSignedOut = postSignedOut
            self.inUseSettings = inUseSettings
            self.inUseEngine = inUseEngine
        }

        /// Why `--login-item` does nothing for the extension.
        public static let extensionHasNoLoginItem =
            "the extension runs while Vitruvian runs; it has no login item of its own"

        static let browser: @Sendable (URL) -> Void = { _ = NSWorkspace.shared.open($0) }

        /// The app's: its login item through the system. Nothing is chosen
        /// yet, so by default it never stands aside.
        public static func app(
            standsAside: @escaping @Sendable () -> Bool = { false },
            asideNote: @escaping @Sendable () -> String? = { nil },
            otherSecrets: @escaping @Sendable () -> Secrets? = { nil },
            postSignedOut: @escaping @Sendable (_ chatOnly: Bool, Notification.Name) -> Void = {
                SignOutNotice.post(chatOnly: $0, name: $1)
            },
            inUseSettings: @escaping @Sendable () -> SpeakerConfig? = { nil },
            inUseEngine: @escaping @MainActor @Sendable () -> HomeSpeakerEngine? = { nil }
        ) -> Parts {
            Parts(openBrowser: browser, loginItem: .control(SystemLoginItem()), standsAside: standsAside,
                  asideNote: asideNote, otherSecrets: otherSecrets, postSignedOut: postSignedOut,
                  inUseSettings: inUseSettings, inUseEngine: inUseEngine)
        }

        /// The extension's: no login item of its own. `otherSecrets` is the
        /// app's sign-ins while it is installed, as for the app's side.
        public static func `extension`(
            standsAside: @escaping @Sendable () -> Bool = { false },
            otherSecrets: @escaping @Sendable () -> Secrets? = { nil },
            postSignedOut: @escaping @Sendable (_ chatOnly: Bool, Notification.Name) -> Void = {
                SignOutNotice.post(chatOnly: $0, name: $1)
            },
            inUseSettings: @escaping @Sendable () -> SpeakerConfig? = { nil },
            inUseEngine: @escaping @MainActor @Sendable () -> HomeSpeakerEngine? = { nil }
        ) -> Parts {
            Parts(openBrowser: browser, loginItem: .none(reason: extensionHasNoLoginItem), standsAside: standsAside,
                  otherSecrets: otherSecrets, postSignedOut: postSignedOut, inUseSettings: inUseSettings,
                  inUseEngine: inUseEngine)
        }
    }

    // MARK: - Running it

    /// What one command does, decided but not yet done: print now, or run
    /// off the main actor with a time limit.
    public enum Action {
        /// Print this and exit with its code.
        case now(CLIOutput)
        /// Run `body`, print what it returns and exit with its code; after
        /// `timeout` seconds, print `timedOut` and exit instead.
        case headless(timeout: TimeInterval, timedOut: CLIOutput, body: @Sendable () async -> CLIOutput)
    }

    /// Runs `arguments` on `engine` and exits with the command's code. For
    /// arguments it does not recognize, prints a usage error and exits 2.
    @MainActor
    public static func run(_ arguments: [String], engine: HomeSpeakerEngine, parts: Parts) -> Never {
        perform(action(for: arguments, engine: engine, parts: parts, environment: ProcessInfo.processInfo.environment))
    }

    /// What `arguments` do on `engine`, without printing or exiting: the
    /// whole of `run` but the printing, so tests drive the real wiring.
    ///
    /// The engine's settings are read only where they always were, and no
    /// sooner: `--say` and `--announce` at once (for their time limit), the
    /// Stop hook once its transcript reads, the volume flags and `--discover`
    /// inside their run, and a bad `--set-volume` never. Every other command
    /// reads no setting, so it never writes the default settings file and
    /// never prints a settings problem ahead of its own lines.
    ///
    /// `environment` is the process's, for whose shell `--say` runs in
    /// (`BroadcastSource`); a test's is empty, so it speaks as a person.
    @MainActor
    public static func action(
        for arguments: [String], engine: HomeSpeakerEngine, parts: Parts,
        standardInput: () -> Data = { FileHandle.standardInput.readDataToEndOfFile() },
        environment: [String: String] = [:]
    ) -> Action {
        guard let command = parse(arguments) else {
            return .now(usageError(UsageError("no HomeSpeaker command in: \(arguments.joined(separator: " "))")))
        }
        let profile = engine.profile
        let history = engine.history
        let announcer = engine.announcer
        let home = engine.home
        let auth = engine.auth
        let standsAside = parts.standsAside
        let asideNote = parts.asideNote
        // Read at once for --say and --announce only: their limit grows
        // with this Mac's speech, using the settings of whichever
        // HomeSpeaker is in use.
        let limit = timeLimit(for: command, settings: { parts.inUseSettings() ?? engine.config.config })
        /// Runs `body` under the command's own time limit.
        func headless(_ body: @escaping @Sendable () async -> CLIOutput) -> Action {
            guard let limit else { preconditionFailure("\(command) runs later but has no time limit") }
            return .headless(timeout: limit.seconds, timedOut: limit.timedOut, body: body)
        }

        switch command {
        case .announce(let text, let agent):
            // Automated, so quiet hours hold.
            return headless {
                let settings = await MainActor.run { engine.config.config }
                return await announce(
                    text, for: agent, config: settings, announcer: announcer, history: history,
                    standsAside: standsAside())
            }
        case .stopHook(let agent):
            let input = standardInput()
            return headless {
                await stopHook(
                    agent, input: input, config: { engine.config }, history: history, standsAside: standsAside(),
                    broadcaster: ClaudeStopHook.broadcaster(for: home))
            }
        case .app(.failure(let usage)), .chatMonitor(.failure(let usage)):
            return .now(usageError(usage))
        case .app(.success(let command)):
            switch command {
            case .loginItem(let action):
                return .now(loginItem(action, item: parts.loginItem))
            case .signOut(let chatOnly):
                // The one sign-out rule (design 7.7): a login the other side
                // shares is removed here only, never revoked at Google.
                let otherSecrets = parts.otherSecrets
                let post = parts.postSignedOut
                let name = SignOutNotice.notificationName(for: profile)
                return headless {
                    await engine.signOut(
                        chatOnly: chatOnly, otherSecrets: otherSecrets(), notify: { post($0, name) })
                }
            case .discover(let save, let wanted):
                return headless {
                    let current = await MainActor.run { engine.config.config.structureId }
                    return await AppCommandRunner.discover(
                        save: save, home: wanted, client: home, currentStructureId: current,
                        apply: { home, targets in
                            engine.config.config.applyDiscovery(
                                structureId: home.id, structureName: home.name, targets: targets)
                            try engine.config.trySaveConfig()
                        })
                }
            case .testMediaPause:
                return headless {
                    await AppCommandRunner.testMediaPause(coordinator: MediaPauseCoordinator())
                }
            }
        case .chatMonitor(.success(let action)):
            return .now(chatMonitor(action, profile: profile) { ChatMonitorControlNotice.post($0, name: $1) })
        case .say(let text):
            // Deliberate, like Quick Announce: it overrides quiet hours but
            // still honours the master switch. An agent's also needs its
            // own switch on, in the settings of the HomeSpeaker in use.
            let source: BroadcastSource
            switch BroadcastSource.resolve(arguments: arguments, environment: environment) {
            case .success(let resolved): source = resolved
            case .failure(let usage): return .now(usageError(usage))
            }
            let inUseSettings = parts.inUseSettings
            let inUseEngine = parts.inUseEngine
            return headless {
                let (settings, activeAnnouncer, activeHistory) = await MainActor.run {
                    let active = inUseEngine() ?? engine
                    return (engine.config.config, active.announcer, active.history)
                }
                return await say(
                    text, config: settings, announcer: activeAnnouncer, history: activeHistory,
                    standsAside: standsAside(), door: profile.door, note: asideNote(),
                    source: source, inUse: inUseSettings())
            }
        case .volume(.invalidLevel):
            return .now(volumeFailure(badLevelReason))
        case .volume(let request):
            return headless {
                let settings = await MainActor.run { engine.config.config }
                return await volume(request, config: settings, speaker: home)
            }
        case .signIn(let purpose):
            let openBrowser = parts.openBrowser
            return headless {
                await signIn(
                    purpose: purpose,
                    signIn: { try await auth.signIn(purpose: $0, openBrowser: $1) },
                    openBrowser: openBrowser,
                    progress: { print($0) },
                    notify: { CredentialsChangedNotice.post(name: CredentialsChangedNotice.notificationName(for: profile)) })
            }
        case .help:
            return .now(help())
        case .version:
            return .now(version())
        case .location:
            return .now(dataFolder(of: profile))
        }
    }

    // MARK: - Time limits

    /// How long a command that runs later may take, and what it prints when
    /// that runs out. The command line prints it and exits; the extension's
    /// tool, which runs the same commands in its own process, answers with
    /// the same words.
    public struct TimeLimit: Equatable, Sendable {
        public var seconds: TimeInterval
        public var timedOut: CLIOutput

        public init(seconds: TimeInterval, timedOut: CLIOutput) {
            self.seconds = seconds
            self.timedOut = timedOut
        }
    }

    /// `command`'s time limit; nil for the commands that print at once.
    /// `settings` is asked for only by `--say` and `--announce`, whose limit
    /// grows with this Mac's speech; every other command reads none.
    public static func timeLimit(for command: Command, settings: () -> SpeakerConfig) -> TimeLimit? {
        let timedOut = CLIOutput.failure("timed out")
        switch command {
        case .announce(let text, _):
            return TimeLimit(seconds: announceTimeout(text, config: settings(), restyle: true), timedOut: timedOut)
        case .say(let text):
            return TimeLimit(seconds: announceTimeout(text, config: settings()), timedOut: timedOut)
        case .stopHook:
            // Each agent enforces its own hook timeout (10 s as installed);
            // this backstop means a hung network call can never wedge the
            // agent. Output is always "{}", a well-formed no-op hook result
            // for Claude Code and Antigravity alike.
            return TimeLimit(seconds: 8, timedOut: CLIOutput(stdout: ["{}"]))
        case .app(.success(.signOut)), .app(.success(.testMediaPause)):
            return TimeLimit(seconds: 30, timedOut: timedOut)
        case .app(.success(.discover)):
            return TimeLimit(seconds: 60, timedOut: timedOut)
        case .volume(.invalidLevel):
            return nil
        case .volume:
            // Two 6 s confirm windows plus retries: 40 s, not --say's 20.
            return TimeLimit(seconds: 40, timedOut: volumeFailure("timed out"))
        case .signIn:
            return TimeLimit(seconds: 300, timedOut: timedOut)
        case .app(.success(.loginItem)), .app(.failure), .chatMonitor, .help, .version, .location:
            return nil
        }
    }

    /// Does `action`: prints and exits.
    static func perform(_ action: Action) -> Never {
        switch action {
        case .now(let output):
            emit(output)
        case .headless(let timeout, let timedOut, let body):
            runHeadless(timeout: timeout, onTimeout: { emit(timedOut) }) { emit(await body()) }
        }
    }

    /// Prints `output` and exits with its code.
    static func emit(_ output: CLIOutput) -> Never {
        for line in output.stdout { print(line) }
        for line in output.stderr { FileHandle.standardError.write(Data("\(line)\n".utf8)) }
        exit(output.exitCode)
    }

    /// Runs `body` off the main actor while the main thread services the
    /// main queue, then exits. A program's `@main` `main()`, or its
    /// top-level code, is MainActor-isolated, so a plain `Task {}` there
    /// would inherit that and deadlock against a blocking wait; the settings
    /// are MainActor-bound too, so the main thread must keep running its
    /// run loop (`MainThreadLoop`) rather than block on a semaphore, or
    /// leave the main queue to a worker thread as `dispatchMain()` does.
    static func runHeadless(
        timeout: TimeInterval,
        onTimeout: @escaping @Sendable () -> Void,
        _ body: @escaping @Sendable () async -> Void
    ) -> Never {
        Task.detached {
            await body()
            exit(0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            onTimeout()
            exit(0)
        }
        MainThreadLoop.run()
    }

    // MARK: - Each flag's outcome

    /// `--say <text>`: speaks, whichever HomeSpeaker is chosen, because
    /// someone asked. When the other one (`door`'s other) is in use, says
    /// so on standard error.
    ///
    /// For a coding agent's `source`, the master switch and that agent's
    /// own switch are read from `inUse` (the other HomeSpeaker's settings,
    /// while it is the one in use), else from `config`; either off says so
    /// and speaks nothing (`agentRefusal`). `records` false speaks without
    /// adding to the history: a replay of what is already in it.
    public static func say(
        _ text: String, config: SpeakerConfig, announcer: Announcer, history: BroadcastHistory,
        standsAside: Bool, door: HomeSpeakerProfile.Door, note: String? = nil,
        source: BroadcastSource = .user, inUse: SpeakerConfig? = nil, records: Bool = true, at date: Date = Date()
    ) async -> CLIOutput {
        let active = inUse ?? config
        if let agent = source.agent, let refusal = agentRefusal(agent, config: active) {
            return refusal
        }
        var out = await announcement(
            text, force: true, source: source.historyLabel, records: records, config: active, announcer: announcer,
            history: history, at: date)
        if standsAside {
            let other = door == .app ? "extension" : "app"
            out.stderr.insert(note ?? "note: the HomeSpeaker \(other) is the one in use", at: 0)
        }
        return out
    }

    /// `--announce <text>`, the Stop hook's detached announcement:
    /// automated, so quiet hours hold. Prints nothing and says nothing when
    /// this side stands aside.
    public static func announce(
        _ text: String, for agent: CodingAgent = .claudeCode, config: SpeakerConfig, announcer: Announcer,
        history: BroadcastHistory, standsAside: Bool, at date: Date = Date()
    ) async -> CLIOutput {
        guard !standsAside else { return CLIOutput() }
        // Switched off since the hook handed it over: nothing is said.
        if let refusal = agentRefusal(agent, config: config) { return refusal }
        return await announcement(
            text, force: false, source: agent.displayName, restyle: true, config: config, announcer: announcer,
            history: history, at: date)
    }

    /// Speaks `text` on the home speakers and/or this Mac, as `config`
    /// says. Returns once this Mac has finished speaking (docs/local-speech.md
    /// rule 9). Exit 0 when anything was heard, or nothing was meant to be
    /// (quiet hours, no outputs); 1 when it failed. What was heard goes into
    /// `history` under `source`, so the menu bar's Recent Broadcasts shows it.
    static func announcement(
        _ text: String, force: Bool, source: String, records: Bool = true, restyle: Bool = false,
        config: SpeakerConfig, announcer: Announcer, history: BroadcastHistory, at date: Date
    ) async -> CLIOutput {
        guard config.enabled else { return CLIOutput(stderr: ["broadcasting is switched off"], exitCode: 1) }
        // Home only with no speaker picked: the same message as before.
        if config.effectiveSpeakHome && !config.effectiveSpeakLocal && config.defaultDevice == nil {
            return CLIOutput(stderr: ["no default speaker; open HomeSpeaker and pick one"], exitCode: 1)
        }
        let (outcome, spoken) = await announcer.announceReporting(
            text, config: config, force: force, restyle: restyle, at: date)
        // A reworded reply is listed as it was heard.
        let heardText = restyle && AnnouncementStylist.rewrites(config) ? (spoken ?? text) : text
        // With no long-lived HomeSpeaker alive, this process paused the
        // media itself: stay until it is resumed, never exit holding it.
        await announcer.media.waitUntilReleased()
        var out = CLIOutput()
        switch outcome {
        case .disabled:
            return CLIOutput(stderr: ["broadcasting is switched off"], exitCode: 1)
        case .quietHours(let until):
            out.stderr.append("Quiet hours active until \(until). Nothing spoken.")
        case .noOutputs:
            out.stdout.append(AnnounceOutcome.noOutputsMessage)
        case .nothingToSay:
            out.stderr.append("nothing to say after cleaning up the text")
        case .announced:
            // Heard here with the home speaker failed is one line that says
            // both, so the tool, which shows this output, says it.
            out.stdout += outcome.spokenLines(homeName: config.defaultDevice?.name ?? "the home speakers")
            if outcome.anySpoke, records {
                let heardOn = outcome.spokenLabel(homeName: config.defaultDevice?.name ?? "Home speakers")
                do {
                    try history.append(BroadcastLogItem(text: heardText, targetName: heardOn, source: source))
                } catch {
                    out.stderr.append("warning: could not record the broadcast: \(error.localizedDescription)")
                }
            }
            out.stderr += outcome.failureMessages.map { "error: \($0)" }
            if !outcome.anySpoke { out.exitCode = 1 }
        }
        return out
    }

    /// Why an announcement `agent` sent is not spoken, by `config`; nil when
    /// it may be. Broadcasting off is the failure it always was (exit 1);
    /// the agent's own switch off is the person's choice, so it exits 0, as
    /// quiet hours do, and the agent is not told it failed.
    public static func agentRefusal(_ agent: CodingAgent, config: SpeakerConfig) -> CLIOutput? {
        guard config.enabled else { return CLIOutput(stderr: ["broadcasting is switched off"], exitCode: 1) }
        guard config.announces(agent) else {
            return CLIOutput(stderr: [agentSwitchedOff(agent)])
        }
        return nil
    }

    /// What an agent's announcement says while its switch is off.
    public static func agentSwitchedOff(_ agent: CodingAgent) -> String {
        "\(agent.displayName) announcements are switched off in HomeSpeaker. Nothing spoken."
    }

    /// How long `--say` or `--announce` may take: 20 s covered a home
    /// broadcast; this Mac speaking adds its own time.
    /// `restyle` is `--announce`'s rewording, which can take both models'
    /// time limits; the reworded text is never longer than the speech
    /// length allows, so the rest still holds.
    static func announceTimeout(_ text: String, config: SpeakerConfig, restyle: Bool = false) -> TimeInterval {
        var timeout: TimeInterval = 20
        let spoken = GoogleHomeClient.cleanForSpeech(text, length: config.effectiveSpeechLength)
        if restyle && AnnouncementStylist.rewrites(config) {
            timeout += AnnouncementStylist.worstCaseSeconds
        }
        if config.effectiveSpeakLocal {
            timeout += LocalSpeaker.timeLimit(for: spoken)
            // Gemini's answer, and its audio failing late, before the Mac
            // voice says it after all.
            if config.effectiveLocalEngine == .gemini {
                timeout += GeminiSpeaker.synthesisTimeout + LocalSpeaker.timeLimit(for: spoken)
            }
        }
        // With nobody else alive to hold paused media, this process waits
        // out the hold itself (`MediaPausing.waitUntilReleased`): it must
        // never be cut off while the media is still paused.
        if config.effectivePauseMedia {
            timeout += AnnouncementTiming.seconds(for: spoken, extra: config.effectivePauseMediaExtraSeconds)
        }
        return timeout
    }

    /// `--claude-stop-hook`: speaks the turn's last reply, as
    /// `ClaudeStopHook.run` decides, and always answers `{}`. `config` is
    /// asked for only once the transcript reads. When this side stands aside
    /// it reads nothing and speaks nothing.
    public static func claudeStopHook(
        input: Data, config: @escaping @MainActor @Sendable () -> ConfigManager, history: BroadcastHistory,
        standsAside: Bool,
        lockDirectory: URL = ClaudeStopHook.lockDirectory,
        launchDetached: @escaping @Sendable (String) -> Void = { DetachedAnnouncement.launch(text: $0) },
        broadcaster: @escaping ClaudeStopHook.Broadcaster
    ) async -> CLIOutput {
        await stopHook(
            .claudeCode, input: input, config: config, history: history, standsAside: standsAside,
            lockDirectory: lockDirectory, launchDetached: launchDetached, broadcaster: broadcaster)
    }

    /// Any agent's end-of-turn hook (`--claude-stop-hook`,
    /// `--antigravity-hook`, `--opencode-hook`): speaks the turn's last
    /// reply as that agent's reader decides, and always answers `{}`.
    /// `launchDetached` defaults to `--announce` for `agent`.
    public static func stopHook(
        _ agent: CodingAgent,
        input: Data, config: @escaping @MainActor @Sendable () -> ConfigManager, history: BroadcastHistory,
        standsAside: Bool,
        lockDirectory: URL = ClaudeStopHook.lockDirectory,
        launchDetached: (@Sendable (String) -> Void)? = nil,
        broadcaster: @escaping ClaudeStopHook.Broadcaster
    ) async -> CLIOutput {
        guard !standsAside else { return CLIOutput(stdout: ["{}"]) }
        let detached = launchDetached ?? { DetachedAnnouncement.launch(text: $0, agent: agent) }
        switch agent {
        case .claudeCode:
            await ClaudeStopHook.run(
                input: input, config: config, history: history, lockDirectory: lockDirectory,
                launchDetached: detached, broadcaster: broadcaster)
        case .antigravity:
            await AntigravityHook.run(
                input: input, config: config, history: history, lockDirectory: lockDirectory,
                launchDetached: detached, broadcaster: broadcaster)
        case .opencode:
            await OpenCodeHook.run(
                input: input, config: config, history: history, lockDirectory: lockDirectory,
                launchDetached: detached, broadcaster: broadcaster)
        }
        return CLIOutput(stdout: ["{}"])
    }

    /// The default speaker's volume, as JSON on stdout: the contract the
    /// Mac agent (android-remote) relies on. `--set-volume N`, `--mute` and
    /// `--unmute` change it and answer with the level read back afterwards.
    /// Failures are still JSON (available:false + reason) and exit 1.
    public static func volume(
        _ request: VolumeRequest, config: SpeakerConfig, speaker: VolumeAndMuteControlling
    ) async -> CLIOutput {
        if request == .invalidLevel { return volumeFailure(badLevelReason) }
        guard let target = config.defaultDevice else {
            return volumeFailure("no default speaker; open HomeSpeaker and pick one")
        }
        do {
            var confirmed: SpeakerVolume?
            switch request {
            case .set(let level):
                confirmed = try await speaker.setVolumeConfirmed(level, on: target, structureId: config.structureId)
            case .mute: try await speaker.setMuted(true, on: target, structureId: config.structureId)
            case .unmute: try await speaker.setMuted(false, on: target, structureId: config.structureId)
            case .read, .invalidLevel: break
            }
            // After a set, the level Google finally reports (it lags ~3 s);
            // otherwise --set-volume 41 answers with the old 40.
            let v: SpeakerVolume
            if let confirmed { v = confirmed } else { v = try await speaker.volume(of: target, structureId: config.structureId) }
            return CLIOutput(stdout: volumeJSON([
                "available": true, "speaker": target.name,
                "percent": v.percent, "muted": v.muted, "online": v.online,
            ]))
        } catch {
            return CLIOutput(
                stdout: volumeJSON(["available": false, "speaker": target.name, "reason": error.localizedDescription]),
                exitCode: 1)
        }
    }

    static let badLevelReason = "--set-volume needs a whole number from 0 to 100"

    static func volumeFailure(_ reason: String) -> CLIOutput {
        CLIOutput(stdout: volumeJSON(["available": false, "reason": reason]), exitCode: 1)
    }

    /// One JSON object on one line, its keys sorted, for the Mac agent to
    /// parse. No line when it does not serialize.
    static func volumeJSON(_ object: [String: Any]) -> [String] {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return [] }
        return [line]
    }

    /// `--sign-in [--chat]`: the browser sign-in the Settings buttons run.
    /// `--chat` signs in for Google Chat instead of Home (Google refuses
    /// both scopes in one grant, so they are separate logins). `progress`
    /// prints as it goes; `notify` tells a running HomeSpeaker to re-read
    /// the login and start or restart the chat monitor with it.
    public static func signIn(
        purpose: GoogleAuth.Purpose,
        signIn: @Sendable (GoogleAuth.Purpose, @escaping @Sendable (URL) -> Void) async throws -> GoogleCredentials,
        openBrowser: @escaping @Sendable (URL) -> Void,
        progress: @escaping @Sendable (String) -> Void,
        notify: @Sendable () -> Void
    ) async -> CLIOutput {
        do {
            let creds = try await signIn(purpose) { url in
                progress("opening browser: \(url.host ?? "")")
                openBrowser(url)
            }
            notify()
            return CLIOutput(stdout: ["signed in as \(creds.email ?? "unknown"); scopes: \(creds.scopes.joined(separator: " "))"])
        } catch {
            return CLIOutput(stderr: ["error: \(error.localizedDescription)"], exitCode: 1)
        }
    }

    /// `--login-item`: the app's, or for the extension, why it has none.
    public static func loginItem(_ action: LoginItemAction, item: Parts.LoginItem) -> CLIOutput {
        switch item {
        case .control(let control): return AppCommandRunner.loginItem(action, control: control)
        case .none(let reason): return .failure(reason)
        }
    }

    /// `--chat-monitor start|stop`: asks the running HomeSpeaker, which is
    /// where the monitor lives, under `profile`'s names. Only posts.
    public static func chatMonitor(
        _ action: ChatMonitorAction, profile: HomeSpeakerProfile,
        post: (ChatMonitorAction, Notification.Name) -> Void
    ) -> CLIOutput {
        post(action, ChatMonitorControlNotice.notificationName(for: profile))
        return CLIOutput(stdout: [ChatMonitorControlNotice.askedLine(action)])
    }

    /// A flag used wrongly: the caller's mistake, exit 2.
    public static func usageError(_ usage: UsageError) -> CLIOutput {
        CLIOutput(stderr: ["error: \(usage.message)", "run HomeSpeaker --help for usage"],
                  exitCode: AppCommandParser.usageExitCode)
    }

    /// `--help`. Without it, `--help` fell through to the menu bar app and
    /// hung a terminal on a second copy of it.
    public static func help() -> CLIOutput {
        CLIOutput(stdout: ["""
        HomeSpeaker \(HomeSpeakerVersion.current) — speaks your coding agent's replies on a Google speaker.

        usage: HomeSpeaker [flag]
          (no flag)            run the menu bar app
          --say <text>         announce text on the default speaker and/or this Mac
          --source <name> --say <text>
                               the same, for claude-code, antigravity or opencode:
                               spoken only while that agent's switch is on (default:
                               the agent whose shell runs it, else a person)
          --volume             the default speaker's volume, as JSON
          --set-volume <0-100> set it; --mute / --unmute likewise
          --sign-in [--chat]   sign in for Home (or Google Chat)
        \(AppCommandParser.usageLines)
          --chat-monitor start|stop
                               start or stop the chat monitor in the running app
          --claude-stop-hook   Claude Code Stop hook; reads hook JSON on stdin
          --antigravity-hook   Antigravity Stop hook; reads hook JSON on stdin
          --opencode-hook      OpenCode session.idle plugin; reads messages JSON on stdin
          --version            print the version
          --help               print this
        """])
    }

    /// `--version`.
    public static func version() -> CLIOutput {
        CLIOutput(stdout: ["HomeSpeaker \(HomeSpeakerVersion.current)"])
    }

    /// `--where`: the folder `profile` keeps its settings in. The
    /// extension's data folder; for the app, `~/.gemini`.
    public static func dataFolder(of profile: HomeSpeakerProfile) -> CLIOutput {
        CLIOutput(stdout: [profile.settingsURL.deletingLastPathComponent().path])
    }
}

/// What the volume flags need from a speaker: its volume, and mute.
public protocol VolumeAndMuteControlling: VolumeControlling {
    func setMuted(_ muted: Bool, on target: SpeakerDevice, structureId: String) async throws
}

extension GoogleHomeClient: VolumeAndMuteControlling {}
