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
@preconcurrency import HomeSpeakerCore

/// Runs the tool's jobs on the extension's own engine, in the tool's own
/// process: no HomeSpeaker program is started.
///
/// Each job goes through the same Core function the command line runs for
/// that flag (`HomeSpeakerCommandLine.say`, `.volume`, `.signIn`,
/// `.loginItem`, `AppCommandRunner.discover`, `.testMediaPause`; sign-out
/// through `HomeSpeakerEngine.signOut`). What the function printed is read
/// by `ProcessDriver.result`, exactly as the program's printing was, so the
/// tool's state machine (`HomeSpeakerTool.finished`) gets the `JobResult`
/// it always got and needs no change.
///
/// The settings, the history and the sign-ins are the engine's: the
/// extension's own files, never the app's.
///
/// Each job has the command line's time limit for its flag
/// (`HomeSpeakerCommandLine.timeLimit(for:settings:)`): when it runs out, the
/// job answers what the program printed when it gave up, so a call to Google
/// or a speaker that never returns cannot hold the tool's slot forever. The
/// job itself is asked to stop; its later answer is dropped.
///
/// `run` may be called from any thread and never blocks it: each job runs
/// in a detached task, and what must run on the main actor (the settings,
/// the sign-out) is awaited there, as the command line does. So the process
/// must keep its main actor running. `then` is called once, on a thread of
/// the system's.
public final class EngineDriver: SpeakerDriver, Sendable {
    /// What the jobs run on besides the engine's files. `init(engine:…)`
    /// takes the engine's own; tests put stand-ins in their place.
    public struct Parts: Sendable {
        /// Speaks `--say` on the home speakers and this Mac.
        public var announcer: Announcer
        /// The default speaker's volume and mute.
        public var speaker: any VolumeAndMuteControlling
        /// The homes and their speakers, for discovery.
        public var homes: any HomeDiscovering
        /// The browser sign-in for one purpose; it calls its second
        /// argument with the page to open.
        public var signIn: @Sendable (GoogleAuth.Purpose, @escaping @Sendable (URL) -> Void) async throws -> GoogleCredentials
        /// Opens the sign-in page through the app (`open/url`). When nil,
        /// `browser` opens it.
        public var link: (@Sendable (URL) -> Void)?
        /// This Mac's browser: the command line's own (`NSWorkspace`).
        public var browser: @Sendable (URL) -> Void
        /// The app's sign-ins, when it is installed, so a sign-out never
        /// revokes a login the app shares (`HomeSpeakerEngine.signOut`).
        public var otherSecrets: @Sendable () -> Secrets?
        /// True when the app is the one chosen: `--say` then says so on
        /// standard error, and still speaks.
        public var standsAside: @Sendable () -> Bool
        /// Told after a sign-in: by default the extension's own
        /// credentials-changed notice, as `--sign-in` posts it.
        public var signedIn: @Sendable () -> Void
        /// Told after a sign-out: by default the extension's own sign-out
        /// notice, as `--sign-out` posts it.
        public var signedOut: @Sendable (_ chatOnly: Bool) -> Void
        /// How long a job may run, given the command line's limit for its
        /// flag: that limit itself, unless a test shortens it.
        public var allowed: @Sendable (_ limit: TimeInterval) -> TimeInterval

        /// The engine's own parts: its announcer, its Google Home client
        /// and its sign-in; the browser and the notices the command line
        /// uses, under the engine's message names.
        @MainActor
        public init(
            engine: HomeSpeakerEngine,
            otherSecrets: @escaping @Sendable () -> Secrets?,
            link: (@Sendable (URL) -> Void)? = nil,
            standsAside: @escaping @Sendable () -> Bool = { false }
        ) {
            let auth = engine.auth
            let profile = engine.profile
            announcer = engine.announcer
            speaker = engine.home
            homes = engine.home
            signIn = { try await auth.signIn(purpose: $0, openBrowser: $1) }
            self.link = link
            browser = HomeSpeakerCommandLine.Parts.extension().openBrowser
            self.otherSecrets = otherSecrets
            self.standsAside = standsAside
            signedIn = { CredentialsChangedNotice.post(name: CredentialsChangedNotice.notificationName(for: profile)) }
            signedOut = { SignOutNotice.post(chatOnly: $0, name: SignOutNotice.notificationName(for: profile)) }
            allowed = { $0 }
        }
    }

