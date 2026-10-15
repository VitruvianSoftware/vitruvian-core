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

/// The tool's two pages, pure functions of what it knows. English, as
/// HomeSpeaker is.
public enum Pages {
    /// The parts of the settings panel, one shown at a time.
    public enum Section: String, CaseIterable, Sendable {
        case general, speakers, monitor, agents, googleCloud

        public var title: String {
            switch self {
            case .general: return "General"
            case .speakers: return "Speakers"
            case .monitor: return "Chat & Slack"
            case .agents: return "AI Agents"
            case .googleCloud: return "Google Cloud"
            }
        }
    }

    /// The Google Home sign-in, as Settings shows it: never a token.
    public struct Account: Equatable, Sendable {
        public var isSignedIn = false
        public var email: String?
        public var hasOAuthClient = false
        public var hasAntigravityTokens = false
        /// The person's own OAuth client id, if one is saved. Never its secret.
        public var customOAuthClientId: String?
        public var hasCustomOAuthClientSecret = false
        /// HomeSpeaker.app was packaged with a shared OAuth client.
        public var hasBundledOAuthClient = false

        public init(isSignedIn: Bool = false, email: String? = nil, hasOAuthClient: Bool = false, hasAntigravityTokens: Bool = false,
                    customOAuthClientId: String? = nil, hasCustomOAuthClientSecret: Bool = false, hasBundledOAuthClient: Bool = false) {
            self.isSignedIn = isSignedIn
            self.email = email
            self.hasOAuthClient = hasOAuthClient
            self.hasAntigravityTokens = hasAntigravityTokens
            self.customOAuthClientId = customOAuthClientId
            self.hasCustomOAuthClientSecret = hasCustomOAuthClientSecret
            self.hasBundledOAuthClient = hasBundledOAuthClient
        }
    }

    /// The coding agents, as AI Agents shows them.
    public struct Agents: Equatable {
        /// Each agent's state, read from its files.
        public var statuses: [AgentIntegration.AgentStatus] = []
        /// The command a hook runs, by agent: only while HomeSpeaker is
        /// installed, since without it there is nothing a hook could run.
        public var hookCommands: [CodingAgent: String] = [:]
        /// The 1.x chat-monitor launch agent is still on this Mac.
        public var legacyLaunchAgent = false

        public init(statuses: [AgentIntegration.AgentStatus] = [], hookCommands: [CodingAgent: String] = [:],
                    legacyLaunchAgent: Bool = false) {
            self.statuses = statuses
            self.hookCommands = hookCommands
            self.legacyLaunchAgent = legacyLaunchAgent
        }
    }

    /// Where HomeSpeaker keeps things, and the versions, as Files lists them.
    public struct Files: Equatable, Sendable {
        public var settings = ""
        public var secrets = ""
        public var toolVersion = ToolVersion.current
        /// The installed HomeSpeaker's version; nil when it cannot be read.
        public var homeSpeakerVersion: String?

        public init(settings: String = "", secrets: String = "", toolVersion: String = ToolVersion.current,
                    homeSpeakerVersion: String? = nil) {
            self.settings = settings
            self.secrets = secrets
            self.toolVersion = toolVersion
            self.homeSpeakerVersion = homeSpeakerVersion
        }
    }

    /// The Chat & Slack credentials and surroundings, as Settings shows
    /// them: whether a Slack token is saved, never the token.
    public struct Chat: Equatable, Sendable {
        public var hasSlackToken = false
        /// The Google Chat login exists with every Chat scope.
        public var hasChatAccess = false
        /// Where the `gws` command is; nil when it is not installed.
        public var gwsPath: String?
        /// The process that runs the chat monitor (HomeSpeaker.app, for the
        /// app) is running, and so can read messages.
        public var ownerRunning = false
        /// What the monitor last wrote about itself (`ChatMonitorStatusFile`),
        /// as far as it can be believed: with its owner not running it never
        /// reads as running, whatever the file says.
        public var monitor: ChatMonitorStatus?

        public init(hasSlackToken: Bool = false, hasChatAccess: Bool = false, gwsPath: String? = nil, ownerRunning: Bool = false,
                    monitor: ChatMonitorStatus? = nil) {
            self.hasSlackToken = hasSlackToken
            self.hasChatAccess = hasChatAccess
            self.gwsPath = gwsPath
            self.ownerRunning = ownerRunning
            self.monitor = monitor?.believed(ownerRunning: ownerRunning)
        }

        /// The monitor is polling: its owner runs and says so.
        public var monitorRunning: Bool { ownerRunning && monitor?.isRunning == true }

        /// What went wrong while it ran, when it is running.
        public var runtimeError: String? {
            guard monitorRunning, let error = monitor?.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !error.isEmpty else { return nil }
            return error
        }
    }

    public struct Status: Equatable {
        public var installed = true
        public var config = SpeakerConfig()
        public var volume: Volume?
        /// What HomeSpeaker is doing for the tool right now, if anything.
        public var busy: Job?
        /// The last thing worth saying: where a text was spoken, or why not.
        public var notice: String?
        public var quietNow = false
        /// The app draws a `choice` block; without it, a list stands in.
        public var offersChoice = false
        /// Why the settings file does not read, while it does not. Nothing
        /// is saved until it reads again.
        public var configProblem: String?
        public var section = Section.general
        /// The setup job HomeSpeaker is running, beside any speaker job.
        public var setupBusy: Job?
        /// The last thing a setup job said.
        public var setupNotice: String?
        public var account = Account()
        /// Nil until `--login-item status` has answered.
        public var loginItem: LoginItemState?
        /// What the last media-pause test said.
        public var mediaPauseReport: String?
        /// The homes this account sees; nil until they have been listed.
        public var homes: [HomeStructure]?
        public var selectedHomeId: String?
        /// The English voices installed on this Mac.
        public var voices: [LocalVoice] = []
        public var previewing = false
        /// A tap on a speaker removes it, rather than making it the default.
        public var removingSpeakers = false
        public var chat = Chat()
        public var agents = Agents()
        public var files = Files()
        /// The Client ID typed under Google Cloud and not saved yet.
        public var draftClientId = ""
        /// A client secret is typed and not saved yet. The field itself is
        /// always drawn empty: a secret goes in and never comes back out.
        public var draftClientSecretTyped = false
        /// The shared history (`BroadcastHistory`), newest first: what the
        /// app, `HomeSpeaker --say` and the Stop hook have spoken.
        public var recentBroadcasts: [BroadcastLogItem] = []

