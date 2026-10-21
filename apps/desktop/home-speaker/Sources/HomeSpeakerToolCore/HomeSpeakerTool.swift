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
import HomeSpeakerCore
import VitruvianToolKit
import VitruvianToolProtocol

/// The app, as the tool's core reaches it. The program answers each over
/// the kit; the tests record.
public protocol ToolLink: AnyObject {
    func render(panel: String, _ tree: UITree)
    func showMessage(_ message: String, icon: String)
    func log(_ message: String)
    func clipboardText() -> String?
    /// Whether the app named this feature in its hello: something a later
    /// protocol release added, such as the `choice` block. By its name on
    /// the link, so a feature newer than the kit HomeSpeaker builds
    /// against can still be asked about (`HomeSpeakerTool.openSettingsFeature`).
    func supports(featureNamed name: String) -> Bool
}

extension ToolLink {
    /// Whether the app has a feature the kit names.
    public func supports(_ feature: ProtocolFeature) -> Bool { supports(featureNamed: feature.rawValue) }
}

/// What the tool is: HomeSpeaker's settings file, HomeSpeaker's program,
/// and the app, tied together. Everything a handler of the kit's does
/// comes here, on the kit's thread; a job's end comes back through
/// `Parts.later`, which the program hands to the kit's thread. That hop is
/// the one place the tool is named from another thread, and nothing of it
/// is read there: hence `@unchecked Sendable`.
public final class HomeSpeakerTool: @unchecked Sendable {
    public static let islandPanel = "speaker"
    public static let settingsPanel = "settings"
    /// The hello's name for "an answer's `open` may name the tool's own
    /// settings panel" (Vitruvian 3.58 and later). Held here as text, not
    /// as `ProtocolFeature.openSettings`: the SwiftPM build, which is what
    /// ships, uses the published kit, and that case first comes with kit
    /// 1.6.0. The kit's `supports` takes the name as text in every 1.x.
    public static let openSettingsFeature = "ui.open.settings"

    public enum Command {
        public static let sayClipboard = "sayClipboard"
        public static let toggleBroadcasting = "toggleBroadcasting"
        public static let mute = "mute"
        public static let unmute = "unmute"
        public static let toggleQuietHours = "toggleQuietHours"
        public static let all = [sayClipboard, toggleBroadcasting, mute, unmute, toggleQuietHours]
    }

    public struct Parts {
        public var link: ToolLink
        public var store: ConfigStore
        public var driver: SpeakerDriver
        /// Runs work on the kit's thread, from any thread.
        public var later: @Sendable (@escaping @Sendable () -> Void) -> Void
        public var now: () -> Date
        /// The Google Home sign-in: whether there is one, never its tokens.
        public var account: GoogleAccount
        /// The English voices installed on this Mac.
        public var voices: () -> [LocalVoice]
        /// Says `Pages.previewText` on this Mac in the voice with this id.
        public var previewVoice: @Sendable (String) async throws -> Void
        /// The Slack token and Google Chat access: whether there are any,
        /// never a token.
        public var chat: ChatCredentials
        /// Where the `gws` command is (`GwsChatClient.locate()`); nil when
        /// it is not installed.
        public var gwsLocation: () -> String?
        /// The process that runs this side's chat monitor is alive, so it
        /// reads messages: for the extension, its own `running.lock` is held
        /// (`HomeSpeakerProfile.ownerRunning()`).
        public var ownerRunning: () -> Bool
        /// Tells this HomeSpeaker's long-lived process that a login or token
        /// changed (`CredentialsChangedNotice`, under the profile's name),
        /// so it re-reads them and starts or restarts its chat monitor.
        public var credentialsChanged: () -> Void
        /// The home folder the coding agents keep their files in.
        public var home: URL
        /// Where HomeSpeaker's settings and secrets files are, for Files.
        public var settingsURL: URL
        public var secretsURL: URL
        /// The HomeSpeaker version Files shows: the engine this tool runs
        /// on. Nil when it does not say.
        public var homeSpeakerVersion: () -> String?
        /// Stops a launchd job (`AgentIntegration.launchctlBootout`); the
        /// tests record instead, so they never touch the live session.
        public var launchctlBootout: @Sendable (String) -> Void
        /// The shared broadcast history (`BroadcastHistory`) the island
        /// lists: by default beside the settings file, so a test's
        /// temporary settings never read this Mac's history.
        public var historyURL: URL
        /// What HomeSpeaker's chat monitor last wrote about itself
        /// (`ChatMonitorStatusFile`): by default beside the settings file,
        /// so a test's temporary settings never read this Mac's.
        public var monitorStatusURL: URL
        /// Starts or stops this side's chat monitor: for the extension, the
        /// one in its own process. The default does nothing, so a test never
        /// reaches a real monitor or a real running app.
        public var controlChatMonitor: (ChatMonitorAction) -> Void
        /// What this HomeSpeaker does now, given the other one and the
        /// person's choice (`DoorCheck.role(me:)`), asked afresh each time.
        public var role: () -> DoorRole
        /// The other HomeSpeaker, the app, as far as the extension needs it:
        /// whether it still runs. Nil when there is none to ask.
        public var other: (any OtherAppControlling)?
        /// The choice file (`~/.gemini/speaker_door.json`); nil in a test
        /// that has none.
        public var door: DoorFile?
        /// Copies one HomeSpeaker's settings and sign-ins into the other's
        /// (`DoorCopy.copy`).
        public var copy: (_ from: HomeSpeakerProfile, _ to: HomeSpeakerProfile) throws -> CopyReport
        /// Shows the mark on the closed island (`ui/status`). Called only
        /// when the app has it, and only with a mark that changed.
        public var sendStatus: (MarkChoice) -> Void
        /// Told when this side's chat monitor may start, and when it may no
        /// longer: the monitor's own triggers (its settings changing on
        /// disk, a sign-in, the control message) start nothing otherwise.
        public var monitorMayRun: (Bool) -> Void
        /// This HomeSpeaker's files, and the app's: what the choice card
        /// compares and copies (design 7.4, 7.5). Nil in a test that has
        /// none, and then nothing is compared or copied.
        public var profile: HomeSpeakerProfile?
        public var appProfile: HomeSpeakerProfile?
        /// The app's program as it is found now (`ProcessDriver.locate`),
        /// asked afresh at each switch: the agents' hooks are pointed at it
        /// when the person picks the app. Nil when there is none; a copy in
        /// the Trash is never used.
        public var appProgram: () -> URL?
        /// While this side runs, a HomeSpeaker hook left pointing at a
        /// program that is gone or in the Trash is pointed at this side's
        /// program. Only the extension's real parts turn it on: a test's
        /// default home is this Mac's.
        public var repairsHooks: Bool
        /// The app is installed (`DoorCheck.appInstalled`), for General's
        /// "Which HomeSpeaker" row.
        public var otherInstalled: () -> Bool
        /// Tells one HomeSpeaker its sign-ins changed, under that profile's
        /// own message names: after a copy, the side that took it (design
        /// 7.5). The default tells no one, so a test never posts.
        public var credentialsChangedIn: (HomeSpeakerProfile) -> Void
        /// What the engine said when it last put a speaker back after an
        /// announcement (`VolumeRestoreCoordinator.lastReport`).
        public var volumeRestoreReport: () -> String?

        public init(link: ToolLink, store: ConfigStore, driver: SpeakerDriver,
                    later: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void, now: @escaping () -> Date = Date.init,
                    account: GoogleAccount = NoGoogleAccount(), voices: @escaping () -> [LocalVoice] = { [] },
                    previewVoice: @escaping @Sendable (String) async throws -> Void = { _ in },
                    chat: ChatCredentials = NoChatCredentials(), gwsLocation: @escaping () -> String? = { nil },
                    ownerRunning: @escaping () -> Bool = { false }, credentialsChanged: @escaping () -> Void = {},
                    home: URL = FileManager.default.homeDirectoryForCurrentUser,
                    settingsURL: URL = ConfigManager.defaultConfigURL(), secretsURL: URL = SecretStore.defaultURL(),
                    homeSpeakerVersion: @escaping () -> String? = { nil },
                    launchctlBootout: @escaping @Sendable (String) -> Void = AgentIntegration.launchctlBootout,
                    historyURL: URL? = nil, monitorStatusURL: URL? = nil,
                    controlChatMonitor: @escaping (ChatMonitorAction) -> Void = { _ in },
                    role: @escaping () -> DoorRole = { .active }, other: (any OtherAppControlling)? = nil,
                    door: DoorFile? = nil,
                    copy: @escaping (HomeSpeakerProfile, HomeSpeakerProfile) throws -> CopyReport = DoorCopy.copy,
                    sendStatus: @escaping (MarkChoice) -> Void = { _ in },
                    monitorMayRun: @escaping (Bool) -> Void = { _ in },
                    profile: HomeSpeakerProfile? = nil, appProfile: HomeSpeakerProfile? = nil, appProgram: @escaping () -> URL? = { nil },
                    repairsHooks: Bool = false,
                    otherInstalled: @escaping () -> Bool = { false },
                    credentialsChangedIn: @escaping (HomeSpeakerProfile) -> Void = { _ in },
                    volumeRestoreReport: @escaping () -> String? = { nil }) {
            self.link = link
            self.store = store
            self.driver = driver
            self.later = later
            self.now = now
            self.account = account
            self.voices = voices
            self.previewVoice = previewVoice
            self.chat = chat
            self.gwsLocation = gwsLocation
            self.ownerRunning = ownerRunning
            self.credentialsChanged = credentialsChanged
            self.home = home
            self.settingsURL = settingsURL
            self.secretsURL = secretsURL
            self.homeSpeakerVersion = homeSpeakerVersion
            self.launchctlBootout = launchctlBootout
            self.historyURL = historyURL ?? Self.historyURL(beside: settingsURL)
            self.monitorStatusURL = monitorStatusURL ?? ChatMonitorStatusFile.url(beside: settingsURL)
            self.controlChatMonitor = controlChatMonitor
            self.role = role
            self.other = other
            self.door = door
            self.copy = copy
            self.sendStatus = sendStatus
            self.monitorMayRun = monitorMayRun
            self.profile = profile
            self.appProfile = appProfile
            self.appProgram = appProgram
            self.repairsHooks = repairsHooks
            self.otherInstalled = otherInstalled
            self.credentialsChangedIn = credentialsChangedIn
            self.volumeRestoreReport = volumeRestoreReport
        }

        /// `speaker_history.json` in the settings file's folder, where
        /// HomeSpeaker keeps it (`BroadcastHistory.defaultURL()`).
        public static func historyURL(beside settingsURL: URL) -> URL {
            settingsURL.deletingLastPathComponent().appendingPathComponent("speaker_history.json")
        }
    }

