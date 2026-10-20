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

// The menu bar app and the choice (design 7.3 and 7.6). What the app starts
// at launch and stops or starts again when the choice changes, worked out
// here, where a test can drive it; `App.swift` only applies the answers.

/// What the app runs, for its role. Pure.
public enum AppStartup {
    /// A part of the app's start-up that its role turns on or off. Every
    /// other listener stays on in every role: the settings watcher, the
    /// sign-out and credentials-changed notices and the control message
    /// start the monitor only through its gate (`AppDoor.monitor`).
    public enum Part: String, CaseIterable, Sendable {
        /// Re-points a hook left on a moved app
        /// (`AgentIntegration.repairHookIfMoved`).
        case hookRepair
        /// The chat monitor, when a source is switched on
        /// (`ChatMonitorService.startIfConfigured`).
        case chatMonitor
        /// Holding paused media and putting speakers back for the hook and
        /// `--say` (`HomeSpeakerEngine.listen`).
        case listeners
    }

    /// The app's start-up before 1.19, in its order.
    public static let today: [Part] = [.hookRepair, .chatMonitor, .listeners]

    /// What the app does now.
    public struct Plan: Equatable, Sendable {
        /// The app's role. Quiet while the app is in the Trash.
        public let role: DoorRole
        /// The app's own bundle is in a Trash: it stays quiet, shows no
        /// window and writes nothing.
        public let inTrash: Bool
        /// What runs, in start-up order.
        public let starts: [Part]
        /// The choice window and the line in the menu (design 7.4, step 1).
        public let asks: Bool
        /// The quiet window: the extension is in use.
        public let showsQuiet: Bool

        /// The app runs: the hook, the chat monitor, listening.
        public var runs: Bool { !starts.isEmpty }
    }

    /// The plan for `role`. Until the person picks (`activeAsking`) the app
    /// runs exactly as today and asks; only `quiet` stops it.
    public static func plan(role: DoorRole, inTrash: Bool) -> Plan {
        if inTrash {
            return Plan(role: .quiet(other: .extension), inTrash: true, starts: [], asks: false, showsQuiet: false)
        }
        switch role {
        case .active:
            return Plan(role: role, inTrash: false, starts: today, asks: false, showsQuiet: false)
        case .activeAsking, .waitingAsking:
            // `waitingAsking` is the extension's; the app never waits.
            return Plan(role: .activeAsking, inTrash: false, starts: today, asks: true, showsQuiet: false)
        case .quiet:
            return Plan(role: role, inTrash: false, starts: [], asks: false, showsQuiet: true)
        }
    }

    /// The plan from the choice file as read (`record`), whether a file
    /// exists, and where the app's own bundle is now.
    public static func plan(record: DoorRecord?, fileExists: (String) -> Bool, bundlePath: String) -> Plan {
        plan(role: role(record: record, fileExists: fileExists), inTrash: OtherDoorPresence.isInTrash(bundlePath + "/"))
    }

    /// The app's role from the choice file alone, the Trash aside.
    static func role(record: DoorRecord?, fileExists: (String) -> Bool) -> DoorRole {
        let installed = OtherDoorPresence.extensionInstalled(record: record, fileExists: fileExists)
        return DoorRole.decide(me: .app, otherInstalled: installed, chosen: record?.chosen)
    }

    /// The plan, reading the choice file afresh.
    public static func plan(check: DoorCheck, bundlePath: String) -> Plan {
        plan(record: check.file.read(), fileExists: check.fileExists, bundlePath: bundlePath)
    }

    /// The app's command line, each answer asked afresh on each run:
    /// - its Stop hook and `--announce` stand aside while the extension is
    ///   chosen and installed, or the app is in the Trash, so a stale hook
    ///   entry never says a reply twice;
    /// - `--say` says why, accurately (`asideNote`);
    /// - `--say` (both human and agent) follows the extension's settings,
    ///   secrets, announcer and history while the extension is in use
    ///   (`inUseSettings`, `inUseEngine`): `speaker-broadcast` runs this
    ///   program whichever HomeSpeaker the person picked;
    /// - `--sign-out` never revokes a login the extension shares.
    public static func commandLineParts(
        check: DoorCheck = DoorCheck(appInstalled: { false }),
        bundlePath: @escaping @Sendable () -> String = { Bundle.main.bundlePath },
        makeInUseEngine: @escaping @MainActor @Sendable (HomeSpeakerProfile) -> HomeSpeakerEngine = {
            HomeSpeakerEngine(profile: $0)
        },
        postSignedOut: @escaping @Sendable (_ chatOnly: Bool, Notification.Name) -> Void = {
            SignOutNotice.post(chatOnly: $0, name: $1)
        }
    ) -> HomeSpeakerCommandLine.Parts {
        .app(
            standsAside: { plan(check: check, bundlePath: bundlePath()).role.isQuiet },
            asideNote: { asideNote(record: check.file.read(), fileExists: check.fileExists, bundlePath: bundlePath()) },
            otherSecrets: { otherSecrets(check: check) },
            postSignedOut: postSignedOut,
            inUseSettings: { inUseSettings(check: check) },
            inUseEngine: {
                guard let profile = inUseProfile(check: check, bundlePath: bundlePath()) else { return nil }
                return makeInUseEngine(profile)
            })
    }