    /// The tool's own program, which the agents' hooks run.
    public let program: URL?
    private let engine: HomeSpeakerEngine
    private let door: HomeSpeakerProfile.Door
    private let history: BroadcastHistory
    private let parts: Parts

    @MainActor
    public init(engine: HomeSpeakerEngine, program: URL, parts: Parts) {
        self.program = program
        self.engine = engine
        door = engine.profile.door
        history = engine.history
        self.parts = parts
    }

    /// The engine is in this process, so it is always there.
    public var isInstalled: Bool { true }

    public func run(_ job: Job, then: @escaping @Sendable (JobResult) -> Void) {
        let engine = engine
        let door = door
        let history = history
        let parts = parts
        let answer = Answer { printed in
            then(ProcessDriver.result(
                of: job, status: printed.exitCode,
                output: Self.lines(printed.stdout), error: Self.lines(printed.stderr)))
        }
        Task.detached {
            let command = Self.command(for: job)
            let limit = await MainActor.run {
                HomeSpeakerCommandLine.timeLimit(for: command, settings: { engine.config.config })
            }
            // The clock starts before the work does, so work that answers at
            // once cannot get ahead of it.
            if let limit {
                answer.give(limit.timedOut, after: parts.allowed(limit.seconds))
            }
            let work = Task.detached {
                let printed = await Self.output(of: job, engine: engine, door: door, history: history, parts: parts)
                answer.give(printed)
            }
            answer.stop(work)
        }
    }

    /// The command line's command for `job`, as `ProcessDriver.arguments`
    /// would ask for it.
    static func command(for job: Job) -> HomeSpeakerCommandLine.Command {
        switch job {
        case .say(let text): return .say(text)
        case .volume, .setVolume, .mute, .unmute: return .volume(volumeRequest(job))
        case .app(let command): return .app(.success(command))
        case .signIn(let chatOnly): return .signIn(chatOnly ? .chat : .home)
        }
    }

    /// What the flag for `job` prints, run on the engine.
    static func output(
        of job: Job, engine: HomeSpeakerEngine, door: HomeSpeakerProfile.Door,
        history: BroadcastHistory, parts: Parts
    ) async -> CLIOutput {
        switch job {
        case .say(let text):
            let settings = await settings(of: engine)
            return await HomeSpeakerCommandLine.say(
                text, config: settings, announcer: parts.announcer, history: history,
                standsAside: parts.standsAside(), door: door)
        case .volume, .setVolume, .mute, .unmute:
            let settings = await settings(of: engine)
            return await HomeSpeakerCommandLine.volume(volumeRequest(job), config: settings, speaker: parts.speaker)
        case .app(.signOut(let chatOnly)):
            return await signOut(chatOnly: chatOnly, engine: engine, parts: parts)
        case .app(.discover(let save, let wanted)):
            let current = await settings(of: engine).structureId
            return await AppCommandRunner.discover(
                save: save, home: wanted, client: parts.homes, currentStructureId: current,
                apply: { home, targets in
                    engine.config.config.applyDiscovery(
                        structureId: home.id, structureName: home.name, targets: targets)
                    try engine.config.trySaveConfig()
                })
        case .app(.loginItem(let action)):
            // The extension has no login item of its own: the command
            // line's refusal, in its words.
            return HomeSpeakerCommandLine.loginItem(action, item: HomeSpeakerCommandLine.Parts.extension().loginItem)
        case .app(.testMediaPause):
            return await testMediaPause()
        case .signIn(let chatOnly):
            // The program printed the line it waits on before who signed
            // in; the tool reads both, so they are kept in that order.
            let progress = Printed()
            var out = await HomeSpeakerCommandLine.signIn(
                purpose: chatOnly ? .chat : .home, signIn: parts.signIn,
                openBrowser: parts.link ?? parts.browser,
                progress: { progress.add($0) }, notify: parts.signedIn)
            out.stdout = progress.lines + out.stdout
            return out
        }
    }