        public init() {}

        /// Not signed in, or signed in with no speakers yet: the island
        /// offers the first-run steps where the speaker picker would be.
        public var needsSetup: Bool { !account.isSignedIn || config.targets.isEmpty }
    }

    public static let releases = "https://github.com/VitruvianSoftware/vitruvian-core/releases?q=home-speaker"
    public static let maxSpeakerRows = 20
    /// How many of the history's entries the island lists.
    public static let maxRecentBroadcasts = 5
    /// How many homes the island's setup offers as buttons.
    public static let maxSetupHomes = 10
    public static let noRecentBroadcasts = "No recent announcements"
    public static let homeSpeakersOff = "Home speakers are off"
    public static let appNotReadingChat = "HomeSpeaker isn't running, so nothing is reading chat"
    public static let fixChatInSettings = "Fix it in Settings > Chat & Slack"
    /// What Preview says, in the voice picked.
    public static let previewText = "This is how announcements will sound on this Mac."

    public enum Block {
        public static let say = "say"
        public static let broadcasting = "broadcasting"
        public static let quiet = "quiet"
        public static let mute = "mute"
        public static let unmute = "unmute"
        public static let volume = "volume"
        public static let refresh = "refresh"
        public static let speakers = "speakers"
        public static let section = "section"
        public static let signIn = "signIn"
        public static let signOut = "signOut"
        public static let importAntigravity = "importAntigravity"
        public static let loginItem = "loginItem"
        public static let speechLength = "speechLength"
        public static let speakHome = "speakHome"
        public static let speakLocal = "speakLocal"
        public static let announceVolume = "announceVolume"
        public static let announceLevel = "announceLevel"
        public static let pauseMedia = "pauseMedia"
        public static let pauseExtra = "pauseExtra"
        public static let testMediaPause = "testMediaPause"
        public static let quietStart = "quietStart"
        public static let quietEnd = "quietEnd"
        public static let home = "home"
        public static let discover = "discover"
        public static let targets = "targets"
        public static let editSpeakers = "editSpeakers"
        public static let voice = "voice"
        public static let previewVoice = "previewVoice"
        public static let slackEnabled = "slackEnabled"
        public static let slackToken = "slackToken"
        public static let clearSlackToken = "clearSlackToken"
        public static let googleChatEnabled = "googleChatEnabled"
        public static let chatSource = "chatSource"
        public static let grantChat = "grantChat"
        public static let disconnectChat = "disconnectChat"
        public static let gwsAccount = "gwsAccount"
        public static let muteOwnMessages = "muteOwnMessages"
        public static let pollInterval = "pollInterval"
        public static let openGoogleCloud = "openGoogleCloud"
        public static let oauthClientId = "oauthClientId"
        public static let oauthClientSecret = "oauthClientSecret"
        public static let saveOAuthClient = "saveOAuthClient"
        public static let clearOAuthClient = "clearOAuthClient"
        public static let removeLegacyAgent = "removeLegacyAgent"
        public static let startChatMonitor = "startChatMonitor"
        public static let stopChatMonitor = "stopChatMonitor"
        // The island's first-run setup and its outputs. Their own ids, so
        // the island never answers to a settings control's.
        public static let setupSignIn = "setup.signIn"
        public static let setupImportAntigravity = "setup.importAntigravity"
        public static let setupDiscover = "setup.discover"
        public static let setupDiscoverHomePrefix = "setup.discoverHome."
        public static let outputHome = "output.home"
        public static let outputLocal = "output.local"

        /// The button that finds the speakers of the home at `index` in
        /// the homes listed.
        public static func setupDiscoverHome(_ index: Int) -> String { "\(setupDiscoverHomePrefix)\(index)" }

        /// The index a home button's id names; nil for any other id.
        public static func setupDiscoverHomeIndex(_ id: String) -> Int? {
            guard id.hasPrefix(setupDiscoverHomePrefix) else { return nil }
            return Int(id.dropFirst(setupDiscoverHomePrefix.count)).flatMap { $0 >= 0 ? $0 : nil }
        }

        /// What a button under AI Agents does to one agent. Its block id is
        /// `<action>:<agent>`, e.g. `installHook:claudeCode`.
        public enum AgentAction: String, CaseIterable, Sendable {
            case installHook, removeHook, disableRival, addInstruction
        }

        public static func agent(_ action: AgentAction, _ agent: CodingAgent) -> String {
            "\(action.rawValue):\(agent.rawValue)"
        }

        /// The action and agent an AI Agents button's id names; nil for any
        /// other id.
        public static func agentAction(_ id: String) -> (AgentAction, CodingAgent)? {
            let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let action = AgentAction(rawValue: parts[0]), let agent = CodingAgent(rawValue: parts[1]) else {
                return nil
            }
            return (action, agent)
        }
    }

    // MARK: - The island page