    /// The extension's profile while it is the HomeSpeaker in use (chosen
    /// and installed, and the app is not in the Trash); nil otherwise.
    public static func inUseProfile(check: DoorCheck, bundlePath: String = Bundle.main.bundlePath) -> HomeSpeakerProfile? {
        guard !OtherDoorPresence.isInTrash(bundlePath + "/") else { return nil }
        let record = check.file.read()
        guard role(record: record, fileExists: check.fileExists).isQuiet else { return nil }
        return extensionProfile(record: record)
    }

    /// The extension's settings while it is the HomeSpeaker in use (chosen
    /// and installed); nil otherwise, or when its file does not read. Read
    /// afresh, never written.
    public static func inUseSettings(check: DoorCheck) -> SpeakerConfig? {
        let record = check.file.read()
        guard role(record: record, fileExists: check.fileExists).isQuiet,
              let profile = extensionProfile(record: record),
              case .loaded(let settings) = SpeakerConfigFile(url: profile.settingsURL).read() else { return nil }
        return settings
    }

    /// What `--say` notes when the app is in the Trash and the extension is
    /// not the one in use (so "the extension is in use" would be untrue).
    public static let inTheTrashNote = "note: this copy of the HomeSpeaker app is in the Trash, so it stays quiet"

    /// `--say`'s note while the app stands aside: nil for the usual "the
    /// HomeSpeaker extension is the one in use", which holds whenever the
    /// extension is chosen and installed; `inTheTrashNote` when the app
    /// stands aside only because it is in the Trash.
    public static func asideNote(record: DoorRecord?, fileExists: (String) -> Bool, bundlePath: String) -> String? {
        guard OtherDoorPresence.isInTrash(bundlePath + "/") else { return nil }
        return role(record: record, fileExists: fileExists).isQuiet ? nil : inTheTrashNote
    }

    /// Is the extension's chat monitor reading chat now? Only while its
    /// long-lived process holds its lock (`profile.liveLockURL`) and its
    /// status file says the monitor runs: a status left behind by a crash,
    /// with nobody holding the lock, does not count. Read, never written.
    public static func extensionReadsChat(_ profile: HomeSpeakerProfile) -> Bool {
        guard let lock = profile.liveLockURL, LiveLock.isHeld(at: lock) else { return false }
        return ChatMonitorStatusFile(url: profile.monitorStatusURL).read()?.isRunning == true
    }

    /// May the app start its chat monitor now that it runs (design 7.6,
    /// step 4)? Only once the extension is seen not reading chat: its
    /// lock not held, or its monitor stopped. A 1.19 extension stops its
    /// own within one look at the choice file (five seconds); until it is
    /// seen to, the app waits, so no message is read by both.
    public static func monitorMayStart(extensionReadsChat: Bool) -> Bool {
        !extensionReadsChat
    }

    /// The extension's sign-ins, while it is installed and runs without the
    /// app; nil otherwise. Read afresh.
    public static func otherSecrets(check: DoorCheck) -> Secrets? {
        let record = check.file.read()
        guard OtherDoorPresence.extensionInstalled(record: record, fileExists: check.fileExists),
              let profile = extensionProfile(record: record) else { return nil }
        return SecretStore(fileURL: profile.secretsURL).load()
    }

    /// The extension's files, from its block in the choice file: its data
    /// folder as written there, else worked out from its program. Nil when
    /// there is no block.
    public static func extensionProfile(record: DoorRecord?) -> HomeSpeakerProfile? {
        guard let entry = record?.installedExtension else { return nil }
        let folders = HomeSpeakerProfile.extensionFolders(program: URL(fileURLWithPath: entry.program))
        guard let data = entry.dataFolder.map({ URL(fileURLWithPath: $0, isDirectory: true) }) ?? folders?.data else {
            return nil
        }
        return .extension(dataFolder: data, toolFolder: folders?.tool)
    }
}

/// The app's side of the choice, while it runs: reads its role afresh on
/// each `refresh` (at launch, on a change in `~/.gemini`, on a timer), and
/// starts or stops what the role says. Its `monitor` is the chat monitor
/// every listener and button must use: a start is ignored while the app is
/// quiet.
@MainActor
public final class AppDoor: ObservableObject {
    /// What starting and stopping the parts does: the real ones in the app,
    /// recorded in a test.
    public struct Effects {
        public var repairHooks: @MainActor (HomeSpeakerProfile.Door?) -> Void
        public var startMonitorIfConfigured: @MainActor () -> Void
        public var stopMonitor: @MainActor () -> Void
        public var startListening: @MainActor () -> Void
        public var stopListening: @MainActor () -> Void

