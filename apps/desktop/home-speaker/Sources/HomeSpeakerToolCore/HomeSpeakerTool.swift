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
    /// Whether the app has something a later protocol release added, such
    /// as the `choice` block.
    func supports(_ feature: ProtocolFeature) -> Bool
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
        /// HomeSpeaker.app is running as an app, so it reads messages
        /// (`ProcessDriver.isAppRunning()`).
        public var isAppRunning: () -> Bool
        /// Tells a running HomeSpeaker that a login or token changed
        /// (`CredentialsChangedNotice.post()`), so it re-reads them and
        /// starts or restarts its chat monitor.
        public var credentialsChanged: () -> Void
        /// The home folder the coding agents keep their files in.
        public var home: URL
        /// Where HomeSpeaker's settings and secrets files are, for Files.
        public var settingsURL: URL
        public var secretsURL: URL
        /// The installed HomeSpeaker's version, from its bundle; nil when
        /// it is not installed or does not say.
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
        /// Asks a running HomeSpeaker to start or stop its chat monitor
        /// (`ChatMonitorControlNotice.post`). The default asks nothing, so
        /// a test never reaches a real running app.
        public var controlChatMonitor: (ChatMonitorAction) -> Void

        public init(link: ToolLink, store: ConfigStore, driver: SpeakerDriver,
                    later: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void, now: @escaping () -> Date = Date.init,
                    account: GoogleAccount = NoGoogleAccount(), voices: @escaping () -> [LocalVoice] = { [] },
                    previewVoice: @escaping @Sendable (String) async throws -> Void = { _ in },
                    chat: ChatCredentials = NoChatCredentials(), gwsLocation: @escaping () -> String? = { nil },
                    isAppRunning: @escaping () -> Bool = { false }, credentialsChanged: @escaping () -> Void = {},
                    home: URL = FileManager.default.homeDirectoryForCurrentUser,
                    settingsURL: URL = ConfigManager.defaultConfigURL(), secretsURL: URL = SecretStore.defaultURL(),
                    homeSpeakerVersion: @escaping () -> String? = { nil },
                    launchctlBootout: @escaping @Sendable (String) -> Void = AgentIntegration.launchctlBootout,
                    historyURL: URL? = nil, monitorStatusURL: URL? = nil,
                    controlChatMonitor: @escaping (ChatMonitorAction) -> Void = { _ in }) {
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
            self.isAppRunning = isAppRunning
            self.credentialsChanged = credentialsChanged
            self.home = home
            self.settingsURL = settingsURL
            self.secretsURL = secretsURL
            self.homeSpeakerVersion = homeSpeakerVersion
            self.launchctlBootout = launchctlBootout
            self.historyURL = historyURL ?? Self.historyURL(beside: settingsURL)
            self.monitorStatusURL = monitorStatusURL ?? ChatMonitorStatusFile.url(beside: settingsURL)
            self.controlChatMonitor = controlChatMonitor
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
    /// The setup job running beside it: signing in or out, discovery, the
    /// login item, the media-pause test. Its own slot, so a browser sign-in
    /// that takes minutes never holds up speech or a mute.
    public private(set) var setupBusy: Job?
    public private(set) var notice: String?
    public private(set) var setupNotice: String?
    public private(set) var openPanels: Set<String> = []
    /// The settings section shown, kept across redraws.
    public private(set) var section = Pages.Section.general
    public private(set) var loginItem: LoginItemState?
    public private(set) var mediaPauseReport: String?
    public private(set) var homes: [HomeStructure]?
    public private(set) var selectedHomeId: String?
    public private(set) var previewing = false
    public private(set) var removingSpeakers = false
    /// The OAuth client typed under Google Cloud, held until Save. The
    /// secret is never drawn back into its field.
    public private(set) var draftClientId = ""
    public private(set) var draftClientSecret = ""
    private var voices: [LocalVoice]?
    /// Asked once each time Settings opens, so a failure is not asked again
    /// at every redraw.
    private var askedLoginItem = false
    private var askedHomes = false
    /// The island's setup lists the homes once each time it opens.
    private var askedIslandHomes = false
    /// The chat monitor as last drawn, so a change the app writes is drawn
    /// and an unchanged one is not (`refreshMonitorStatus`).
    private var drawnChat: Pages.Chat?

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
        if !openPanels.contains(Self.islandPanel) { askedIslandHomes = false }
        openPanels.insert(Self.islandPanel)
        reload()
        if readsVolume, volume == nil, busy == nil { try? run(.volume) }
        listHomesForSetup()
        return Pages.island(status())
    }

    /// The volume is read only where it can answer: HomeSpeaker installed,
    /// a speaker picked, and Home speakers on. With them off a read would
    /// only wait on a Cast speaker nobody is using.
    private var readsVolume: Bool {
        parts.driver.isInstalled && config.defaultDevice != nil && config.effectiveSpeakHome
    }

    /// Signed in with no speakers: the island's setup offers each home, so
    /// they are listed once an opening, in the setup slot.
    private func listHomesForSetup() {
        guard parts.driver.isInstalled, setupBusy == nil, homes == nil, !askedIslandHomes,
              config.targets.isEmpty, parts.account.isSignedIn else { return }
        askedIslandHomes = true
        try? setupJob(.app(.discover(save: false, home: nil)))
    }

    public func islandEvent(_ event: PanelEvent) -> PanelAnswer {
        if let answer = islandSetupEvent(event) { return answer }
        do {
            switch event.block {
            case Pages.Block.say?:
                guard let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return .keep }
                try say(text)
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
            case Pages.Block.mute?: try speakerJob(.mute)
            case Pages.Block.unmute?: try speakerJob(.unmute)
            case Pages.Block.refresh?: try speakerJob(.volume)
            case Pages.Block.volume?:
                guard let text = event.text, let level = Int(text.trimmingCharacters(in: .whitespaces)), (0...100).contains(level) else {
                    notice = "A volume is a whole number from 0 to 100"
                    return .page(Pages.island(status()))
                }
                try speakerJob(.setVolume(level))
            case Pages.Block.speakers?:
                guard let key = event.row else { return .keep }
                reload()
                guard config.targets[key] != nil else { return .keep }
                config.defaultTarget = key
                try save()
                volume = nil
                if readsVolume { try run(.volume) }
            case Pages.Block.outputHome?:
                guard let isOn = event.isOn else { return .keep }
                reload()
                config.effectiveSpeakHome = isOn
                try save()
                // A reading from before Home speakers went off is stale.
                volume = nil
            case Pages.Block.outputLocal?:
                guard let isOn = event.isOn else { return .keep }
                reload()
                config.effectiveSpeakLocal = isOn
                try save()
            default:
                return .keep
            }
        } catch {
            notice = Self.words(error)
        }
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
            askedLoginItem = false
            askedHomes = false
            voices = nil
            draftClientId = parts.account.customOAuthClientId ?? ""
            draftClientSecret = ""
        }
        openPanels.insert(Self.settingsPanel)
        reload()
        return settingsTree()
    }

    public func settingsEvent(_ event: PanelEvent) -> PanelAnswer {
        reload()
        // The value a picker answers with: a choice's as text, a list's as
        // the row tapped.
        let picked = event.text ?? event.row
        do {
            switch event.block {
            case Pages.Block.section?:
                guard let picked, let section = Pages.Section(rawValue: picked) else { return .keep }
                self.section = section
                removingSpeakers = false
                return .page(settingsTree())
            case Pages.Block.openGoogleCloud?:
                section = .googleCloud
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
                // Return only: leaving the field half-typed saves nothing.
                guard event.kind == .submit, let text = event.text else { return .keep }
                try saveSlackToken(text)
            case Pages.Block.clearSlackToken?:
                try saveSlackToken("")
            case Pages.Block.grantChat?:
                try setupJob(.signIn(chatOnly: true))
            case Pages.Block.disconnectChat?:
                try setupJob(.app(.signOut(chatOnly: true)))
            case Pages.Block.loginItem?:
                guard let isOn = event.isOn else { return .keep }
                try setupJob(.app(.loginItem(isOn ? .enable : .disable)))
            case Pages.Block.testMediaPause?:
                mediaPauseReport = nil
                try setupJob(.app(.testMediaPause))
            case Pages.Block.discover?:
                try discover()
            case Pages.Block.home?:
                guard let picked, homes?.contains(where: { $0.id == picked }) == true else { return .keep }
                selectedHomeId = picked
            case Pages.Block.editSpeakers?:
                removingSpeakers.toggle()
            case Pages.Block.previewVoice?:
                preview()
            case Pages.Block.broadcasting?, Pages.Block.speechLength?, Pages.Block.speakHome?, Pages.Block.speakLocal?,
                 Pages.Block.announceVolume?, Pages.Block.announceLevel?, Pages.Block.pauseMedia?, Pages.Block.pauseExtra?,
                 Pages.Block.quiet?, Pages.Block.quietStart?, Pages.Block.quietEnd?, Pages.Block.targets?, Pages.Block.voice?,
                 Pages.Block.slackEnabled?, Pages.Block.googleChatEnabled?, Pages.Block.chatSource?, Pages.Block.gwsAccount?,
                 Pages.Block.muteOwnMessages?, Pages.Block.pollInterval?:
                // A value out of range throws, and is said under the
                // section instead of being dropped or quietly clamped.
                guard try change(event, picked: picked) else { return .keep }
                do {
                    try save()
                    if let notice = setupNotice, Invalid.all.contains(notice) { setupNotice = nil }
                } catch {
                    parts.link.log("the settings could not be saved: \(error)")
                    reload()
                }
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

    /// Asks the running HomeSpeaker to start or stop its monitor. The page
    /// says Running once the app has written that it is; the request alone
    /// changes nothing on it.
    private func controlChatMonitor(_ action: ChatMonitorAction) throws {
        guard parts.isAppRunning() else {
            throw CommandRefused("HomeSpeaker isn't running: open it, then \(action.rawValue) the chat monitor")
        }
        if action == .start, !config.effectiveChatMonitor.anySourceEnabled {
            throw CommandRefused("turn on Slack or Google Chat first")
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
            guard let integration = agentIntegration() else { throw CommandRefused("HomeSpeaker is not installed") }
            try integration.installHook(for: agent)
            setupNotice = "\(name) hook installed"
        case .removeHook:
            try agentStatusIntegration().removeHook(for: agent)
            setupNotice = "\(name) hook removed"
        case .disableRival:
            try agentStatusIntegration().disableRivalHook(for: agent)
            setupNotice = "Disabled the duplicate hook; replies are announced once now"
        case .addInstruction:
            try agentStatusIntegration().addBroadcastInstruction(for: agent)
            setupNotice = "Instruction added to \(agent.instructionFileName)"
        }
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
        case Pages.Block.speakHome?:
            guard let isOn = event.isOn else { return false }
            config.effectiveSpeakHome = isOn
        case Pages.Block.speakLocal?:
            guard let isOn = event.isOn else { return false }
            config.effectiveSpeakLocal = isOn
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
            guard let key = event.row, config.targets[key] != nil else { return false }
            let before = config.defaultTarget
            if removingSpeakers {
                config.removeTarget(key)
                if config.targets.isEmpty { removingSpeakers = false }
            } else {
                guard before != key else { return false }
                config.defaultTarget = key
            }
            // The island's reading was the old default's.
            if config.defaultTarget != before { volume = nil }
        case Pages.Block.voice?:
            guard let picked, !picked.isEmpty else { return false }
            config.effectiveLocalVoice = picked
        // Chat & Slack: the app follows the file and starts, stops or
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
        case Pages.Block.muteOwnMessages?:
            guard let isOn = event.isOn else { return false }
            config.effectiveChatMonitor.muteOwnMessages = isOn
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

    public func panelClosed(_ panel: String) {
        openPanels.remove(panel)
    }

    /// Draws the open pages again when what the chat monitor says about
    /// itself has changed since they were drawn: a Start pressed here shows
    /// Running once the app has started, without another tap. Asked on a
    /// timer; reads nothing unless a page that shows the monitor is open.
    public func refreshMonitorStatus() {
        let settingsShowsIt = openPanels.contains(Self.settingsPanel) && section == .monitor
        let islandShowsIt = openPanels.contains(Self.islandPanel) && config.effectiveChatMonitor.anySourceEnabled
        guard settingsShowsIt || islandShowsIt else { return }
        reload()
        guard chatStatus() != drawnChat else { return }
        refreshOpenPanels()
    }

    // MARK: - HomeSpeaker's program

    /// HomeSpeaker's program ended a job: what it said, drawn again.
    public func finished(_ job: Job, _ result: JobResult) {
        if job.isSetup {
            if setupBusy == job { setupBusy = nil }
            finishedSetup(job, result)
        } else {
            if busy == job { busy = nil }
            finishedSpeaking(job, result)
        }
        refreshOpenPanels()
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
            if case .setVolume = job { notice = nil }
        case .unavailable(let why), .failed(let why):
            volume = nil
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
        case (_, .loginItem(let state, let problem)):
            loginItem = state
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

    public func status() -> Pages.Status {
        var status = Pages.Status()
        status.installed = parts.driver.isInstalled
        status.config = config
        status.volume = volume
        status.busy = busy
        status.notice = notice
        status.quietNow = config.isInQuietHours(at: parts.now())
        status.offersChoice = parts.link.supports(.choice)
        status.configProblem = configProblem
        status.section = section
        status.setupBusy = setupBusy
        status.setupNotice = setupNotice
        status.loginItem = loginItem
        status.mediaPauseReport = mediaPauseReport
        status.homes = homes
        status.selectedHomeId = selectedHomeId
        status.previewing = previewing
        status.removingSpeakers = removingSpeakers
        let account = parts.account
        let islandOpen = openPanels.contains(Self.islandPanel)
        if islandOpen || openPanels.contains(Self.settingsPanel) {
            status.account = Pages.Account(isSignedIn: account.isSignedIn, email: account.email,
                                           hasOAuthClient: account.hasOAuthClient, hasAntigravityTokens: account.hasAntigravityTokens)
        }
        if islandOpen {
            status.recentBroadcasts = BroadcastHistory(fileURL: parts.historyURL).load()
            // The island warns about the chat monitor only while it is on,
            // so nothing is looked for otherwise.
            if config.effectiveChatMonitor.anySourceEnabled {
                status.chat = chatStatus()
                drawnChat = status.chat
            }
        }
        if openPanels.contains(Self.settingsPanel) {
            if section == .googleCloud {
                status.account.customOAuthClientId = account.customOAuthClientId
                status.account.hasCustomOAuthClientSecret = account.hasCustomOAuthClientSecret
                status.account.hasBundledOAuthClient = account.hasBundledOAuthClient
                status.draftClientId = draftClientId
                status.draftClientSecretTyped = !draftClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                status.files = Pages.Files(settings: parts.settingsURL.path, secrets: parts.secretsURL.path,
                                           homeSpeakerVersion: parts.driver.isInstalled ? parts.homeSpeakerVersion() : nil)
            }
            if section == .agents {
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
            if section == .monitor {
                status.chat = chatStatus()
                drawnChat = status.chat
            }
            if section == .speakers, config.effectiveSpeakLocal {
                if voices == nil { voices = parts.voices() }
                status.voices = voices ?? []
            }
        }
        return status
    }

    private func chatStatus() -> Pages.Chat {
        let chat = parts.chat
        return Pages.Chat(hasSlackToken: chat.hasSlackToken, hasChatAccess: chat.hasChatAccess,
                          gwsPath: parts.gwsLocation(), appRunning: parts.isAppRunning(),
                          monitor: ChatMonitorStatusFile(url: parts.monitorStatusURL).read())
    }

    /// The settings page, after starting what Settings reads by itself:
    /// the login item once it opens, the homes once Speakers shows with a
    /// sign-in. Each waits for the setup slot and is asked once an opening.
    private func settingsTree() -> UITree {
        if parts.driver.isInstalled, setupBusy == nil {
            if !askedLoginItem {
                askedLoginItem = true
                try? setupJob(.app(.loginItem(.status)))
            } else if section == .speakers, homes == nil, !askedHomes, parts.account.isSignedIn {
                askedHomes = true
                try? setupJob(.app(.discover(save: false, home: nil)))
            }
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
        }
        parts.credentialsChanged()
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

    private func say(_ text: String) throws {
        guard parts.driver.isInstalled else { throw CommandRefused("HomeSpeaker is not installed") }
        reload()
        guard config.enabled else { throw CommandRefused("broadcasting is switched off") }
        try run(.say(text))
    }

    private func speakerJob(_ job: Job) throws {
        guard parts.driver.isInstalled else { throw CommandRefused("HomeSpeaker is not installed") }
        reload()
        guard config.defaultDevice != nil else { throw CommandRefused("no default speaker; pick one in HomeSpeaker") }
        try run(job)
    }

    /// A setup job needs HomeSpeaker and nothing more: not a speaker, and
    /// not the speaker slot.
    private func setupJob(_ job: Job) throws {
        guard parts.driver.isInstalled else { throw CommandRefused("HomeSpeaker is not installed") }
        try run(job)
    }

    /// One job a slot at a time: HomeSpeaker's program takes seconds, and
    /// two speaker jobs at once would read a volume the other is setting. A
    /// second in the same slot is refused, saying what is still running;
    /// a setup job and a speaker job run side by side.
    private func run(_ job: Job) throws {
        if job.isSetup {
            if let setupBusy { throw CommandRefused("HomeSpeaker is busy: \(Pages.busyLine(setupBusy))") }
            setupBusy = job
            setupNotice = nil
        } else {
            if let busy { throw CommandRefused("HomeSpeaker is busy: \(Pages.busyLine(busy))") }
            busy = job
            notice = nil
        }
        let later = parts.later
        parts.driver.run(job) { [weak self] result in
            later { [weak self] in self?.finished(job, result) }
        }
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
    }

    /// Never over a file that does not read: the tool's copy would replace
    /// whatever the person, the phone or the app put there.
    private func save() throws {
        if let configProblem { throw CommandRefused("refusing to save: \(configProblem)") }
        try parts.store.save(config)
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