    /// The flag's request, held to 0 to 100 as `ProcessDriver.arguments` holds it.
    static func volumeRequest(_ job: Job) -> HomeSpeakerCommandLine.VolumeRequest {
        switch job {
        case .setVolume(let level): return .set(min(100, max(0, level)))
        case .mute: return .mute
        case .unmute: return .unmute
        default: return .read
        }
    }

    /// The engine's settings, read on the main actor as the command line
    /// reads them.
    private static func settings(of engine: HomeSpeakerEngine) async -> SpeakerConfig {
        await MainActor.run { engine.config.config }
    }

    /// `--sign-out [--chat]`: the engine's one sign-out path.
    @MainActor
    private static func signOut(chatOnly: Bool, engine: HomeSpeakerEngine, parts: Parts) async -> CLIOutput {
        await engine.signOut(chatOnly: chatOnly, otherSecrets: parts.otherSecrets(), notify: parts.signedOut)
    }

    /// `--test-media-pause`, on a coordinator of its own as the command line runs it.
    @MainActor
    private static func testMediaPause() async -> CLIOutput {
        await AppCommandRunner.testMediaPause(coordinator: MediaPauseCoordinator())
    }

    /// Lines as `print` wrote them.
    static func lines(_ lines: [String]) -> String {
        lines.map { $0 + "\n" }.joined()
    }
}

/// A job's one answer: what it printed, or, when its time ran out first,
/// what the command line prints then. Whichever comes second is dropped,
/// and the other side is asked to stop.
private final class Answer: @unchecked Sendable {
    private let lock = NSLock()
    private var given = false
    private var timer: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var timedOut = false
    private let then: @Sendable (CLIOutput) -> Void

    init(_ then: @escaping @Sendable (CLIOutput) -> Void) {
        self.then = then
    }

    /// Answers `printed`, unless there is an answer already. True when this
    /// was the answer.
    @discardableResult
    func give(_ printed: CLIOutput) -> Bool {
        let (first, timer) = lock.withLock { () -> (Bool, Task<Void, Never>?) in
            defer {
                given = true
                self.timer = nil
            }
            return (!given, self.timer)
        }
        timer?.cancel()
        if first { then(printed) }
        return first
    }

    /// After `seconds`, answers `timedOut` if nothing has answered, and asks
    /// the work to stop (see `stop`).
    func give(_ timedOut: CLIOutput, after seconds: TimeInterval) {
        lock.withLock {
            guard !given else { return }
            timer = Task.detached {
                do {
                    try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                } catch {
                    return
                }
                if self.give(timedOut) { self.stopTheWork() }
            }
        }
    }

    /// The work that answers, once it has been started after the clock.
    /// Cancelled when time ran out first, even if that was before this call.
    func stop(_ work: Task<Void, Never>) {
        let cancelNow = lock.withLock { () -> Bool in
            self.work = work
            return timedOut
        }
        if cancelNow { work.cancel() }
    }

    private func stopTheWork() {
        let work = lock.withLock { () -> Task<Void, Never>? in
            timedOut = true
            return self.work
        }
        work?.cancel()
    }
}

/// The lines a sign-in printed while it waited, from whichever thread.
private final class Printed: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []
    func add(_ line: String) { lock.withLock { all.append(line) } }
    var lines: [String] { lock.withLock { all } }
}