    public let parts: Parts
    public private(set) var config = SpeakerConfig()
    /// Why the settings file does not read, while it does not.
    public private(set) var configProblem: String?
    public private(set) var volume: Volume?
    /// The speaker job running: speaking, the volume, muting.
    public private(set) var busy: Job?
    /// The default speaker (its key) a volume or mute job was started
    /// for. HomeSpeaker reads the default when the job runs, so an answer
    /// for any other is the old speaker's and is not shown as the new one's.
    private var busyFor: String?
    /// A speaker job asked for while the volume was being read: it runs
    /// when the read ends, rather than being refused. The island reads the
    /// volume when it opens, and a pick made just after must not be lost
    /// to that read.
    public private(set) var waiting: Job?
    /// The default speaker `waiting` was asked for: a change of speaker
    /// meanwhile drops a waiting volume or mute, which was meant for the
    /// old one.
    private var waitingFor: String?
    /// A read of the volume is wanted as soon as the speaker slot is free:
    /// the speaker changed while a job ran. It reads whichever speaker is
    /// the default then, so a second change needs no second read.
    public private(set) var readPending = false
    /// When the default speaker's volume last came back.
    private var volumeReadAt: Date?
    /// The speaker (its key) `volume` was read for. The phone, the app or
    /// a hand edit can change the default without the island knowing; a
    /// reading for another speaker is then dropped, never shown as the
    /// new one's.
    private var volumeFor: String?
    /// The setup job running beside it: signing in or out, discovery, the
    /// login item, the media-pause test. Its own slot, so a browser sign-in
    /// that takes minutes never holds up speech or a mute.
    public private(set) var setupBusy: Job?
    public private(set) var notice: String?
    public private(set) var setupNotice: String?
    public private(set) var openPanels: Set<String> = []
    /// The settings section shown, kept across redraws. Only for an app
    /// that does not draw sections: one that does is sent every section.
    public private(set) var section = Pages.Section.general
    public private(set) var mediaPauseReport: String?
    public private(set) var homes: [HomeStructure]?
    public private(set) var selectedHomeId: String?
    public private(set) var previewing = false
    public private(set) var removingSpeakers = false
    /// The OAuth client typed under Google Cloud, held until Save. The
    /// secret is never drawn back into its field.
    public private(set) var draftClientId = ""
    public private(set) var draftClientSecret = ""
    /// The Slack and Beeper tokens and the Gemini key pasted and not saved
    /// yet, held until Save Token / Save Key (or Return). Never drawn back
    /// into their fields.
    public private(set) var draftSlackToken = ""
    public private(set) var draftBeeperToken = ""
    public private(set) var draftGeminiKey = ""
    private var voices: [LocalVoice]?
    /// Asked once each time Settings opens, so a failure is not asked again
    /// at every redraw.
    private var askedHomes = false
    /// The island's setup lists the homes once each time it opens.
    private var askedIslandHomes = false
    /// The chat monitor as last drawn, so a change the app writes is drawn
    /// and an unchanged one is not (`refreshMonitorStatus`), and a change
    /// of Beeper's network chips is saved against the networks drawn.
    private var drawnChat: Pages.Chat?
    /// The role as the last `refreshRole` found it; nil before the first.
    public private(set) var role: DoorRole?
    /// When this side last became one that runs, for the wait when no
    /// choice says when it was made.
    private var runsSince: Date?
    /// Whether this side's chat monitor may run, as last told
    /// (`Parts.monitorMayRun`).
    public private(set) var monitorMayRun = false
    /// The wait for the other side to stop its monitor is over for the
    /// role this side has now; cleared when the role changes.
    private var waitedForTheOther = false
    /// The mark as last sent, so an unchanged one is not sent again.
    private var sentMark: MarkChoice?
    /// The step of the choice card the person is on (design 7.4); nil
    /// before they tap it and once it is done.
    public private(set) var doorStep: Pages.DoorStep?
    /// What the last step did, a sentence each, until a page opens afresh.
    public private(set) var doorReport: [String] = []
    /// The app was opened when the person picked it, and has not been seen
    /// running since.
    public private(set) var otherStarting = false

    public init(parts: Parts) {
        self.parts = parts
    }

    /// Agent hooks as HomeSpeaker installs them, pointed at the HomeSpeaker
    /// program this tool located. Never at the tool's own `bin/tool`, which
    /// `AgentIntegration`'s default (the running program) would be here;
    /// nil when HomeSpeaker is not installed, so there is nothing to point at.
    public func agentIntegration(home: URL? = nil) -> AgentIntegration? {
        guard let program = parts.driver.program else { return nil }
        return AgentIntegration(home: home ?? parts.home, executablePath: program.path, bootout: parts.launchctlBootout)
    }

    /// The agents' state and the cleanup, which need no HomeSpeaker: the
    /// installing integration when there is one, so its own hook reads as
    /// installed, else one pointed at nothing, which reads every hook as
    /// not HomeSpeaker's current one and refuses to install any.
    public func agentStatusIntegration() -> AgentIntegration {
        agentIntegration() ?? AgentIntegration(home: parts.home, executablePath: "", bootout: parts.launchctlBootout)
    }

    // MARK: - The app's messages

    public func start() {
        reload()
        refreshRole()
        if readsVolume { try? run(.volume) }
        if !parts.driver.isInstalled { parts.link.log("HomeSpeaker is not installed: the tool can only show its settings") }
    }

