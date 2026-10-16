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
        let installed = OtherDoorPresence.extensionInstalled(record: record, fileExists: fileExists)
        let role = DoorRole.decide(me: .app, otherInstalled: installed, chosen: record?.chosen)
        return plan(role: role, inTrash: OtherDoorPresence.isInTrash(bundlePath + "/"))
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
    /// - `--sign-out` never revokes a login the extension shares.
    public static func commandLineParts(
        check: DoorCheck = DoorCheck(appInstalled: { false }),
        bundlePath: @escaping @Sendable () -> String = { Bundle.main.bundlePath },
        postSignedOut: @escaping @Sendable (_ chatOnly: Bool, Notification.Name) -> Void = {
            SignOutNotice.post(chatOnly: $0, name: $1)
        }
    ) -> HomeSpeakerCommandLine.Parts {
        .app(
            standsAside: { plan(check: check, bundlePath: bundlePath()).role.isQuiet },
            asideNote: { asideNote(record: check.file.read(), fileExists: check.fileExists, bundlePath: bundlePath()) },
            otherSecrets: { otherSecrets(check: check) },
            postSignedOut: postSignedOut)
    }

    /// What `--say` notes when the app is in the Trash and the extension is
    /// not the one in use (so "the extension is in use" would be untrue).
    public static let inTheTrashNote = "note: this copy of the HomeSpeaker app is in the Trash, so it stays quiet"

    /// `--say`'s note while the app stands aside: nil for the usual "the
    /// HomeSpeaker extension is the one in use", which holds whenever the
    /// extension is chosen and installed; `inTheTrashNote` when the app
    /// stands aside only because it is in the Trash.
    public static func asideNote(record: DoorRecord?, fileExists: (String) -> Bool, bundlePath: String) -> String? {
        let plan = plan(record: record, fileExists: fileExists, bundlePath: bundlePath)
        guard plan.inTrash else { return nil }
        let installed = OtherDoorPresence.extensionInstalled(record: record, fileExists: fileExists)
        let role = DoorRole.decide(me: .app, otherInstalled: installed, chosen: record?.chosen)
        return role.isQuiet ? nil : inTheTrashNote
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
    /// What runs now, as started here; nothing until the first refresh.
    private var running = false
    /// The choice the hooks were last repaired for, while running.
    private var repairedFor: HomeSpeakerProfile.Door??

    public init(
        check: DoorCheck, bundlePath: @escaping () -> String, monitor: any ChatMonitorControlling, effects: Effects
    ) {
        self.check = check
        self.bundlePath = bundlePath
        self.effects = effects
        self.monitor = GatedMonitor(monitor)
        let record = check.file.read()
        self.record = record
        plan = AppStartup.plan(record: record, fileExists: check.fileExists, bundlePath: bundlePath())
    }

    /// Reads the role afresh and acts on a change. Going quiet stops the
    /// monitor and the listeners; becoming active starts them in today's
    /// order, after re-pointing the hooks for the choice. A change of
    /// choice while running re-points them again. Nothing changed: nothing
    /// is done.
    public func refresh() {
        let record = check.file.read()
        let new = AppStartup.plan(record: record, fileExists: check.fileExists, bundlePath: bundlePath())
        let runs = new.runs
        monitor.permission.set(runs)
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
            if !running {
                effects.startMonitorIfConfigured()
                effects.startListening()
            }
        } else {
            repairedFor = nil
        }
        running = runs
        if record != self.record { self.record = record }
        if new != plan { plan = new }
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