        public init(
            repairHooks: @escaping @MainActor (HomeSpeakerProfile.Door?) -> Void,
            startMonitorIfConfigured: @escaping @MainActor () -> Void,
            stopMonitor: @escaping @MainActor () -> Void,
            startListening: @escaping @MainActor () -> Void,
            stopListening: @escaping @MainActor () -> Void
        ) {
            self.repairHooks = repairHooks
            self.startMonitorIfConfigured = startMonitorIfConfigured
            self.stopMonitor = stopMonitor
            self.startListening = startListening
            self.stopListening = stopListening
        }
    }

    @Published public private(set) var plan: AppStartup.Plan
    /// The choice file as last read.
    @Published public private(set) var record: DoorRecord?
    /// The chat monitor, behind the role.
    public let monitor: GatedMonitor
    public let check: DoorCheck
    private let bundlePath: () -> String
    private let effects: Effects
    /// Is the extension's monitor reading chat (`AppStartup.extensionReadsChat`)?
    private let extensionReadsChat: (HomeSpeakerProfile) -> Bool
    /// Runs `work` again a moment later, while the monitor waits.
    private let later: (@escaping @MainActor () -> Void) -> Void
    /// What runs now, as started here; nothing until the first refresh.
    private var running = false
    /// Running, but the monitor waits for the extension to stop reading
    /// chat (design 7.6, step 4).
    @Published public private(set) var monitorWaiting = false
    /// A re-check is already asked for.
    private var recheckAsked = false
    /// The choice the hooks were last repaired for, while running.
    private var repairedFor: HomeSpeakerProfile.Door??

    /// `later` runs its work again a second later by default; a test runs
    /// it by hand.
    public init(
        check: DoorCheck, bundlePath: @escaping () -> String, monitor: any ChatMonitorControlling, effects: Effects,
        extensionReadsChat: @escaping (HomeSpeakerProfile) -> Bool = AppStartup.extensionReadsChat,
        later: @escaping (@escaping @MainActor () -> Void) -> Void = { work in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { work() } }
        }
    ) {
        self.check = check
        self.bundlePath = bundlePath
        self.effects = effects
        self.extensionReadsChat = extensionReadsChat
        self.later = later
        self.monitor = GatedMonitor(monitor)
        let record = check.file.read()
        self.record = record
        plan = AppStartup.plan(record: record, fileExists: check.fileExists, bundlePath: bundlePath())
    }

    /// Reads the role afresh and acts on a change. Going quiet stops the
    /// monitor and the listeners; becoming active starts them in today's
    /// order, after re-pointing the hooks for the choice. The monitor
    /// itself waits while the extension's still reads chat, and is started
    /// once it is seen to stop (design 7.6, step 4). A change of choice
    /// while running re-points the hooks again. Nothing changed: nothing is
    /// done.
    public func refresh() {
        let record = check.file.read()
        let new = AppStartup.plan(record: record, fileExists: check.fileExists, bundlePath: bundlePath())
        let runs = new.runs
        if !runs, running {
            effects.stopMonitor()
            effects.stopListening()
        }
        if runs {
            let choice = record?.chosen
            if !running || repairedFor != .some(choice) {
                effects.repairHooks(choice)
                repairedFor = .some(choice)
            }
            if !running { monitorWaiting = true }
            if monitorWaiting, AppStartup.monitorMayStart(extensionReadsChat: extensionReading(record)) {
                monitorWaiting = false
                monitor.permission.set(true)
                effects.startMonitorIfConfigured()
            }
            if !running { effects.startListening() }
        } else {
            repairedFor = nil
            monitorWaiting = false
        }
        monitor.permission.set(runs && !monitorWaiting)
        running = runs
        if monitorWaiting, !recheckAsked {
            recheckAsked = true
            later { [weak self] in
                self?.recheckAsked = false
                self?.refresh()
            }
        }
        if record != self.record { self.record = record }
        if new != plan { plan = new }
    }

    /// The extension's monitor reads chat, by its block in the choice file.
    private func extensionReading(_ record: DoorRecord?) -> Bool {
        guard let profile = AppStartup.extensionProfile(record: record) else { return false }
        return extensionReadsChat(profile)
    }

    /// The extension, when it is installed and runs without the app.
    public var extensionInstalled: Bool {
        OtherDoorPresence.extensionInstalled(record: record, fileExists: check.fileExists)
    }

    /// The extension's sign-ins, while it is installed: Sign Out never
    /// revokes a login it shares (design 7.7). Nil otherwise.
    public func otherSecrets() -> Secrets? {
        AppStartup.otherSecrets(check: check)
    }

    /// Signs the app out, by the one rule for both sides
    /// (`HomeSpeakerEngine.signOut`): a login the extension shares is
    /// removed here only, never revoked at Google.
    public func signOut(engine: HomeSpeakerEngine, chatOnly: Bool) async -> CLIOutput {
        await engine.signOut(chatOnly: chatOnly, otherSecrets: otherSecrets())
    }
}