    public static func island(_ status: Status) -> UITree {
        UITree {
            heading("HomeSpeaker")
            configProblemBlocks(status)
            if !status.installed {
                text("HomeSpeaker is not installed on this Mac. The tool speaks through it.", style: .secondary)
                link("Get HomeSpeaker", url: releases)
            } else {
                chatWarningBlocks(status)
                // Before setup only this Mac can speak: offer the field
                // when it would.
                if !status.needsSetup || status.config.effectiveSpeakLocal {
                    field(Block.say, title: "Say something", value: "", placeholder: "Type it and press Return")
                }
                if let notice = status.notice { text(UIText.plain(notice), style: .caption) }
                if let busy = status.busy { text(UIText.plain(busyLine(busy)), style: .caption) }
                toggle(Block.broadcasting, "Broadcasting", isOn: status.config.enabled)
                toggle(Block.quiet, "Quiet hours", isOn: status.config.quietHoursEnabled ?? false)
                if status.quietNow, let until = status.config.quietHoursEnd {
                    text(UIText.plain("Quiet hours until \(until): what you type still plays"), style: .caption)
                }
                divider()
                if status.needsSetup {
                    setupBlocks(status)
                } else {
                    speakerBlocks(status)
                }
                outputBlocks(status)
            }
            divider()
            recentBroadcastBlocks(status)
        }
    }

    /// The settings file is there and does not read: said first, on both
    /// pages, since nothing is saved until it reads again.
    static func configProblemBlocks(_ status: Status) -> [UIBlock] {
        guard let problem = status.configProblem else { return [] }
        return [
            row(nil, "The settings file does not read", subtitle: UIText.plain(problem), icon: "exclamationmark.triangle.fill"),
            text("Nothing is saved until it reads again: fix or remove the file.", style: .caption),
        ]
    }

    /// The default speaker, its volume and the picker. With Home speakers
    /// off the volume is not read, so the controls give way to a note.
    static func speakerBlocks(_ status: Status) -> [UIBlock] {
        UITree {
            row(nil, UIText.plain(status.config.defaultDevice?.name ?? "No speaker picked"),
                subtitle: UIText.plain(volumeLine(status)), icon: "hifispeaker.2")
            if status.config.defaultDevice != nil && status.config.effectiveSpeakHome {
                if status.volume?.muted == true {
                    button(Block.unmute, "Unmute")
                } else {
                    button(Block.mute, "Mute")
                }
                field(Block.volume, title: "Volume (0 to 100)", value: status.volume?.percent.map(String.init) ?? "",
                      placeholder: "Type a level and press Return", kind: .number)
                button(Block.refresh, "Read the volume")
            }
            let speakers = status.config.uniqueTargets()
            if !speakers.isEmpty {
                text("Speaker", style: .caption)
                list(Block.speakers, speakerRows(speakers, chosen: status.config.defaultTarget))
            }
        }.blocks
    }

    /// The first run, inline: the island cannot open Settings. Sign in,
    /// then find the speakers, as Settings' General and Speakers do.
    static func setupBlocks(_ status: Status) -> [UIBlock] {
        let account = status.account
        let idle = status.setupBusy == nil
        let canRun = status.installed && idle
        let homes = status.homes ?? []
        return UITree {
            heading("Setup")
            if account.isSignedIn {
                row(nil, "1 · Google sign-in", subtitle: UIText.plain(account.email.map { "Signed in as \($0)" } ?? "Signed in"),
                    icon: "checkmark.circle.fill")
            } else {
                row(nil, "1 · Google sign-in", subtitle: "Not signed in", icon: "exclamationmark.triangle.fill")
                button(Block.setupSignIn, "Sign In…", style: .prominent, enabled: canRun && account.hasOAuthClient)
                if !account.hasOAuthClient {
                    text("Sign In needs a Google Cloud project of your own first: set it up in Settings > Google Cloud.", style: .caption)
                }
                if account.hasAntigravityTokens {
                    button(Block.setupImportAntigravity, "Import Antigravity login", enabled: idle)
                }
            }
            row(nil, "2 · Find your speakers",
                subtitle: UIText.plain(status.config.targets.isEmpty ? "No speakers yet" : "Speakers found"),
                icon: status.config.targets.isEmpty ? "circle" : "checkmark.circle.fill")
            button(Block.setupDiscover, "Find Speakers", style: .prominent, enabled: canRun && account.isSignedIn)
            if homes.count > 1 {
                text("Or pick the home to find them in:", style: .caption)
                for (index, home) in homes.prefix(maxSetupHomes).enumerated() {
                    button(Block.setupDiscoverHome(index), UIText.plain(home.name), enabled: canRun && account.isSignedIn)
                }
            }
            if let busy = status.setupBusy { text(UIText.plain(busyLine(busy)), style: .caption) }
            if let notice = status.setupNotice { text(UIText.plain(notice), style: .caption) }
        }.blocks
    }

    /// Where announcements go: the two outputs and what they add up to.
    static func outputBlocks(_ status: Status) -> [UIBlock] {
        let config = status.config
        let label = config.activeOutputsLabel
        return UITree {
            text("Speak on", style: .caption)
            toggle(Block.outputHome, "Home speakers", isOn: config.effectiveSpeakHome)
            toggle(Block.outputLocal, "This Mac", isOn: config.effectiveSpeakLocal)
            text(UIText.plain(label.isEmpty ? outputsFooter(config) : "Speaking on \(label)"), style: .caption)
        }.blocks
    }

    /// Why the chat monitor, switched on, reads nothing: each problem, and
    /// HomeSpeaker not running, then where to fix it. Empty while every
    /// source is off.
    public static func chatWarnings(_ status: Status) -> [String] {
        guard status.config.effectiveChatMonitor.anySourceEnabled else { return [] }
        var lines = monitorProblemLines(status)
        if !status.chat.ownerRunning { lines.append(appNotReadingChat) }
        return lines
    }