    public func run(command: String) throws {
        switch command {
        case Command.sayClipboard:
            guard let text = parts.link.clipboardText()?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw CommandRefused("the clipboard holds no text")
            }
            try say(text)
        case Command.toggleBroadcasting:
            reload()
            config.enabled.toggle()
            try save()
            parts.link.showMessage(config.enabled ? "Broadcasting on" : "Broadcasting off", icon: "hifispeaker.2")
        case Command.toggleQuietHours:
            reload()
            config.quietHoursEnabled = !(config.quietHoursEnabled ?? false)
            try save()
            parts.link.showMessage(config.quietHoursEnabled == true ? "Quiet hours on" : "Quiet hours off", icon: "moon.zzz")
        case Command.mute: try speakerJob(.mute)
        case Command.unmute: try speakerJob(.unmute)
        default: throw CommandRefused("no such command")
        }
    }

    // MARK: - Panels

    public func islandPage() -> UITree {
        if !openPanels.contains(Self.islandPanel) {
            askedIslandHomes = false
            if doorStep == nil { doorReport = [] }
        }
        openPanels.insert(Self.islandPanel)
        reload()
        // An opening reads the volume again (the app asks for this page
        // only when the island or the menu bar panel opens it), so the
        // menu shows the level as it is now. Not within `volumeFreshFor`
        // of the last read: each read asks Google's Home API afresh, and
        // opening and closing quickly would ask it every time.
        if readsVolume, busy == nil, !volumeIsFresh { try? run(.volume) }
        listHomesForSetup()
        return Pages.island(status())
    }

    /// The volume is read only where it can answer: HomeSpeaker installed,
    /// a speaker picked, and Home speakers on. With them off a read would
    /// only wait on a Cast speaker nobody is using. A quiet side reads
    /// nothing.
    private var readsVolume: Bool {
        parts.driver.isInstalled && config.defaultDevice != nil && config.effectiveSpeakHome && !parts.role().isQuiet
    }

    /// How long a volume read stands before an opening reads it again.
    public static let volumeFreshFor: TimeInterval = 30

    private var volumeIsFresh: Bool {
        guard volume != nil, volumeFor == config.defaultTarget, let at = volumeReadAt else { return false }
        return parts.now().timeIntervalSince(at) < Self.volumeFreshFor
    }

    /// The level shown is no longer the default speaker's.
    private func forgetVolume() {
        volume = nil
        volumeReadAt = nil
        volumeFor = nil
    }

    /// The default speaker changed: its level is unknown, and a volume or
    /// mute waiting for the old one is dropped, and said to be.
    private func speakerChanged() {
        forgetVolume()
        if let job = waiting, job.controlsSpeaker {
            waiting = nil
            waitingFor = nil
            notice = Pages.pendingDropped
        }
    }

    /// Reads the new default's volume now, or once the slot is free.
    private func readVolumeSoon() {
        guard readsVolume else { return }
        if busy == nil {
            try? run(.volume, keepingNotice: true)
        } else {
            readPending = true
        }
    }

    /// Signed in with no speakers: the island's setup offers each home, so
    /// they are listed once an opening, in the setup slot.
    private func listHomesForSetup() {
        guard parts.driver.isInstalled, setupBusy == nil, homes == nil, !askedIslandHomes,
              config.targets.isEmpty, parts.account.isSignedIn else { return }
        askedIslandHomes = true
        try? setupJob(.app(.discover(save: false, home: nil)))
    }

    /// Settings' controls the island draws too, saved through `change`.
    /// Beeper's network switches are among them, by their id's shape.
    static let islandSettings: Set<String> = [
        Pages.Block.speechLength, Pages.Block.quietStart, Pages.Block.quietEnd, Pages.Block.beeperAnnounce,
        Pages.Block.beeperNetworks, Pages.Block.muteOwnMessages, Pages.Block.announcementStyle, Pages.Block.customStylePrompt,
    ]

    public func islandEvent(_ event: PanelEvent) -> PanelAnswer {
        if event.block == Pages.Block.moreSettings {
            // Settings opens on HomeSpeaker's detail; the island's page
            // stays as it is, so the answer carries no page. An app without
            // the feature never drew the button, and would only log an
            // `open` it cannot do: it gets none.
            guard event.kind == .tap, opensSettings else { return .keep }
            return .open(Self.settingsPanel)
        }
        if event.block == Pages.Block.openChatSettings {
            // As More settings…, but on Chats: where the chat
            // warning's fix is. An open panel is redrawn on that section.
            // With every section on one page there is none to pick, and
            // Settings opens at its top.
            guard event.kind == .tap, opensSettings else { return .keep }
            if !sendsEverySection { section = .monitor }
            removingSpeakers = false
            if openPanels.contains(Self.settingsPanel) { parts.link.render(panel: Self.settingsPanel, settingsTree()) }
            return .open(Self.settingsPanel)
        }
        if let answer = islandTokenEvent(event) { return answer }
        if doorEvent(event) {
            if openPanels.contains(Self.settingsPanel) { parts.link.render(panel: Self.settingsPanel, settingsTree()) }
            return .page(Pages.island(status()))
        }
        if let answer = islandSetupEvent(event) { return answer }
        do {
            switch event.block {
            case Pages.Block.say?:
                guard let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return .keep }
                try say(text)
            case Pages.Block.sayClipboard?:
                guard event.kind == .tap else { return .keep }
                try run(command: Command.sayClipboard)
            case Pages.Block.broadcasting?:
                guard let isOn = event.isOn else { return .keep }
                reload()
                config.enabled = isOn
                try save()
            case Pages.Block.quiet?:
                guard let isOn = event.isOn else { return .keep }
                reload()
                config.quietHoursEnabled = isOn
                try save()
            case Pages.Block.mute?:
                guard let isOn = event.isOn else { return .keep }
                try speakerJob(isOn ? .mute : .unmute)
            case Pages.Block.volume?:
                // The menu's pick or the typed level, both as text. The
                // menu's "—" (not read yet) and an empty field ask nothing.
                guard let text = event.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return .keep }
                guard let level = Int(text), (0...100).contains(level) else {
                    notice = "A volume is a whole number from 0 to 100"
                    return .page(Pages.island(status()))
                }
                guard level != volume?.percent else { return .keep }
                try speakerJob(.setVolume(level))
            case Pages.Block.speakers?:
                // The menu answers with the speaker's option as text, the
                // list with the row tapped: its key, or the stand-in for a
                // key that is not a protocol name (`Pages.Block.rowId`).
                guard let id = event.text ?? event.row, !id.isEmpty else { return .keep }
                reload()
                guard let key = Pages.Block.rowValue(id, among: config.targets.keys), key != config.defaultTarget else { return .keep }
                config.defaultTarget = key
                try save()
                speakerChanged()
                readVolumeSoon()
            case Pages.Block.outputHome?:
                guard let isOn = event.isOn else { return .keep }
                reload()
                config.effectiveSpeakHome = isOn
                try save()
                // A reading from before Home speakers went off is stale.
                forgetVolume()
            case Pages.Block.outputLocal?:
                guard let isOn = event.isOn else { return .keep }
                reload()
                config.effectiveSpeakLocal = isOn
                try save()
            case Pages.Block.outputPhone?:
                guard let isOn = event.isOn else { return .keep }
                reload()
                config.effectiveSpeakPhone = isOn
                try save()
            case Pages.Block.claudeCodeEnabled?, Pages.Block.antigravityEnabled?, Pages.Block.opencodeEnabled?:
                guard let isOn = event.isOn, let id = event.block, let agent = Pages.Block.agentEnabledAgent(id) else { return .keep }
                reload()
                config.setAnnounces(agent, isOn)
                try save()
            case Pages.Block.slackEnabled?, Pages.Block.googleChatEnabled?, Pages.Block.beeperEnabled?:
                // Saved, as Settings saves it: the engine follows the file
                // and starts, stops or restarts its monitor to match
                // (`ChatMonitorReconciliation`). The redraw reads the
                // monitor again, so a source that cannot run is warned
                // about at the top.
                guard let isOn = event.isOn else { return .keep }
                reload()
                switch event.block {
                case Pages.Block.slackEnabled?: config.effectiveChatMonitor.slackEnabled = isOn
                case Pages.Block.googleChatEnabled?: config.effectiveChatMonitor.googleChatEnabled = isOn
                default: config.effectiveChatMonitor.beeperEnabled = isOn
                }
                try save()
            case let id? where Self.islandSettings.contains(id) || Pages.Block.beeperNetworkKey(id) != nil:
                // Settings' own controls, saved as Settings saves them; an
                // open Settings is drawn again so it shows the same value.
                // A time that does not read is said here, not saved.
                reload()
                guard try change(event, picked: event.text ?? event.row) else { return .keep }
                try save()
                if openPanels.contains(Self.settingsPanel) { parts.link.render(panel: Self.settingsPanel, settingsTree()) }
                // Saved as it is typed, without a redraw that would move
                // the cursor; Return redraws.
                if Self.savesWhileTyping(event) { return .keep }
            case let id? where Pages.Block.replayBroadcastId(id) != nil:
                guard event.kind == .tap, let wanted = Pages.Block.replayBroadcastId(id) else { return .keep }
                try replay(wanted)
            default:
                return .keep
            }
        } catch {
            notice = Self.words(error)
        }
        return .page(Pages.island(status()))
    }

    /// The island's token fields, under a chat source switched on with no
    /// token: pasted and saved there, so the warning goes at once. Return
    /// saves what it carries; Save Token saves what was pasted. A change
    /// is only held: saving each keystroke would keep a half-typed token,
    /// and a redraw would wipe the field. Nothing typed clears nothing
    /// here: clearing is Settings' button. Nil for any other block.
    private func islandTokenEvent(_ event: PanelEvent) -> PanelAnswer? {
        guard let id = event.block, let secret = Secret(block: id) else { return nil }
        let typed: String
        switch (id == secret.field, event.kind) {
        case (true, .change):
            setDraft(secret, event.text ?? "")
            return .keep
        case (true, .submit):
            typed = event.text ?? draft(secret)
        case (false, .tap):
            typed = tokenToSave(secret)
        default:
            return .keep
        }
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notice = "Paste the \(secret.name) first"
            return .page(Pages.island(status()))
        }
        do {
            try save(secret, typed)
            notice = setupNotice
        } catch {
            notice = Self.words(error)
        }
        if openPanels.contains(Self.settingsPanel) { parts.link.render(panel: Self.settingsPanel, settingsTree()) }
        return .page(Pages.island(status()))
    }

    /// The island's first-run buttons: the same actions as Settings'
    /// Sign In, Import and Find Speakers. Nil for any other block. What
    /// goes wrong is said where setup speaks, under the steps.
    private func islandSetupEvent(_ event: PanelEvent) -> PanelAnswer? {
        guard let id = event.block, id.hasPrefix("setup.") else { return nil }
        reload()
        do {
            switch id {
            case Pages.Block.setupSignIn:
                try setupJob(.signIn(chatOnly: false))
            case Pages.Block.setupImportAntigravity:
                try importAntigravity()
            case Pages.Block.setupDiscover:
                try discover()
            default:
                guard let index = Pages.Block.setupDiscoverHomeIndex(id), let homes, index < homes.count else { return .keep }
                selectedHomeId = homes[index].id
                try discover()
            }
        } catch {
            setupNotice = Self.words(error)
        }
        return .page(Pages.island(status()))
    }

    public func settingsPage() -> UITree {
        if !openPanels.contains(Self.settingsPanel) {
            // Opened, not redrawn: what Settings reads once is read again.
            askedHomes = false
            if doorStep == nil { doorReport = [] }
            voices = nil
            draftClientId = parts.account.customOAuthClientId ?? ""
            draftClientSecret = ""
            draftSlackToken = ""
            draftBeeperToken = ""
            draftGeminiKey = ""
        }
        openPanels.insert(Self.settingsPanel)
        reload()
        return settingsTree()
    }

    public func settingsEvent(_ event: PanelEvent) -> PanelAnswer {
        if doorEvent(event) {
            if openPanels.contains(Self.islandPanel) { parts.link.render(panel: Self.islandPanel, Pages.island(status())) }
            return .page(settingsTree())
        }
        reload()
        // The value a picker answers with: a choice's as text, a list's as
        // the row tapped.
        let picked = event.text ?? event.row
        do {
            switch event.block {
            case Pages.Block.section?:
                // With every section on one page there is no picker: the
                // event comes from a page drawn before, and changes nothing.
                guard !sendsEverySection, let picked, let section = Pages.Section(rawValue: picked) else { return .keep }
                self.section = section
                removingSpeakers = false
                return .page(settingsTree())
            case Pages.Block.openGoogleCloud?:
                if !sendsEverySection { section = .googleCloud }
                removingSpeakers = false
                return .page(settingsTree())
            case Pages.Block.oauthClientId?:
                guard event.kind == .change || event.kind == .submit, let text = event.text else { return .keep }
                let wasEmpty = draftClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                draftClientId = text
                // Only Save's enabled state depends on it: a redraw for
                // every edit would also wipe a secret typed but not saved.
                guard wasEmpty != text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .keep }
            case Pages.Block.oauthClientSecret?:
                // The page always draws this field empty, so a redraw now
                // would wipe what was typed before Save.
                guard event.kind == .change || event.kind == .submit, let text = event.text else { return .keep }
                draftClientSecret = text
                return .keep
            case Pages.Block.saveOAuthClient?:
                try saveOAuthClient()
            case Pages.Block.clearOAuthClient?:
                try parts.account.clearOAuthClient()
                draftClientId = ""
                draftClientSecret = ""
                setupNotice = "OAuth client cleared"
            case Pages.Block.startChatMonitor?:
                try controlChatMonitor(.start)
            case Pages.Block.stopChatMonitor?:
                try controlChatMonitor(.stop)
            case Pages.Block.removeLegacyAgent?:
                try agentStatusIntegration().removeLegacyLaunchAgent()
                setupNotice = "Legacy launch agent removed"
            case Pages.Block.signIn?:
                try setupJob(.signIn(chatOnly: false))
            case Pages.Block.signOut?:
                try setupJob(.app(.signOut(chatOnly: false)))
            case Pages.Block.importAntigravity?:
                try importAntigravity()
            case Pages.Block.slackToken?:
                // A change is held for Save Token; the page draws the field
                // empty, so a redraw now would wipe it. Return saves what
                // it carries (nothing clears it), as before.
                if event.kind == .change {
                    draftSlackToken = event.text ?? ""
                    return .keep
                }
                guard event.kind == .submit, let text = event.text else { return .keep }
                try saveSlackToken(text)
                tokenSavedElsewhere()
            case Pages.Block.saveSlackToken?:
                guard event.kind == .tap else { return .keep }
                // Never a clear: an empty Save is a slip, not a request.
                let typed = tokenToSave(slack: true)
                guard !typed.isEmpty else {
                    throw CommandRefused("paste the Slack token first")
                }
                try saveSlackToken(typed)
                tokenSavedElsewhere()
            case Pages.Block.clearSlackToken?:
                try saveSlackToken("")
                tokenSavedElsewhere()
            case Pages.Block.beeperToken?:
                if event.kind == .change {
                    draftBeeperToken = event.text ?? ""
                    return .keep
                }
                guard event.kind == .submit, let text = event.text else { return .keep }
                try saveBeeperToken(text)
                tokenSavedElsewhere()
            case Pages.Block.saveBeeperToken?:
                guard event.kind == .tap else { return .keep }
                let typed = tokenToSave(slack: false)
                guard !typed.isEmpty else {
                    throw CommandRefused("paste the Beeper token first")
                }
                try saveBeeperToken(typed)
                tokenSavedElsewhere()
            case Pages.Block.clearBeeperToken?:
                try saveBeeperToken("")
                tokenSavedElsewhere()
            case Pages.Block.geminiApiKey?:
                if event.kind == .change {
                    draftGeminiKey = event.text ?? ""
                    return .keep
                }
                guard event.kind == .submit, let text = event.text else { return .keep }
                try saveGeminiKey(text)
                tokenSavedElsewhere()
            case Pages.Block.saveGeminiApiKey?:
                guard event.kind == .tap else { return .keep }
                let typed = tokenToSave(.gemini)
                guard !typed.isEmpty else {
                    throw CommandRefused("paste the Gemini API key first")
                }
                try saveGeminiKey(typed)
                tokenSavedElsewhere()
            case Pages.Block.clearGeminiApiKey?:
                try saveGeminiKey("")
                tokenSavedElsewhere()
            case Pages.Block.customStylePrompt?:
                guard try saveSetting(event, picked: picked) else { return .keep }
                if Self.savesWhileTyping(event) { return .keep }
            case Pages.Block.grantChat?:
                try setupJob(.signIn(chatOnly: true))
            case Pages.Block.disconnectChat?:
                try setupJob(.app(.signOut(chatOnly: true)))
            case Pages.Block.testMediaPause?:
                mediaPauseReport = nil
                try setupJob(.app(.testMediaPause))
            case Pages.Block.discover?:
                try discover()
            case Pages.Block.home?:
                guard let home = Pages.Block.rowValue(picked, among: homes?.map(\.id) ?? []) else { return .keep }
                selectedHomeId = home
            case Pages.Block.editSpeakers?:
                removingSpeakers.toggle()
            case Pages.Block.previewVoice?:
                preview()
            case Pages.Block.broadcasting?, Pages.Block.speechLength?, Pages.Block.speakHome?, Pages.Block.homeCastVoice?,
                 Pages.Block.speakLocal?,
                 Pages.Block.speakPhone?, Pages.Block.phonePauseMedia?, Pages.Block.phoneHeadphonesOnly?,
                 Pages.Block.announceVolume?, Pages.Block.announceLevel?, Pages.Block.pauseMedia?, Pages.Block.pauseExtra?,
                 Pages.Block.quiet?, Pages.Block.quietStart?, Pages.Block.quietEnd?, Pages.Block.targets?, Pages.Block.voice?,
                 Pages.Block.slackEnabled?, Pages.Block.googleChatEnabled?, Pages.Block.chatSource?, Pages.Block.gwsAccount?,
                 Pages.Block.beeperEnabled?, Pages.Block.beeperAnnounce?, Pages.Block.beeperNetworks?,
                 Pages.Block.muteOwnMessages?, Pages.Block.pollInterval?,
                 Pages.Block.claudeCodeEnabled?, Pages.Block.antigravityEnabled?, Pages.Block.opencodeEnabled?,
                 Pages.Block.announcementStyle?, Pages.Block.styleModel?, Pages.Block.localEngine?, Pages.Block.geminiVoice?:
                guard try saveSetting(event, picked: picked) else { return .keep }
            case let id? where Pages.Block.beeperNetworkKey(id) != nil:
                // A Beeper network's switch, saved as the others are.
                guard try saveSetting(event, picked: picked) else { return .keep }
            case let id?:
                guard let (action, agent) = Pages.Block.agentAction(id) else { return .keep }
                try agentAction(action, agent)
            default:
                return .keep
            }
        } catch {
            setupNotice = Self.words(error)
        }
        return .page(settingsTree())
    }

    /// Starts or stops this side's monitor. The page says Running once the
    /// monitor has written that it is; the request alone changes nothing on
    /// it. Refused while the other HomeSpeaker is in use: its monitor is the
    /// one that runs. Start is refused, too, while nobody has picked: the
    /// app may be running its own.
    private func controlChatMonitor(_ action: ChatMonitorAction) throws {
        switch parts.role() {
        case .quiet(let other):
            throw CommandRefused("The HomeSpeaker \(other.rawValue) is in use, so its monitor is the one that runs")
        case .waitingAsking where action == .start:
            throw CommandRefused(Self.pickFirst)
        case .active, .activeAsking, .waitingAsking:
            break
        }
        if action == .start, !config.effectiveChatMonitor.anySourceEnabled {
            throw CommandRefused("turn on Slack, Google Chat or Beeper first")
        }
        parts.controlChatMonitor(action)
        setupNotice = "Asked HomeSpeaker to \(action.rawValue) the chat monitor"
    }

    /// What a settings field that will not take a value says.
    public enum Invalid {
        public static let quietHour = "Quiet hours take a time as HH:mm, such as 22:00"
        public static let announceLevel = "The announcement volume is a whole number from 0 to 100"
        public static let pauseExtra = "Resume after is a number of seconds from 0 to 10"
        public static let pollInterval =
            "The poll interval is a whole number of seconds from \(ChatMonitorConfig.minPollInterval) to \(ChatMonitorConfig.maxPollInterval)"
        public static let all = [quietHour, announceLevel, pauseExtra, pollInterval]
    }

    /// Saves the typed client in one write. A secret left untyped keeps
    /// the one already saved for the same id; a new id drops it, so a
    /// client is never paired with another client's secret.
    private func saveOAuthClient() throws {
        let id = draftClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw CommandRefused("type the Client ID first") }
        let secret = draftClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        try parts.account.saveOAuthClient(id: id, secret: secret.isEmpty ? nil : secret)
        draftClientId = id
        draftClientSecret = ""
        setupNotice = "OAuth client saved. Sign in from General to use it"
    }

    /// What an AI Agents button does. Only installing needs HomeSpeaker,
    /// since a hook runs it; the rest work on the files alone.
    private func agentAction(_ action: Pages.Block.AgentAction, _ agent: CodingAgent) throws {
        let name = agent.displayName
        switch action {
        case .installHook:
            if case .quiet(let other) = parts.role() {
                throw CommandRefused("The HomeSpeaker \(other.rawValue) is in use, so its hooks are the ones that run")
            }
            guard let integration = agentIntegration() else { throw CommandRefused("HomeSpeaker is not installed") }
            try integration.installHook(for: agent)
            setupNotice = "\(name) \(agent.hookKind) installed"
        case .removeHook:
            try agentStatusIntegration().removeHook(for: agent)
            setupNotice = "\(name) \(agent.hookKind) removed"
        case .disableRival:
            try agentStatusIntegration().disableRivalHook(for: agent)
            setupNotice = "Disabled the duplicate hook; replies are announced once now"
        case .addInstruction:
            try agentStatusIntegration().addBroadcastInstruction(for: agent)
            setupNotice = "Instruction added to \(agent.instructionFileName)"
        }
    }

    /// A Settings control's change, applied and saved. A value out of
    /// range throws, and is said under the section instead of being
    /// dropped or quietly clamped; false when the event changes nothing.
    private func saveSetting(_ event: PanelEvent, picked: String?) throws -> Bool {
        guard try change(event, picked: picked) else { return false }
        do {
            try save()
            if let notice = setupNotice, Invalid.all.contains(notice) { setupNotice = nil }
        } catch {
            parts.link.log("the settings could not be saved: \(error)")
            reload()
        }
        return true
    }

    /// Applies a settings change to `config`. False when the event changes
    /// nothing, so nothing is saved; throws, changing nothing, when a field
    /// holds a value the setting cannot take.
    private func change(_ event: PanelEvent, picked: String?) throws -> Bool {
        switch event.block {
        case Pages.Block.broadcasting?:
            guard let isOn = event.isOn else { return false }
            config.enabled = isOn
        case Pages.Block.speechLength?:
            guard let picked, let length = SpeechLength(rawValue: picked) else { return false }
            config.effectiveSpeechLength = length
        case Pages.Block.announcementStyle?:
            guard let picked, let style = AnnouncementStyle(rawValue: picked) else { return false }
            guard style != config.effectiveAnnouncementStyle else { return false }
            config.effectiveAnnouncementStyle = style
        case Pages.Block.customStylePrompt?:
            guard let text = event.text else { return false }
            guard text != (config.customStylePrompt ?? "") else { return false }
            config.customStylePrompt = text
        case Pages.Block.styleModel?:
            guard let picked, let model = StyleModel(rawValue: picked) else { return false }
            guard model != config.effectiveStyleModel else { return false }
            config.effectiveStyleModel = model
        case Pages.Block.localEngine?:
            guard let picked, let engine = LocalVoiceEngine(rawValue: picked) else { return false }
            guard engine != config.effectiveLocalEngine else { return false }
            config.effectiveLocalEngine = engine
        case Pages.Block.geminiVoice?:
            // One of the voices drawn: those offered, and the one saved.
            let drawn = GeminiVoice.allCases.map(\.rawValue) + [config.effectiveGeminiVoice]
            guard let picked, drawn.contains(picked), picked != config.effectiveGeminiVoice else { return false }
            config.effectiveGeminiVoice = picked
        case Pages.Block.speakHome?:
            guard let isOn = event.isOn else { return false }
            config.effectiveSpeakHome = isOn
        case Pages.Block.homeCastVoice?:
            guard let isOn = event.isOn else { return false }
            config.effectiveHomeCastVoice = isOn
        case Pages.Block.speakLocal?:
            guard let isOn = event.isOn else { return false }
            config.effectiveSpeakLocal = isOn
        case Pages.Block.speakPhone?:
            guard let isOn = event.isOn else { return false }
            config.effectiveSpeakPhone = isOn
        case Pages.Block.phonePauseMedia?:
            guard let isOn = event.isOn else { return false }
            config.effectivePhonePauseMedia = isOn
        case Pages.Block.phoneHeadphonesOnly?:
            guard let isOn = event.isOn else { return false }
            config.effectivePhoneHeadphonesOnly = isOn
        case Pages.Block.announceVolume?:
            guard let isOn = event.isOn else { return false }
            config.effectiveAnnounceVolumeEnabled = isOn
        case Pages.Block.announceLevel?:
            guard let text = event.text else { return false }
            guard let level = Int(text.trimmingCharacters(in: .whitespaces)), (0...100).contains(level) else {
                throw CommandRefused(Invalid.announceLevel)
            }
            config.effectiveAnnounceVolume = level
        case Pages.Block.pauseMedia?:
            guard let isOn = event.isOn else { return false }
            config.effectivePauseMedia = isOn
        case Pages.Block.pauseExtra?:
            guard let text = event.text else { return false }
            guard let seconds = Double(text.trimmingCharacters(in: .whitespaces)), seconds.isFinite, (0...10).contains(seconds) else {
                throw CommandRefused(Invalid.pauseExtra)
            }
            config.effectivePauseMediaExtraSeconds = seconds.rounded()
        case Pages.Block.quiet?:
            guard let isOn = event.isOn else { return false }
            config.quietHoursEnabled = isOn
        case Pages.Block.quietStart?, Pages.Block.quietEnd?:
            guard let text = event.text else { return false }
            guard let hour = SpeakerConfig.quietHour(text) else { throw CommandRefused(Invalid.quietHour) }
            if event.block == Pages.Block.quietStart {
                config.quietHoursStart = hour
            } else {
                config.quietHoursEnd = hour
            }
        case Pages.Block.targets?:
            guard let key = Pages.Block.rowValue(event.row, among: config.targets.keys) else { return false }
            let before = config.defaultTarget
            if removingSpeakers {
                config.removeTarget(key)
                if config.targets.isEmpty { removingSpeakers = false }
            } else {
                guard before != key else { return false }
                config.defaultTarget = key
            }
            // The island's reading was the old default's.
            if config.defaultTarget != before { speakerChanged() }
        case Pages.Block.voice?:
            // One of the voices drawn: those installed, and the one saved.
            let drawn = (voices ?? parts.voices()).map(\.id) + [config.effectiveLocalVoice]
            guard let voice = Pages.Block.rowValue(picked, among: drawn), !voice.isEmpty else { return false }
            config.effectiveLocalVoice = voice
        // Chats: the app follows the file and starts, stops or
        // restarts its monitor to match (ChatMonitorReconciliation).
        case Pages.Block.slackEnabled?:
            guard let isOn = event.isOn else { return false }
            config.effectiveChatMonitor.slackEnabled = isOn
        case Pages.Block.googleChatEnabled?:
            guard let isOn = event.isOn else { return false }
            config.effectiveChatMonitor.googleChatEnabled = isOn
        case Pages.Block.chatSource?:
            guard let picked, let source = ChatMonitorConfig.GoogleChatSource(rawValue: picked) else { return false }
            config.effectiveChatMonitor.googleChatSource = source
        case Pages.Block.gwsAccount?:
            guard let text = event.text else { return false }
            config.effectiveChatMonitor.gwsAccount = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case Pages.Block.beeperEnabled?:
            guard let isOn = event.isOn else { return false }
            config.effectiveChatMonitor.beeperEnabled = isOn
        case Pages.Block.beeperAnnounce?:
            guard let picked, let mode = ChatMonitorConfig.BeeperAnnounce(rawValue: picked) else { return false }
            config.effectiveChatMonitor.beeperAnnounce = mode
        case Pages.Block.claudeCodeEnabled?, Pages.Block.antigravityEnabled?, Pages.Block.opencodeEnabled?:
            guard let isOn = event.isOn, let id = event.block, let agent = Pages.Block.agentEnabledAgent(id) else { return false }
            config.setAnnounces(agent, isOn)
        case Pages.Block.muteOwnMessages?:
            guard let isOn = event.isOn else { return false }
            config.effectiveChatMonitor.muteOwnMessages = isOn
        case let id? where Pages.Block.beeperNetworkKey(id) != nil:
            // Off mutes the network, on reads it again. Read at the
            // monitor's next poll, without a restart. A switch already
            // where it is put saves nothing, and a network HomeSpeaker
            // reads itself (drawn greyed) is never muted: an app may
            // ignore a toggle's `enabled`.
            guard let isOn = event.isOn, let key = Pages.Block.beeperNetworkKey(id) else { return false }
            if !isOn, beeperNetworksListed()?.contains(where: { $0.key == key && $0.state == .skipped }) == true {
                return false
            }
            let before = config.effectiveChatMonitor.beeperMutedNetworks
            config.effectiveChatMonitor.setBeeperNetwork(key, reading: isOn)
            return config.effectiveChatMonitor.beeperMutedNetworks != before
        case Pages.Block.beeperNetworks?:
            // The chips of an app that draws them: every network whose chip
            // is off is muted, as its switch would be, and the same values
            // again save nothing. Against the networks as last drawn, not
            // as listed now: one Beeper lists after the page was drawn was
            // never shown, so it stays announced until James mutes it, and
            // one it stops listing keeps its tap. A network HomeSpeaker now
            // reads itself is still never muted, as for a switch.
            guard let values = event.values else { return false }
            let drawn = drawnChat.flatMap { $0.monitorRunning ? $0.monitor?.beeperNetworkStates : nil }
            let skippedNow = Set((beeperNetworksListed() ?? []).filter { $0.state == .skipped }.map(\.key))
            let rows = BeeperNetworkList(listed: drawn, muted: config.effectiveChatMonitor.beeperMutedNetworks).rows
                .map { row -> BeeperNetworkState in
                    var row = row
                    if skippedNow.contains(row.key) { row.state = .skipped }
                    return row
                }
            return Pages.saveBeeperNetworkChips(values, rows: rows, into: &config.effectiveChatMonitor)
        case Pages.Block.pollInterval?:
            guard let text = event.text else { return false }
            guard let seconds = Int(text.trimmingCharacters(in: .whitespaces)),
                  (ChatMonitorConfig.minPollInterval...ChatMonitorConfig.maxPollInterval).contains(seconds) else {
                throw CommandRefused(Invalid.pollInterval)
            }
            config.effectiveChatMonitor.pollIntervalSeconds = seconds
        default:
            return false
        }
        return true
    }

    /// The networks the running monitor last listed, as the pages draw
    /// them (`Pages.beeperNetworksRead`); nil while it is not running or
    /// has not read Beeper.
    private func beeperNetworksListed() -> [BeeperNetworkState]? {
        let chat = chatStatus()
        return chat.monitorRunning ? chat.monitor?.beeperNetworkStates : nil
    }

    public func panelClosed(_ panel: String) {
        openPanels.remove(panel)
    }

    // MARK: - Which HomeSpeaker runs

    /// How long a side that has just become the one in use waits for the
    /// other to stop its chat monitor before starting its own (design 7.6).
    public static let otherStopsWithin: TimeInterval = 5

    /// What a refusal says while nobody has picked a HomeSpeaker.
    public static let pickFirst = "Pick which HomeSpeaker to use first"
    /// What `say` says with nowhere to speak.
    public static let notSetUp = "Set up HomeSpeaker first: pick a speaker, or turn on This Mac"

    /// Reads the settings and the role afresh (the choice file, and whether
    /// the other is installed) and acts on a change: the chat monitor may
    /// run only while this side runs, and, once it does, only after the
    /// other has stopped or `otherStopsWithin` has passed since the choice
    /// was written. That wait is over once it has passed for this role: a
    /// choice written again later (the same side, a newer time) does not
    /// stop a monitor that runs. Then the pages are drawn again and the
    /// mark sent, from the settings as they are on disk now (a copy into
    /// this side, or `--discover`, may have changed them with no page
    /// open). Asked at start and on the five-second tick.
    public func refreshRole() {
        reload()
        let now = parts.now()
        let role = parts.role()
        let changed = role != self.role
        let runs = Self.runs(role)
        if changed {
            if !runs {
                runsSince = nil
            } else if !(self.role.map(Self.runs) ?? false) {
                runsSince = now
            }
            waitedForTheOther = false
            self.role = role
        }
        if changed, case .compare(let compare)? = doorStep, choiceChanged(since: compare) {
            // Picked elsewhere, in the app: the step is stale.
            doorStep = nil
            doorReport = [Pages.DoorWords.choiceChanged]
        }
        if otherStarting, parts.other?.isRunning ?? true || !role.isQuiet { otherStarting = false }
        var mayRun = false
        if runs {
            if parts.repairsHooks { repairStrandedHooks() }
            let otherRunning = parts.other?.isRunning ?? false
            // Only an app that is found: with none (a test's
            // `HOMESPEAKER_PROGRAM=""`), there is nothing to wait for or quit.
            let appFound = parts.appProgram() != nil
            // An app older than 1.19 never hears the choice and keeps its
            // own monitor: this side's waits until it has quit, however
            // long that takes (design 7.6, item 4). A newer one goes quiet
            // by itself, so five seconds is the most this side waits, once
            // for each time this side comes to run.
            let waited = waitedForTheOther || !otherRunning || {
                let since = parts.door?.read()?.chosenAt ?? runsSince ?? now
                return now.timeIntervalSince(since) >= Self.otherStopsWithin
            }()
            mayRun = !(otherRunning && appFound && Self.isOld(parts.other)) && waited
            if mayRun { waitedForTheOther = true }
        }
        if mayRun != monitorMayRun {
            monitorMayRun = mayRun
            parts.monitorMayRun(mayRun)
            if mayRun {
                // As the app does at launch: only a monitor switched on.
                if config.effectiveChatMonitor.anySourceEnabled { parts.controlChatMonitor(.start) }
            } else {
                parts.controlChatMonitor(.stop)
            }
        }
        if changed || drawnStarting != otherStarting { refreshOpenPanels() }
        drawnStarting = otherStarting
        updateMark()
    }

    /// Whether the open pages last showed the app as starting.
    private var drawnStarting = false

    /// An app that cannot hear the choice file: older than 1.19, or of a
    /// version that does not read.
    private static func isOld(_ other: (any OtherAppControlling)?) -> Bool {
        guard let other else { return false }
        return OtherAppVersion.isOlder(other.version, than: OtherAppPlan.hearsTheChoiceSince)
    }

    /// Points a HomeSpeaker hook stranded on a program that is gone or in
    /// the Trash (the app dragged there by hand, say) at this side's own
    /// program, re-points a hook when the extension is explicitly chosen, or
    /// refreshes an older plugin file that already points at this program
    /// after an update, so the replies are spoken again. When nobody has
    /// chosen (`choice == nil`), a hook that runs another program that is
    /// there is left alone, as is one that is not HomeSpeaker's program.
    private func repairStrandedHooks() {
        guard let program = parts.driver.program,
              !OtherDoorPresence.isInTrash(program.path),
              !OtherDoorPresence.isOnTemporaryVolume(program.path) else { return }
        let choice = parts.door?.read()?.chosen
        let integration = AgentIntegration(home: parts.home, executablePath: program.path, bootout: parts.launchctlBootout)
        for agent in CodingAgent.allCases where agent.supportsHook {
            let status = integration.status(of: agent)
            guard case .stale = status.hook, let runs = status.hookProgram, AgentIntegration.isHomeSpeakerProgram(runs),
                  runs == program.path || choice == .extension || OtherDoorPresence.isInTrash(runs) || !FileManager.default.fileExists(atPath: runs) else { continue }
            do {
                try integration.installHook(for: agent)
            } catch {
                parts.link.log("the \(agent.displayName) hook could not be pointed at this HomeSpeaker: \(error.localizedDescription)")
            }
        }
    }

    /// A side that runs: the hook, the chat monitor, listening.
    private static func runs(_ role: DoorRole) -> Bool {
        switch role {
        case .active, .activeAsking: return true
        case .waitingAsking, .quiet: return false
        }
    }

    /// What the mark is worked out from (`IslandStatus.mark`). Set up means
    /// something to speak with: a Google sign-in, a default speaker, or
    /// this Mac's speech on (design 6, "not set up").
    public func statusInputs() -> StatusInputs {
        let monitorProblem = config.effectiveChatMonitor.anySourceEnabled
            ? Pages.Chat(ownerRunning: parts.ownerRunning(),
                         monitor: ChatMonitorStatusFile(url: parts.monitorStatusURL).read()).runtimeError
            : nil
        let speaking = busy?.spokenText != nil
        return StatusInputs(
            role: role ?? parts.role(),
            monitorProblem: monitorProblem,
            setUp: parts.account.isSignedIn || config.defaultDevice != nil || config.effectiveSpeakLocal || config.effectiveSpeakPhone,
            speaking: speaking,
            quietUntil: config.isInQuietHours(at: parts.now()) ? config.quietHoursEnd : nil,
            broadcasting: config.enabled,
            defaultSpeaker: config.defaultDevice?.name)
    }

    /// Sends the mark when it changed, to an app that shows one.
    private func updateMark() {
        guard parts.link.supports(.status) else { return }
        let mark = IslandStatus.mark(statusInputs())
        guard mark != sentMark else { return }
        sentMark = mark
        parts.sendStatus(mark)
    }

    /// Draws the open pages again when what the chat monitor says about
    /// itself has changed since they were drawn: a Start pressed here shows
    /// Running once the app has started, without another tap. Asked on a
    /// timer; reads nothing unless a page that shows the monitor is open.
    public func refreshMonitorStatus() {
        let settingsShowsIt = openPanels.contains(Self.settingsPanel) && settingsShows(.monitor)
        let islandShowsIt = openPanels.contains(Self.islandPanel) && config.effectiveChatMonitor.anySourceEnabled
        guard settingsShowsIt || islandShowsIt else { return }
        reload()
        guard chatStatus() != drawnChat else { return }
        refreshOpenPanels()
    }

    // MARK: - The choice card

    /// This HomeSpeaker: the extension, for the tool.
    private var me: HomeSpeakerProfile.Door { parts.profile?.door ?? .extension }

    /// Which HomeSpeaker is in use, read afresh, and the step the person is on.
    private func doorState(role: DoorRole? = nil) -> Pages.DoorState {
        let role = role ?? parts.role()
        let oldAppRunning = Self.runs(role) && parts.appProgram() != nil && (parts.other?.isRunning ?? false)
            && Self.isOld(parts.other)
        return Pages.DoorState(me: me, role: role, otherInstalled: parts.otherInstalled(), step: doorStep, report: doorReport,
                               oldAppRunning: oldAppRunning, otherStarting: otherStarting)
    }

    /// The app's program as it is found now; never a copy in the Trash.
    private func appProgramNow() -> URL? {
        guard let program = parts.appProgram(), !OtherDoorPresence.isInTrash(program.path) else { return nil }
        return program
    }

    /// The choice file no longer says what it did when `compare` began.
    private func choiceChanged(since compare: Pages.DoorCompare) -> Bool {
        let record = parts.door?.read()
        return record?.chosen != compare.seenChoice || record?.chosenAt != compare.seenChosenAt
    }

    private static func other(of door: HomeSpeakerProfile.Door) -> HomeSpeakerProfile.Door {
        door == .app ? .extension : .app
    }

    /// The card's buttons and toggles, on either page (design 7.4 and 7.7).
    /// False for any other block. What goes wrong is said on the card.
    private func doorEvent(_ event: PanelEvent) -> Bool {
        guard let id = event.block, id.hasPrefix(Pages.Block.doorPrefix) else { return false }
        do {
            switch id {
            case Pages.Block.doorUseExtension: try compare(choosing: .extension)
            case Pages.Block.doorUseApp: try compare(choosing: .app)
            case Pages.Block.doorBack:
                // Nothing is committed before Copy or Keep.
                if case .compare? = doorStep { doorStep = nil }
            case Pages.Block.doorQuitAgain: quitAgain()
            case Pages.Block.doorUseThis: try compare(choosing: me)
            case Pages.Block.doorSwitch:
                guard let inUse = doorState().inUse else { return true }
                try compare(choosing: Self.other(of: inUse))
            case Pages.Block.doorCopyAgain:
                guard let inUse = doorState().inUse else { return true }
                try compare(from: Self.other(of: inUse), into: inUse, purpose: .copyOnly)
            case Pages.Block.doorCopy: finishCompare(copy: true)
            case Pages.Block.doorKeep: finishCompare(copy: false)
            case Pages.Block.doorLoginItem, Pages.Block.doorTrash:
                guard case .offers(var offers) = doorStep, !offers.working, let isOn = event.isOn else { return true }
                if id == Pages.Block.doorTrash {
                    offers.trash = isOn
                } else if offers.loginItemOptional {
                    offers.loginItem = isOn
                }
                doorStep = .offers(offers)
            case Pages.Block.doorDone: closeOffers()
            default: break
            }
        } catch {
            doorReport = [Self.words(error)]
        }
        return true
    }

    private func profile(_ door: HomeSpeakerProfile.Door) throws -> HomeSpeakerProfile {
        guard let profile = door == me ? parts.profile : parts.appProfile else {
            throw CommandRefused("the \(door.rawValue)'s files are not known here, so nothing can be compared")
        }
        return profile
    }

    /// Step 2 for choosing `door`: what the other one has, beside it.
    private func compare(choosing door: HomeSpeakerProfile.Door) throws {
        try compare(from: Self.other(of: door), into: door, purpose: .choose)
    }

    private func compare(from: HomeSpeakerProfile.Door, into: HomeSpeakerProfile.Door,
                         purpose: Pages.DoorCompare.Purpose) throws {
        // The app is offered only while it is installed, and picked only
        // while its program can be found: the hook must have it to run.
        if purpose == .choose, into != me {
            guard parts.otherInstalled() else { return }
            guard appProgramNow() != nil else { throw CommandRefused(Pages.DoorWords.appNotFound) }
        }
        let source = try profile(from)
        let destination = try profile(into)
        let record = parts.door?.read()
        doorReport = []
        doorStep = .compare(Pages.DoorCompare(
            purpose: purpose, from: from, into: into,
            source: DoorSnapshot(profile: source), destination: DoorSnapshot(profile: destination),
            seenChoice: record?.chosen, seenChosenAt: record?.chosenAt))
    }

    /// Copy or Keep, then, when choosing, the rest in order (design 7.6):
    /// the copy reads the other side while it still writes its files; the
    /// choice is written; the hooks follow it; then the app is closed.
    private func finishCompare(copy: Bool) {
        guard case .compare(var compare) = doorStep else { return }
        // A choice made elsewhere since this step began (in the app, say)
        // is never overridden: the step goes, and the page shows what is.
        if choiceChanged(since: compare) {
            doorStep = nil
            doorReport = [Pages.DoorWords.choiceChanged]
            refreshRole()
            return
        }
        // The hook must have the app's program to run: without it, nothing
        // is copied or chosen.
        var appProgram: URL?
        if compare.purpose == .choose, compare.into != me {
            appProgram = appProgramNow()
            if appProgram == nil {
                compare.problem = Pages.DoorWords.appNotFound
                doorStep = .compare(compare)
                return
            }
        }
        do {
            let source = try profile(compare.from)
            let destination = try profile(compare.into)
            doorReport = []
            compare.problem = nil
            if copy {
                do {
                    doorReport = try parts.copy(source, destination).lines
                } catch let partial as DoorCopyPartial {
                    // Stopped part-way: say what came across and what did
                    // not, and tell the destination if its sign-ins changed.
                    if partial.signInsWritten { parts.credentialsChangedIn(destination) }
                    doorReport = partial.copied + partial.notCopied
                    doorStep = .compare(compare)
                    return
                }
                // The side that took the copy re-reads its sign-ins.
                parts.credentialsChangedIn(destination)
            }
            if compare.purpose == .choose { try choose(compare.into) }
        } catch {
            compare.problem = Self.words(error)
            doorStep = .compare(compare)
            return
        }
        guard compare.purpose == .choose else {
            doorStep = nil
            return
        }
        doorReport += repointHooks(at: compare.into, program: compare.into == me ? parts.driver.program : appProgram)
        if compare.into == me {
            closeTheOther()
        } else if let other = parts.other, !other.isRunning {
            openTheOther(other)
        } else {
            doorStep = nil
        }
        refreshRole()
    }

    /// Writes the person's choice into the choice file, under its lock.
    private func choose(_ door: HomeSpeakerProfile.Door) throws {
        guard let file = parts.door else { throw CommandRefused("the choice file is not available, so nothing was chosen") }
        let now = parts.now()
        try file.update {
            $0.chosen = door
            $0.chosenAt = now
            $0.chosenBy = "HomeSpeaker extension \(ToolVersion.current)"
        }
    }

    /// Points every agent's HomeSpeaker hook at the chosen side's program
    /// (design 7.6): otherwise each reply would go to a program that stands
    /// aside, or one in the Trash. An agent with no HomeSpeaker hook gets
    /// none. What could not be done, a sentence each.
    private func repointHooks(at door: HomeSpeakerProfile.Door, program: URL?) -> [String] {
        guard let program else { return [] }
        let integration = AgentIntegration(home: parts.home, executablePath: program.path, bootout: parts.launchctlBootout)
        var problems: [String] = []
        for agent in CodingAgent.allCases where agent.supportsHook {
            guard case .stale = integration.status(of: agent).hook else { continue }
            do {
                try integration.installHook(for: agent)
            } catch {
                problems.append(Self.words(error))
            }
        }
        return problems
    }

    /// Asks the app to quit, and waits for it, off the kit's thread; then
    /// step 3's offers.
    private func closeTheOther() {
        guard let other = parts.other else {
            // Nothing to ask: say nothing about a quit.
            doorStep = nil
            return
        }
        doorStep = .closing
        let later = parts.later
        let timeout = Self.otherStopsWithin
        Task.detached { [weak self] in
            let quit = await other.quit(timeout: timeout)
            let version = other.version
            later { [weak self] in self?.appClosed(quit: quit, version: version) }
        }
    }

    /// Quit, asked again: from step 3, or the line an app older than 1.19
    /// leaves while it still runs.
    private func quitAgain() {
        // Never a HomeSpeaker this side has not found.
        guard let other = parts.other, parts.appProgram() != nil else { return }
        let later = parts.later
        let timeout = Self.otherStopsWithin
        Task.detached { [weak self] in
            let quit = await other.quit(timeout: timeout)
            later { [weak self] in self?.quitAgainDone(quit) }
        }
    }

    private func quitAgainDone(_ quit: Bool) {
        if case .offers(var offers)? = doorStep {
            offers.quit = quit
            doorStep = .offers(offers)
        }
        refreshRole()
        refreshOpenPanels()
    }

    /// The person picked the app, which is not running: it is opened, as
    /// they asked, and its Open at Login, which picking the extension
    /// turned off, is turned back on. Off the kit's thread.
    private func openTheOther(_ other: any OtherAppControlling) {
        doorStep = .opening
        let later = parts.later
        Task.detached { [weak self] in
            let opened = await other.open()
            let loginItem = await other.turnOnLoginItem()
            later { [weak self] in self?.otherOpened(opened, loginItem: loginItem) }
        }
    }

    private func otherOpened(_ opened: Bool, loginItem: Result<Void, OtherAppProblem>) {
        doorStep = nil
        otherStarting = opened
        if !opened { doorReport.append(Pages.DoorWords.couldNotOpen) }
        switch loginItem {
        case .success: doorReport.append(Pages.DoorWords.loginItemOn)
        case .failure(let problem): doorReport.append(problem.sentence)
        }
        refreshRole()
        refreshOpenPanels()
    }

    private func appClosed(quit: Bool, version: String?) {
        doorStep = .offers(Pages.DoorOffers(quit: quit, plan: OtherAppPlan.forChoosingTheExtension(appVersion: version)))
        refreshRole()
        refreshOpenPanels()
    }

    /// Done: the offers left ticked, the login item first, since it runs
    /// the app's own program, which the Trash would move.
    private func closeOffers() {
        guard case .offers(var offers) = doorStep, !offers.working else { return }
        guard let other = parts.other else {
            doorStep = nil
            return
        }
        offers.working = true
        doorStep = .offers(offers)
        let (loginItem, trash) = (offers.loginItem, offers.trash)
        let later = parts.later
        Task.detached { [weak self] in
            var lines: [String] = []
            if loginItem {
                switch await other.turnOffLoginItem() {
                case .success: lines.append(Pages.DoorWords.loginItemOff)
                case .failure(let problem): lines.append(problem.sentence)
                }
            }
            if trash {
                do {
                    _ = try other.moveToTrash()
                    lines.append(Pages.DoorWords.inTheTrash)
                } catch {
                    lines.append(error.localizedDescription)
                }
            }
            let said = lines
            later { [weak self] in self?.offersDone(said) }
        }
    }

    private func offersDone(_ lines: [String]) {
        doorStep = nil
        doorReport += lines
        refreshRole()
        refreshOpenPanels()
    }

    // MARK: - HomeSpeaker's program

    /// HomeSpeaker's program ended a job: what it said, drawn again.
    public func finished(_ job: Job, _ result: JobResult) {
        if job.isSetup {
            if setupBusy == job { setupBusy = nil }
            finishedSetup(job, result)
        } else {
            // The speaker the running job was started for; nil for an
            // answer to no job this tool started, taken as it is.
            let startedFor = busy == job ? busyFor : nil
            if busy == job {
                busy = nil
                busyFor = nil
            }
            reload()
            if job.controlsSpeaker, let startedFor, startedFor != config.defaultTarget {
                // For a speaker that is no longer the default: not shown
                // as the new one's, which is read instead.
                if readsVolume { readPending = true }
            } else {
                finishedSpeaking(job, result)
            }
            startNext()
        }
        refreshOpenPanels()
        updateMark()
    }

    private func finishedSpeaking(_ job: Job, _ result: JobResult) {
        switch result {
        case .spoke(let where_):
            notice = where_.capitalizingFirst
            parts.link.showMessage(notice ?? "Spoken", icon: "hifispeaker.2")
        case .notSpoken(let why):
            notice = why.isEmpty ? "Not spoken" : why.capitalizingFirst
            parts.link.showMessage(notice ?? "Not spoken", icon: "speaker.slash")
        case .volume(let read):
            volume = read
            volumeReadAt = parts.now()
            volumeFor = config.defaultTarget
            if case .setVolume = job { notice = nil }
        case .unavailable(let why), .failed(let why):
            forgetVolume()
            notice = why.capitalizingFirst
        case .done, .homes, .loginItem:
            break
        }
    }

    private func finishedSetup(_ job: Job, _ result: JobResult) {
        switch (job, result) {
        case (.app(.testMediaPause), .done(let lines)):
            mediaPauseReport = lines.joined(separator: ". ").capitalizingFirst
        case (.app(.testMediaPause), .failed(let why)), (.app(.testMediaPause), .unavailable(let why)):
            mediaPauseReport = why.capitalizingFirst
        case (_, .homes(let listed)):
            homes = listed
            if selectedHomeId == nil || !listed.contains(where: { $0.id == selectedHomeId }) {
                selectedHomeId = listed.first(where: { $0.id == config.structureId })?.id ?? listed.first?.id
            }
        case (_, .loginItem(_, let problem)):
            if let problem { setupNotice = problem.capitalizingFirst }
        case (.signIn(chatOnly: true), .done):
            // HomeSpeaker's `--sign-in --chat` told the running app itself.
            setupNotice = "Google Chat access granted"
        case (.app(.signOut(chatOnly: true)), .done(let lines)):
            setupNotice = lines.first?.capitalizingFirst ?? "Signed out of Google Chat"
        case (.signIn, .done):
            let email = parts.account.email
            setupNotice = "Signed in" + (email.map { " as \($0)" } ?? "")
            signedInAfresh()
        case (.app(.signOut), .done(let lines)):
            setupNotice = lines.first?.capitalizingFirst ?? "Signed out"
            homes = nil
            selectedHomeId = nil
        case (.app(.discover(save: true, _)), .done(let lines)):
            reload()
            setupNotice = lines.last?.capitalizingFirst ?? "Speakers saved"
        case (_, .done(let lines)):
            setupNotice = lines.last?.capitalizingFirst
        case (.app(.discover(save: false, _)), .failed(let why)):
            homes = []
            setupNotice = why.capitalizingFirst
        case (_, .failed(let why)), (_, .unavailable(let why)), (_, .notSpoken(let why)):
            setupNotice = why.capitalizingFirst
        case (_, .spoke), (_, .volume):
            break
        }
    }

    /// A fresh Google Home sign-in: the homes are listed again, and with no
    /// speakers yet they are found, as HomeSpeaker's Settings does.
    private func signedInAfresh() {
        homes = nil
        askedHomes = false
        reload()
        if !config.hasSpeakers, setupBusy == nil { try? discover() }
    }

    /// The app opens HomeSpeaker's settings panel when an answer names it.
    private var opensSettings: Bool { parts.link.supports(featureNamed: Self.openSettingsFeature) }

    /// The app draws sections, so Settings is sent every section on one
    /// page (`Pages.settings`), with no Section picker.
    private var sendsEverySection: Bool { parts.link.supports(.sections) }

    /// The settings page holds `section`: the one picked, or every one.
    private func settingsShows(_ section: Pages.Section) -> Bool { sendsEverySection || self.section == section }

    public func status() -> Pages.Status {
        var status = Pages.Status()
        status.installed = parts.driver.isInstalled
        status.config = config
        status.volume = volume
        status.busy = waiting ?? busy
        status.notice = notice
        status.quietNow = config.isInQuietHours(at: parts.now())
        status.offersChoice = parts.link.supports(.choice)
        status.offersChips = parts.link.supports(.chips)
        status.offersSections = parts.link.supports(.sections)
        status.opensSettings = opensSettings
        status.configProblem = configProblem
        status.section = section
        status.setupBusy = setupBusy
        status.setupNotice = setupNotice
        status.mediaPauseReport = mediaPauseReport
        status.homes = homes
        status.selectedHomeId = selectedHomeId
        status.previewing = previewing
        status.removingSpeakers = removingSpeakers
        let role = parts.role()
        status.door = doorState(role: role)
        status.volumeRestoreReport = parts.volumeRestoreReport()
        let account = parts.account
        let islandOpen = openPanels.contains(Self.islandPanel)
        let usesGemini = config.effectiveLocalEngine == .gemini || config.effectiveStyleModel == .gemini
        if islandOpen || openPanels.contains(Self.settingsPanel) {
            // Whether a Gemini key is saved, whenever Gemini is chosen:
            // the chat status below reads it only while a chat source is on.
            if usesGemini { status.chat.hasGeminiKey = parts.chat.hasGeminiKey }
            status.account = Pages.Account(isSignedIn: account.isSignedIn, email: account.email,
                                           hasOAuthClient: account.hasOAuthClient, hasAntigravityTokens: account.hasAntigravityTokens)
        }
        if islandOpen {
            status.recentBroadcasts = BroadcastHistory(fileURL: parts.historyURL).load()
            // The island warns about the chat monitor only while it is on,
            // so nothing is looked for otherwise.
            if config.effectiveChatMonitor.anySourceEnabled {
                status.chat = chatStatus(role: role)
                drawnChat = status.chat
            }
        }
        if openPanels.contains(Self.settingsPanel) {
            if settingsShows(.googleCloud) {
                status.account.customOAuthClientId = account.customOAuthClientId
                status.account.hasCustomOAuthClientSecret = account.hasCustomOAuthClientSecret
                status.account.hasBundledOAuthClient = account.hasBundledOAuthClient
                status.draftClientId = draftClientId
                status.draftClientSecretTyped = !draftClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                status.files = Pages.Files(settings: parts.settingsURL.path, secrets: parts.secretsURL.path,
                                           history: parts.historyURL.path,
                                           homeSpeakerVersion: parts.driver.isInstalled ? parts.homeSpeakerVersion() : nil)
            }
            if settingsShows(.agents) {
                // The agents' files are read here and nowhere else.
                let integration = agentStatusIntegration()
                let installer = agentIntegration()
                status.agents = Pages.Agents(
                    statuses: CodingAgent.allCases.map(integration.status(of:)),
                    hookCommands: Dictionary(uniqueKeysWithValues: CodingAgent.allCases.compactMap { agent in
                        installer.map { (agent, $0.hookCommand(for: agent)) }
                    }),
                    legacyLaunchAgent: integration.isLegacyLaunchAgentInstalled())
            }
            // Read as the page draws Chats, so a change of Beeper's
            // network chips is saved against the networks drawn.
            if settingsShows(.monitor) {
                status.chat = chatStatus(role: role)
                drawnChat = status.chat
            }
            if settingsShows(.speakers), config.effectiveSpeakLocal {
                if voices == nil { voices = parts.voices() }
                status.voices = voices ?? []
            }
        }
        return status
    }

    /// The chat monitor as the pages show it. Its owner counts as running
    /// only while this side runs and its process is alive: a waiting or
    /// quiet side runs no monitor, so it offers no Start or Stop.
    private func chatStatus(role: DoorRole? = nil) -> Pages.Chat {
        let chat = parts.chat
        return Pages.Chat(hasSlackToken: chat.hasSlackToken, hasChatAccess: chat.hasChatAccess,
                          gwsPath: parts.gwsLocation(), ownerRunning: Self.runs(role ?? parts.role()) && parts.ownerRunning(),
                          monitor: ChatMonitorStatusFile(url: parts.monitorStatusURL).read(),
                          hasBeeperToken: chat.hasBeeperToken, hasGeminiKey: chat.hasGeminiKey)
    }

    /// The settings page, after starting what Settings reads by itself:
    /// the homes once Speakers shows with a sign-in. It waits for the setup
    /// slot and is asked once an opening.
    private func settingsTree() -> UITree {
        if parts.driver.isInstalled, setupBusy == nil, settingsShows(.speakers), homes == nil, !askedHomes,
           parts.account.isSignedIn {
            askedHomes = true
            try? setupJob(.app(.discover(save: false, home: nil)))
        }
        return Pages.settings(status())
    }

    private func discover() throws {
        guard parts.account.isSignedIn else { throw CommandRefused("sign in under General first") }
        let home = selectedHomeId.flatMap { $0.isEmpty ? nil : $0 }
        try setupJob(.app(.discover(save: true, home: home)))
    }

    private func importAntigravity() throws {
        guard try parts.account.importFromAntigravity() else {
            throw CommandRefused("no Google Home login found in the Antigravity token file")
        }
        setupNotice = "Imported the Antigravity Google Home login"
        parts.credentialsChanged()
        homes = nil
        askedHomes = false
        if !config.hasSpeakers, parts.driver.isInstalled, setupBusy == nil { try discover() }
    }

    /// A token saved or cleared from Settings: the island, if open, is
    /// redrawn, so its warning and token field follow at once.
    private func tokenSavedElsewhere() {
        if openPanels.contains(Self.islandPanel) { parts.link.render(panel: Self.islandPanel, Pages.island(status())) }
    }

    /// What Save Token saves: the token held from the field, or else the
    /// one on the clipboard. A Vitruvian that sends a field's text only
    /// when the field is left (3.61 and earlier) never sends it when Save
    /// Token is clicked straight after pasting, so the draft is empty while
    /// the token sits on the clipboard. Only a clipboard that looks like a
    /// token is taken: one word, and for Slack starting `xox`. Empty when
    /// there is neither.
    private func tokenToSave(slack: Bool) -> String {
        tokenToSave(slack ? .slack : .beeper)
    }

    private func tokenToSave(_ secret: Secret) -> String {
        let draft = draft(secret).trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.isEmpty else { return draft }
        let clip = (parts.link.clipboardText() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clip.isEmpty, !clip.contains(where: \.isWhitespace) else { return "" }
        if secret == .slack, !clip.hasPrefix("xox") { return "" }
        return clip
    }

    /// The secrets a field takes: its field and its save button.
    enum Secret: Equatable {
        case slack, beeper, gemini

        init?(block: String) {
            switch block {
            case Pages.Block.slackToken, Pages.Block.saveSlackToken: self = .slack
            case Pages.Block.beeperToken, Pages.Block.saveBeeperToken: self = .beeper
            case Pages.Block.geminiApiKey, Pages.Block.saveGeminiApiKey: self = .gemini
            default: return nil
            }
        }

        var field: String {
            switch self {
            case .slack: return Pages.Block.slackToken
            case .beeper: return Pages.Block.beeperToken
            case .gemini: return Pages.Block.geminiApiKey
            }
        }

        /// "Slack token", for "Paste the … first".
        var name: String {
            switch self {
            case .slack: return "Slack token"
            case .beeper: return "Beeper token"
            case .gemini: return "Gemini API key"
            }
        }
    }

    private func draft(_ secret: Secret) -> String {
        switch secret {
        case .slack: return draftSlackToken
        case .beeper: return draftBeeperToken
        case .gemini: return draftGeminiKey
        }
    }

    private func setDraft(_ secret: Secret, _ text: String) {
        switch secret {
        case .slack: draftSlackToken = text
        case .beeper: draftBeeperToken = text
        case .gemini: draftGeminiKey = text
        }
    }

    private func save(_ secret: Secret, _ typed: String) throws {
        switch secret {
        case .slack: try saveSlackToken(typed)
        case .beeper: try saveBeeperToken(typed)
        case .gemini: try saveGeminiKey(typed)
        }
    }

    /// A text setting saved at each keystroke, which no redraw may follow.
    static func savesWhileTyping(_ event: PanelEvent) -> Bool {
        event.block == Pages.Block.customStylePrompt && event.kind == .change
    }

    /// Saves the Slack token typed, trimmed; nothing typed clears it. The
    /// token goes to the secrets file and nowhere else -- not the page, not
    /// a notice -- and a running HomeSpeaker is told, so a monitor waiting
    /// for a token starts.
    private func saveSlackToken(_ typed: String) throws {
        let token = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            try parts.chat.clearSlackToken()
            setupNotice = "Slack token cleared"
        } else {
            try parts.chat.saveSlackToken(token)
            setupNotice = "Slack token saved"
            draftSlackToken = ""
        }
        parts.credentialsChanged()
    }

    /// Saves the Beeper token typed, trimmed; nothing typed clears it. As
    /// with Slack's: to the secrets file only, and the running monitor is
    /// told, so it starts or restarts with it.
    private func saveBeeperToken(_ typed: String) throws {
        let token = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            try parts.chat.clearBeeperToken()
            setupNotice = "Beeper token cleared"
        } else {
            try parts.chat.saveBeeperToken(token)
            setupNotice = "Beeper token saved"
            draftBeeperToken = ""
        }
        parts.credentialsChanged()
    }

    /// Saves the Gemini API key typed, trimmed; nothing typed clears it. To
    /// the secrets file only. Nothing restarts: it is read at each
    /// announcement.
    private func saveGeminiKey(_ typed: String) throws {
        let key = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            try parts.chat.clearGeminiKey()
            setupNotice = "Gemini API key cleared"
        } else {
            try parts.chat.saveGeminiKey(key)
            setupNotice = "Gemini API key saved"
            draftGeminiKey = ""
        }
    }

    /// A poll interval the chat monitor accepts.
    public static func clampedPollInterval(_ seconds: Int) -> Int {
        min(max(seconds, ChatMonitorConfig.minPollInterval), ChatMonitorConfig.maxPollInterval)
    }

    /// Speaks the preview on this Mac, in the tool's own process: it needs
    /// no sign-in and no HomeSpeaker.
    private func preview() {
        guard !previewing else { return }
        previewing = true
        let voice = config.effectiveLocalVoice
        let speak = parts.previewVoice
        let later = parts.later
        Task { [weak self] in
            let failure: String?
            do {
                try await speak(voice)
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
            later { [weak self] in self?.previewed(failure) }
        }
    }

    private func previewed(_ failure: String?) {
        previewing = false
        if let failure { setupNotice = failure.capitalizingFirst }
        refreshOpenPanels()
    }

    /// While the other HomeSpeaker is in use this one does nothing, even
    /// asked by hand: the other is the one the person picked. While nobody
    /// has picked, what the person asks for is done.
    private func refuseWhileQuiet() throws {
        if case .quiet(let other) = parts.role() {
            throw CommandRefused("The HomeSpeaker \(other.rawValue) is in use, so this one stays quiet")
        }
    }

    private func say(_ text: String) throws {
        try check(.say(text))
        try run(.say(text))
    }

    /// Speaks again the history's broadcast `id`, as Say speaks what is
    /// typed: the master switch holds, quiet hours do not. HomeSpeaker
    /// leaves the history as it is (`Job.replay`), so it is listed once.
    private func replay(_ id: UUID) throws {
        guard let item = BroadcastHistory(fileURL: parts.historyURL).load().first(where: { $0.id == id }) else {
            throw CommandRefused(Pages.replayGone)
        }
        try check(.replay(item.text))
        try run(.replay(item.text))
    }

    private func speakerJob(_ job: Job) throws {
        try check(job)
        try run(job)
    }

    /// What a speaker job needs, when it is asked for and again when it
    /// has waited.
    private func check(_ job: Job) throws {
        try refuseWhileQuiet()
        guard parts.driver.isInstalled else { throw CommandRefused("HomeSpeaker is not installed") }
        reload()
        if job.spokenText != nil {
            guard config.defaultDevice != nil || config.effectiveSpeakLocal || config.effectiveSpeakPhone else {
                throw CommandRefused(Self.notSetUp)
            }
            guard config.enabled else { throw CommandRefused("broadcasting is switched off") }
        } else {
            guard config.defaultDevice != nil else { throw CommandRefused("no default speaker; pick one in HomeSpeaker") }
        }
    }

    /// Runs what waited for the slot: the job the person asked for, if it
    /// still holds, then a read the speaker change left.
    private func startNext() {
        guard busy == nil else { return }
        if let next = waiting {
            let wantedFor = waitingFor
            waiting = nil
            waitingFor = nil
            do {
                try check(next)
                if next.controlsSpeaker {
                    // Meant for this speaker, with Home speakers on.
                    guard wantedFor == config.defaultTarget else { throw CommandRefused(Pages.pendingDropped) }
                    guard config.effectiveSpeakHome else { throw CommandRefused(Pages.homeSpeakersOff) }
                }
                try run(next)
            } catch {
                notice = Self.words(error)
            }
            if busy != nil { return }
        }
        if readPending {
            readPending = false
            if readsVolume { try? run(.volume, keepingNotice: true) }
        }
    }

    /// A setup job needs HomeSpeaker and nothing more: not a speaker, and
    /// not the speaker slot.
    private func setupJob(_ job: Job) throws {
        try refuseWhileQuiet()
        guard parts.driver.isInstalled else { throw CommandRefused("HomeSpeaker is not installed") }
        try run(job)
    }

    /// One job a slot at a time: HomeSpeaker's program takes seconds, and
    /// two speaker jobs at once would read a volume the other is setting. A
    /// second in the same slot is refused, saying what is still running;
    /// a setup job and a speaker job run side by side.
    private func run(_ job: Job, keepingNotice: Bool = false) throws {
        if job.isSetup {
            if let setupBusy { throw CommandRefused("HomeSpeaker is busy: \(Pages.busyLine(setupBusy))") }
            setupBusy = job
            setupNotice = nil
        } else {
            if let busy {
                if job == .volume {
                    // A read already running for this speaker is enough;
                    // otherwise one follows whatever runs.
                    if busy != .volume || busyFor != config.defaultTarget { readPending = true }
                    return
                }
                // Behind a read of the volume, one job waits; behind
                // anything else, or a second, it is refused.
                guard busy == .volume, waiting == nil else {
                    throw CommandRefused("HomeSpeaker is busy: \(Pages.busyLine(waiting ?? busy))")
                }
                waiting = job
                waitingFor = config.defaultTarget
                notice = nil
                updateMark()
                return
            }
            busy = job
            busyFor = job.controlsSpeaker ? config.defaultTarget : nil
            if !keepingNotice { notice = nil }
        }
        let later = parts.later
        parts.driver.run(job) { [weak self] result in
            later { [weak self] in self?.finished(job, result) }
        }
        updateMark()
    }

    private func reload() {
        switch parts.store.read() {
        case .loaded(let read):
            config = read
            configProblem = nil
        case .missing:
            configProblem = nil
        case .unreadable(let why):
            configProblem = why.localizedDescription
        }
        // The default changed outside the tool: the level shown was the
        // old speaker's.
        if volume != nil, volumeFor != config.defaultTarget { forgetVolume() }
    }

    /// Never over a file that does not read: the tool's copy would replace
    /// whatever the person, the phone or the app put there.
    private func save() throws {
        if let configProblem { throw CommandRefused("refusing to save: \(configProblem)") }
        try parts.store.save(config)
        updateMark()
    }

    /// An error as a sentence for the page: a refusal's own words, not
    /// the struct around them.
    static func words(_ error: Error) -> String {
        ((error as? CommandRefused)?.message ?? error.localizedDescription).capitalizingFirst
    }

    private func refreshOpenPanels() {
        if openPanels.contains(Self.islandPanel) { parts.link.render(panel: Self.islandPanel, Pages.island(status())) }
        if openPanels.contains(Self.settingsPanel) { parts.link.render(panel: Self.settingsPanel, settingsTree()) }
    }
}

extension String {
    var capitalizingFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

extension Job {
    /// Reads or changes the default speaker's volume: HomeSpeaker picks the
    /// speaker from the settings when it runs.
    var controlsSpeaker: Bool {
        switch self {
        case .volume, .setVolume, .mute, .unmute: return true
        case .say, .replay, .app, .signIn: return false
        }
    }
}