    /// The setup problems, then what went wrong while the monitor ran, as
    /// the menu bar shows it. The running error is left out when it only
    /// repeats a setup problem.
    public static func monitorProblemLines(_ status: Status) -> [String] {
        var lines = monitorProblems(status).map(\.localizedDescription)
        if status.config.effectiveChatMonitor.anySourceEnabled, let error = status.chat.runtimeError,
           !lines.contains(where: { error.contains($0) }) {
            lines.append(error)
        }
        return lines
    }

    static func chatWarningBlocks(_ status: Status) -> [UIBlock] {
        let lines = chatWarnings(status)
        guard !lines.isEmpty else { return [] }
        return UITree {
            problemRows(lines)
            text(UIText.plain(fixChatInSettings), style: .caption)
        }.blocks
    }

    /// A warning row a line, with no id to tap.
    static func problemRows(_ lines: [String]) -> [UIBlock] {
        lines.map { row(nil, UIText.plain($0), icon: "exclamationmark.triangle.fill") }
    }

    /// The newest of the shared history, as the menu bar's Recent
    /// Broadcasts lists it.
    static func recentBroadcastBlocks(_ status: Status) -> [UIBlock] {
        UITree {
            heading("Recent Broadcasts")
            if status.recentBroadcasts.isEmpty {
                text(UIText.plain(noRecentBroadcasts), style: .secondary)
            } else {
                for item in status.recentBroadcasts.prefix(maxRecentBroadcasts) {
                    row(nil, UIText.plain(item.text), subtitle: UIText.plain(broadcastLine(item)), icon: "text.bubble")
                }
            }
        }.blocks
    }

    /// "Say · Kitchen + This Mac · 14 Oct 2026 at 9:41": who, where, when.
    public static func broadcastLine(_ item: BroadcastLogItem) -> String {
        [item.source, item.targetName, item.timestamp.formatted(date: .abbreviated, time: .shortened)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    public static func busyLine(_ job: Job) -> String {
        switch job {
        case .say: return "Speaking…"
        case .volume: return "Reading the volume…"
        case .setVolume(let level): return "Setting the volume to \(level) %…"
        case .mute: return "Muting…"
        case .unmute: return "Unmuting…"
        case .signIn: return "Finish signing in in your browser…"
        case .app(.signOut): return "Signing out…"
        case .app(.discover(save: false, _)): return "Listing your homes…"
        case .app(.discover(save: true, _)): return "Finding speakers…"
        case .app(.loginItem(.status)): return "Reading Open at Login…"
        case .app(.loginItem): return "Changing Open at Login…"
        case .app(.testMediaPause): return "Pausing what this Mac plays for 3 seconds…"
        }
    }

    /// "Volume 40 %", "Muted", "Offline", or that it has not been read.
    public static func volumeLine(_ status: Status) -> String {
        guard status.config.defaultDevice != nil else { return "Pick one in HomeSpeaker, or below" }
        guard status.config.effectiveSpeakHome else { return homeSpeakersOff }
        guard let volume = status.volume else { return "Volume not read yet" }
        if volume.online == false { return "Offline" }
        if volume.muted == true { return "Muted" }
        return volume.percent.map { "Volume \($0) %" } ?? "Volume unknown"
    }

    public static func speakerRows(_ speakers: [(key: String, device: SpeakerDevice)], chosen: String) -> [UIListRow] {
        speakers.prefix(maxSpeakerRows).map { entry in
            UIListRow(id: entry.key, title: UIText.plain(entry.device.displayLine),
                      icon: entry.device.isWholeHome ? "house" : "hifispeaker",
                      trailing: entry.key == chosen ? "✓" : nil)
        }
    }

    // MARK: - The settings panel

    public static func settings(_ status: Status) -> UITree {
        UITree {
            picker(Block.section, title: "Section", value: status.section.rawValue,
                   options: Section.allCases.map { UIChoiceOption(value: $0.rawValue, title: UIText.plain($0.title)) },
                   choice: status.offersChoice)
            if !status.installed {
                text("HomeSpeaker is not installed on this Mac; these are its settings, which it reads too.", style: .caption)
            }
            configProblemBlocks(status)
            if let busy = status.setupBusy { text(UIText.plain(busyLine(busy)), style: .caption) }
            if let notice = status.setupNotice { text(UIText.plain(notice), style: .caption) }
            switch status.section {
            case .general: general(status)
            case .speakers: speakers(status)
            case .monitor: monitor(status)
            case .agents: agents(status)
            case .googleCloud: googleCloud(status)
            }
        }
    }

    /// A `choice` where the app draws one, else a list whose picked row
    /// carries a tick. Both answer with the option's value: the choice as
    /// `PanelEvent.text`, the list as `PanelEvent.row`.
    public static func picker(_ id: String, title: String, value: String, options: [UIChoiceOption], choice offersChoice: Bool) -> [UIBlock] {
        if offersChoice {
            return [choice(id, title: UIText.plain(title), value: value, options: Array(options.prefix(UILimits.maxChoiceOptions)))]
        }
        return [
            text(UIText.plain(title), style: .secondary),
            list(id, options.prefix(UILimits.maxListRows).map {
                UIListRow(id: $0.value, title: $0.title, trailing: $0.value == value ? "✓" : nil)
            }),
        ]
    }

    static func general(_ status: Status) -> [UIBlock] {
        let config = status.config
        let canRun = status.installed && status.setupBusy == nil
        return UITree {
            heading("Google Home Account")
            if status.account.isSignedIn {
                row(nil, UIText.plain(status.account.email ?? "Connected"), subtitle: "Signed in", icon: "checkmark.circle.fill")
                button(Block.signOut, "Sign Out", enabled: canRun)
                text("Sign Out also signs out of Google Chat and stops the Chat monitor.", style: .caption)
            } else {
                row(nil, "Not signed in", icon: "exclamationmark.triangle.fill")
                button(Block.signIn, "Sign In…", style: .prominent, enabled: canRun)
                if !status.account.hasOAuthClient {
                    text("Sign In needs a Google Cloud project of your own (Home API enabled) — a few minutes, once.", style: .caption)
                    button(Block.openGoogleCloud, "Set up…")
                }
                if status.account.hasAntigravityTokens {
                    button(Block.importAntigravity, "Import Antigravity login")
                    text("Reuses the Google Home sign-in from the Antigravity connector on this Mac.", style: .caption)
                }
            }

            heading("Broadcast Controls")
            toggle(Block.broadcasting, "Enable Voice Broadcasting", isOn: config.enabled)
            loginItem(status)
            picker(Block.speechLength, title: "Speak", value: config.effectiveSpeechLength.rawValue,
                   options: SpeechLength.allCases.map { UIChoiceOption(value: $0.rawValue, title: UIText.plain($0.label)) },
                   choice: status.offersChoice)
            toggle(Block.announceVolume, "Announce at a set volume", isOn: config.effectiveAnnounceVolumeEnabled)
            if config.effectiveAnnounceVolumeEnabled {
                field(Block.announceLevel, title: "Announcement volume (0 to 100)", value: String(config.effectiveAnnounceVolume),
                      kind: .number)
                text("The speaker goes back to its own volume when the announcement ends, unless someone changes it in the meantime. Needs HomeSpeaker running to put it back.",
                     style: .caption)
            }
            toggle(Block.pauseMedia, "Pause media while announcing", isOn: config.effectivePauseMedia)
            if config.effectivePauseMedia {
                field(Block.pauseExtra, title: "Resume after (0 to 10 s)", value: String(Int(config.effectivePauseMediaExtraSeconds)),
                      kind: .number)
                button(Block.testMediaPause, status.setupBusy == .app(.testMediaPause) ? "Paused…" : "Test", enabled: canRun)
                text(UIText.plain(status.mediaPauseReport
                                  ?? "Test pauses what this Mac is playing for 3 seconds, then resumes it. Works with Chrome, Brave, Edge, Arc, Vivaldi, Safari, Music, Spotify and QuickTime; browsers need Allow JavaScript from Apple Events."),
                     style: .caption)
            }

            heading("Quiet Hours")
            toggle(Block.quiet, "Enable Quiet Hours", isOn: config.quietHoursEnabled ?? false)
            field(Block.quietStart, title: "From (HH:mm)", value: config.quietHoursStart ?? "22:00")
            field(Block.quietEnd, title: "Until (HH:mm)", value: config.quietHoursEnd ?? "07:00")
            text("Automated announcements are held during quiet hours. What you type yourself still plays.", style: .caption)
        }.blocks
    }

    /// Open at Login, as `--login-item` last said it is. Waiting for
    /// approval reads as on, since HomeSpeaker asked for it; a HomeSpeaker
    /// that is not an app in Applications cannot have one at all.
    static func loginItem(_ status: Status) -> [UIBlock] {
        let title = "Open HomeSpeaker at Login"
        guard status.installed, let state = status.loginItem else {
            return [toggle(Block.loginItem, UIText.plain(title), isOn: false, enabled: false)]
        }
        let changing: Bool
        if case .app(.loginItem)? = status.setupBusy { changing = true } else { changing = false }
        switch state {
        case .enabled, .notRegistered:
            return [toggle(Block.loginItem, UIText.plain(title), isOn: state == .enabled, enabled: !changing && status.setupBusy == nil)]
        case .requiresApproval:
            return [
                toggle(Block.loginItem, UIText.plain(title), isOn: true, enabled: !changing && status.setupBusy == nil),
                text("Approve HomeSpeaker under System Settings > General > Login Items.", style: .caption),
            ]
        case .notFound:
            return [
                toggle(Block.loginItem, UIText.plain(title), isOn: false, enabled: false),
                text("Only HomeSpeaker.app, run from its app bundle, can open at login.", style: .caption),
            ]
        }
    }

    static func speakers(_ status: Status) -> [UIBlock] {
        let config = status.config
        let homes = status.homes ?? []
        return UITree {
            heading("Discovery")
            if homes.count > 1 {
                picker(Block.home, title: "Home", value: status.selectedHomeId ?? config.structureId,
                       options: homes.map { UIChoiceOption(value: $0.id, title: UIText.plain($0.name)) },
                       choice: status.offersChoice)
            } else if let name = config.structureName ?? homes.first?.name {
                row(nil, UIText.plain(name), subtitle: "Home", icon: "house")
            }
            button(Block.discover, config.hasSpeakers ? "Refresh from Google Home" : "Find Speakers", style: .prominent,
                   enabled: status.installed && status.account.isSignedIn && status.setupBusy == nil)
            text(status.account.isSignedIn
                 ? "Lists every speaker and display in your home that can play announcements."
                 : "Sign in under General first.", style: .caption)

            heading("Speakers & Displays")
            if config.targets.isEmpty {
                text("No speakers yet.", style: .secondary)
            } else {
                list(Block.targets, targetRows(config, removing: status.removingSpeakers))
                button(Block.editSpeakers, status.removingSpeakers ? "Done" : "Remove Speakers…")
                text(status.removingSpeakers
                     ? "Tap a speaker to remove it. Refresh from Google Home brings back any still in the home."
                     : "Tap a speaker to make it the default. Aliases that point at the same device appear once in the menu bar picker.",
                     style: .caption)
            }

            heading("Where to speak")
            toggle(Block.speakHome, "Home speakers", isOn: config.effectiveSpeakHome)
            toggle(Block.speakLocal, "This Mac", isOn: config.effectiveSpeakLocal)
            if config.effectiveSpeakLocal {
                picker(Block.voice, title: "Voice", value: config.effectiveLocalVoice, options: voiceOptions(status),
                       choice: status.offersChoice)
                button(Block.previewVoice, status.previewing ? "Speaking…" : "Preview", enabled: !status.previewing)
            }
            let footer = outputsFooter(config)
            if !footer.isEmpty { text(UIText.plain(footer), style: .caption) }
        }.blocks
    }

    /// What "Read Google Chat via" offers, in the app's words.
    public static func chatSourceTitle(_ source: ChatMonitorConfig.GoogleChatSource) -> String {
        switch source {
        case .auto: return "Automatic"
        case .api: return "Google API (this app's login)"
        case .gws: return "gws command-line tool"
        }
    }

    public static var pollIntervalTitle: String {
        "Poll interval (\(ChatMonitorConfig.minPollInterval) to \(ChatMonitorConfig.maxPollInterval) s)"
    }

    /// Why a source that is on cannot run, by the rules the chat monitor
    /// starts by. Nothing while every source is off.
    public static func monitorProblems(_ status: Status) -> [ChatMonitorError] {
        let monitor = status.config.effectiveChatMonitor
        guard monitor.anySourceEnabled else { return [] }
        return ChatMonitorService.setupProblems(config: monitor, hasSlackToken: status.chat.hasSlackToken,
                                                hasChatScopes: status.chat.hasChatAccess, gwsInstalled: status.chat.gwsPath != nil)
    }

    /// Chat & Slack, as HomeSpeaker's tab of that name: what reads the
    /// messages, the two sources and their credentials, and the options.
    /// The Slack token field is always empty: a token goes in, and only
    /// whether one is saved comes back out.
    static func monitor(_ status: Status) -> [UIBlock] {
        let monitor = status.config.effectiveChatMonitor
        let chat = status.chat
        let canRun = status.installed && status.setupBusy == nil
        return UITree {
            heading("Background Monitoring")
            if chat.ownerRunning {
                row(nil, "HomeSpeaker is running", icon: "bolt.fill")
            } else {
                row(nil, "HomeSpeaker is not running", icon: "moon.fill")
            }
            text("HomeSpeaker reads new messages in the background while Slack or Google Chat is on, and announces them on your speakers. Nothing is sent anywhere except to Google Home.",
                 style: .caption)
            if !chat.ownerRunning && monitor.anySourceEnabled {
                text("Open HomeSpeaker to start: it is what reads the messages.", style: .caption)
            }
            monitorRunBlocks(status)
            problemRows(monitorProblemLines(status))

            heading("Slack")
            toggle(Block.slackEnabled, "Announce Slack messages", isOn: monitor.slackEnabled)
            field(Block.slackToken, title: "User token (xoxp-…)", value: "",
                  placeholder: chat.hasSlackToken ? "Paste a new token to replace it" : "Paste the token and press Return",
                  kind: .secret)
            if chat.hasSlackToken {
                row(nil, "Slack token saved", icon: "checkmark.circle.fill")
                button(Block.clearSlackToken, "Clear Slack Token")
            } else {
                row(nil, "No Slack token saved", icon: "exclamationmark.circle")
            }
            text("Create a Slack app with the search:read user scope and paste its user token. The token is stored only on this Mac.",
                 style: .caption)

            heading("Google Chat")
            toggle(Block.googleChatEnabled, "Announce Google Chat messages", isOn: monitor.googleChatEnabled)
            picker(Block.chatSource, title: "Read Google Chat via", value: monitor.googleChatSource.rawValue,
                   options: ChatMonitorConfig.GoogleChatSource.allCases.map {
                       UIChoiceOption(value: $0.rawValue, title: UIText.plain(chatSourceTitle($0)))
                   },
                   choice: status.offersChoice)
            if monitor.googleChatSource != .gws {
                if chat.hasChatAccess {
                    row(nil, "Chat access granted", icon: "checkmark.circle.fill")
                    button(Block.disconnectChat, "Disconnect", enabled: canRun)
                } else {
                    text("Google grants Chat access separately from Home — a second sign-in.", style: .caption)
                    button(Block.grantChat, "Grant…", enabled: canRun)
                }
            }
            if monitor.googleChatSource != .api {
                if let path = chat.gwsPath {
                    row(nil, "gws is installed", subtitle: UIText.plain(path), icon: "checkmark.circle.fill")
                    text("gws must be signed in: run gws auth login in Terminal.", style: .caption)
                    field(Block.gwsAccount, title: "gws account (optional, e.g. you@gmail.com)", value: monitor.gwsAccount)
                } else {
                    text("gws is not installed. Install the Google Workspace CLI and run gws auth login to use it.", style: .caption)
                }
            }
            text("Automatic uses the API when its permission is granted, otherwise gws if installed. “Skip messages I sent” needs your Google user id, which only an API sign-in provides.",
                 style: .caption)

            heading("Options")
            toggle(Block.muteOwnMessages, "Skip messages I sent", isOn: monitor.muteOwnMessages)
            field(Block.pollInterval, title: UIText.plain(pollIntervalTitle), value: String(monitor.clampedPollInterval), kind: .number)
        }.blocks
    }

    /// The monitor itself, as the app's Settings shows it: Running or
    /// Stopped, Start or Stop while HomeSpeaker runs and a source is on, and
    /// while it runs, when it last polled, who Slack says we are and how
    /// Google Chat is read.
    static func monitorRunBlocks(_ status: Status) -> [UIBlock] {
        let chat = status.chat
        let running = chat.monitorRunning
        return UITree {
            row(nil, running ? "Chat monitor running" : "Chat monitor stopped",
                icon: running ? "dot.radiowaves.left.and.right" : "pause.circle")
            if chat.ownerRunning && status.config.effectiveChatMonitor.anySourceEnabled {
                if running {
                    button(Block.stopChatMonitor, "Stop")
                } else {
                    button(Block.startChatMonitor, "Start", style: .prominent)
                }
            }
            if running, let monitor = chat.monitor {
                if let polled = monitor.lastPollDate {
                    text(UIText.plain(polledLine(polled)), style: .caption)
                }
                if let who = monitor.slackIdentity, !who.isEmpty {
                    row(nil, UIText.plain("Signed in as \(who)"), subtitle: "Slack", icon: "person.crop.circle")
                }
                if let via = monitor.activeGoogleChatBackend, !via.isEmpty {
                    text(UIText.plain(readingViaLine(via)), style: .caption)
                }
            }
        }.blocks
    }

    /// "Polled at 9:41 AM".
    public static func polledLine(_ date: Date) -> String {
        "Polled at \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// "Currently reading via the Google API", in the app's words.
    public static func readingViaLine(_ backend: String) -> String {
        let name: String
        switch backend {
        case "api": name = "the Google API"
        case "gws": name = "gws"
        default: name = backend
        }
        return "Currently reading via \(name)"
    }

    /// What a hook says when it is there but HomeSpeaker, which it runs, is not.
    public static let hookWithoutHomeSpeaker = "Points at HomeSpeaker, which isn't installed — it can't speak"

    /// AI Agents, as HomeSpeaker's tab of that name: each coding agent's
    /// hook or instruction, and the 1.x launch agent to clean up. Reading
    /// state, removing and the instruction need no HomeSpeaker; installing
    /// a hook does, since a hook runs it.
    static func agents(_ status: Status) -> [UIBlock] {
        UITree {
            for agent in status.agents.statuses {
                agentBlocks(agent, status)
            }
            if status.agents.legacyLaunchAgent {
                heading("Cleanup")
                row(nil, "Legacy chat-monitor launch agent", subtitle: "Installed by HomeSpeaker 1.x. Chat monitoring now runs inside the app.",
                    icon: "trash")
                button(Block.removeLegacyAgent, "Remove")
            }
        }.blocks
    }

    static func agentBlocks(_ st: AgentIntegration.AgentStatus, _ status: Status) -> [UIBlock] {
        let name = st.agent.displayName
        let file = st.agent.instructionFileName
        return UITree {
            heading(UIText.plain(name))
            switch st.section {
            case .notInstalled:
                row(nil, UIText.plain("\(name) hook"), subtitle: "Not installed on this Mac. Nothing to do here.", icon: "minus.circle")
            case .instructionDriven:
                if st.configuredByInstruction {
                    row(nil, UIText.plain("\(name) announcements"), subtitle: "Configured", icon: "checkmark.circle.fill")
                    text(UIText.plain("\(file) tells \(name) to speak each reply through HomeSpeaker's speaker settings."), style: .caption)
                } else {
                    row(nil, UIText.plain("\(name) announcements"), subtitle: "Not set up", icon: "exclamationmark.circle")
                    button(Block.agent(.addInstruction, st.agent), "Add Instruction", style: .prominent)
                    text(UIText.plain("Adds one line to \(file) asking \(name) to speak each reply. \(name)'s CLI does not run end-of-turn hooks, so this is the only path."),
                         style: .caption)
                }
            case .hook:
                hookBlocks(st, status)
            }
            text(UIText.plain(st.agent == .claudeCode
                              ? "Adds one entry to the Stop hooks in ~/.claude/settings.json. Other hooks you have are left untouched."
                              : "Reads the broadcast settings and speaker from the same files as HomeSpeaker, so switching speakers here changes where \(name) speaks."),
                 style: .caption)
        }.blocks
    }

    /// An agent HomeSpeaker hooks: the "spoken twice" warning, the hook's
    /// state and what it runs. A hook left behind by a HomeSpeaker that is
    /// gone says so and offers Remove, never an update it cannot make.
    static func hookBlocks(_ st: AgentIntegration.AgentStatus, _ status: Status) -> [UIBlock] {
        let name = st.agent.displayName
        let title = UIText.plain("\(name) hook")
        return UITree {
            if let warning = st.speaksTwiceWarning {
                row(nil, UIText.plain(warning), icon: "exclamationmark.triangle.fill")
                button(Block.agent(.disableRival, st.agent), "Turn it off")
            }
            switch st.hook {
            case .installed:
                row(nil, title, subtitle: "Installed", icon: "checkmark.circle.fill")
                button(Block.agent(.removeHook, st.agent), "Remove")
            case .stale where !status.installed:
                row(nil, title, subtitle: UIText.plain(hookWithoutHomeSpeaker), icon: "exclamationmark.triangle.fill")
                button(Block.agent(.removeHook, st.agent), "Remove", enabled: true)
            case .stale:
                row(nil, title, subtitle: "Needs update", icon: "arrow.triangle.2.circlepath")
                button(Block.agent(.installHook, st.agent), "Update Hook", style: .prominent)
            case .notInstalled:
                row(nil, title, subtitle: "Not installed", icon: "circle")
                button(Block.agent(.installHook, st.agent), "Install Hook", style: .prominent, enabled: status.installed)
                if !status.installed { text("Install HomeSpeaker first: the hook runs it.", style: .caption) }
            }
            text("Speaks a one-sentence summary of each reply when a turn finishes.", style: .caption)
            if status.installed, let command = status.agents.hookCommands[st.agent] {
                text(UIText.plain(command), style: .caption)
            }
            if st.configuredByInstruction {
                text(UIText.plain(st.hook == .installed
                                  ? "Your \(st.agent.instructionFileName) also tells \(name) to broadcast on its own. With the hook installed, remove that instruction to avoid hearing replies twice."
                                  : "Already announcing: your \(st.agent.instructionFileName) tells \(name) to broadcast on its own. The hook is optional — it makes that deterministic and needs no model cooperation."),
                     style: .caption)
            }
        }.blocks
    }

    public static let cloudConsole = "https://console.cloud.google.com/apis/credentials"

    /// Google Cloud, as HomeSpeaker's tab of that name: the five steps to
    /// a project of one's own, the client pasted in and saved with one
    /// button, and where the files are. The secret field is always drawn
    /// empty; what is typed there is held until Save.
    static func googleCloud(_ status: Status) -> [UIBlock] {
        let account = status.account
        let canSave = !status.draftClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let secretHint: UIText
        if status.draftClientSecretTyped {
            secretHint = "Typed — press Save to keep it"
        } else if account.hasCustomOAuthClientSecret {
            secretHint = "Saved — type a new one to replace it"
        } else {
            secretHint = "Paste the client secret"
        }
        return UITree {
            heading("Your Google Cloud project")
            row(nil, "1 · Create or pick a project", subtitle: "console.cloud.google.com — use the Google account that owns your home.")
            row(nil, "2 · Enable the Home API",
                subtitle: "APIs & Services › Library › “Home API”. Also enable the Google Chat API if you want chat announcements.")
            row(nil, "3 · Configure the consent screen, then Publish",
                subtitle: "Google Auth Platform › Audience › External. Leave it on Testing and Google expires your login every 7 days.")
            row(nil, "4 · Create an OAuth client",
                subtitle: "Desktop app: nothing else to enter. Web application: add every callback below to Authorised redirect URIs.")
            text(UIText.plain(GoogleAuth.allRedirectURIs.joined(separator: "\n")), style: .caption)
            link("Open Google Cloud Console", url: cloudConsole)
            text(account.hasBundledOAuthClient
                 ? "This build also ships with a shared OAuth client. Fill in your own below to use your project instead; yours always wins."
                 : "One-time setup. Your client ID and secret never leave this Mac.", style: .caption)

            heading("Step 5 · Paste the client here")
            field(Block.oauthClientId, title: "Client ID", value: status.draftClientId, placeholder: "…apps.googleusercontent.com")
            field(Block.oauthClientSecret, title: "Client secret", value: "", placeholder: secretHint, kind: .secret)
            button(Block.saveOAuthClient, "Save", style: .prominent, enabled: canSave)
            if let id = account.customOAuthClientId {
                row(nil, "Your OAuth client is saved", subtitle: UIText.plain(id), icon: "checkmark.circle.fill")
                button(Block.clearOAuthClient, "Clear")
            }

            heading("Files")
            row(nil, "Settings", subtitle: UIText.plain(status.files.settings))
            row(nil, "Secrets", subtitle: UIText.plain(status.files.secrets))
            row(nil, "Tool version", subtitle: UIText.plain(status.files.toolVersion))
            if status.installed {
                row(nil, "HomeSpeaker version", subtitle: UIText.plain(status.files.homeSpeakerVersion ?? "Unknown"))
            }
        }.blocks
    }

    /// Every alias, by its key: the device's name, the alias and room under
    /// it, and which is the default.
    public static func targetRows(_ config: SpeakerConfig, removing: Bool) -> [UIListRow] {
        config.targets.keys.sorted().prefix(UILimits.maxListRows).compactMap { key in
            guard let device = config.targets[key] else { return nil }
            var subtitle = "Alias: \(key)"
            if let room = device.room, !room.isEmpty { subtitle += " • Room: \(room)" }
            let trailing: UIText? = removing ? "Remove" : (key == config.defaultTarget ? "Default" : nil)
            return UIListRow(id: key, title: UIText.plain(device.name), subtitle: UIText.plain(subtitle),
                             icon: device.isWholeHome ? "house" : "hifispeaker", trailing: trailing)
        }
    }

    /// The installed voices, and first, when the saved voice is not one of
    /// them, the saved voice under a label that says what plays instead: the
    /// picker never quietly changes it.
    public static func voiceOptions(_ status: Status) -> [UIChoiceOption] {
        let saved = status.config.effectiveLocalVoice
        var options = status.voices.map { UIChoiceOption(value: $0.id, title: UIText.plain($0.pickerLabel)) }
        if !status.voices.contains(where: { $0.id == saved }) {
            options.insert(UIChoiceOption(value: saved, title: UIText.plain(missingVoiceLabel(saved, voices: status.voices))), at: 0)
        }
        return options
    }

    public static func missingVoiceLabel(_ id: String, voices: [LocalVoice]) -> String {
        let name = id.split(separator: ".").last.map(String.init) ?? id
        let fallback = LocalSpeaker.chooseVoice(requested: id, from: voices).voice?.name ?? "the system voice"
        return "\(name) (not installed; using \(fallback))"
    }

    /// What the two outputs mean together, as HomeSpeaker's Settings says it.
    public static func outputsFooter(_ config: SpeakerConfig) -> String {
        if !config.effectiveSpeakHome && !config.effectiveSpeakLocal {
            return "Both are off, so nothing is spoken anywhere."
        }
        var lines: [String] = []
        if config.effectiveSpeakLocal {
            lines.append("This Mac speaks at its own volume. More voices: System Settings › Accessibility › Read & Speak › System voice › ⓘ › Voice, then download an \"(Enhanced)\" voice.")
        }
        if config.effectiveSpeakHome && config.effectiveSpeakLocal {
            lines.append("Both speak at the same time. Quiet hours and pausing media cover both.")
        }
        return lines.joined(separator: " ")
    }
}
