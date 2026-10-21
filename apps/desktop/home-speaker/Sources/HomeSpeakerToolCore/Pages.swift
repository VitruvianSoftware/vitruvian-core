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
    /// The parts of the settings panel: one shown at a time, or every one
    /// under its own heading for an app that draws sections.
    public enum Section: String, CaseIterable, Sendable {
        case general, speakers, monitor, agents, googleCloud

        public var title: String {
            switch self {
            case .general: return "General"
            case .speakers: return "Speakers"
            case .monitor: return "Chats"
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
        public var history = ""
        public var toolVersion = ToolVersion.current
        /// The installed HomeSpeaker's version; nil when it cannot be read.
        public var homeSpeakerVersion: String?

        public init(settings: String = "", secrets: String = "", history: String = "", toolVersion: String = ToolVersion.current,
                    homeSpeakerVersion: String? = nil) {
            self.settings = settings
            self.secrets = secrets
            self.history = history
            self.toolVersion = toolVersion
            self.homeSpeakerVersion = homeSpeakerVersion
        }
    }

    /// The Chats credentials and surroundings, as Settings shows
    /// them: whether a Slack or Beeper token is saved, never the token.
    public struct Chat: Equatable, Sendable {
        public var hasSlackToken = false
        public var hasBeeperToken = false
        /// A Gemini API key is saved, for the rewording and the Gemini voice.
        public var hasGeminiKey = false
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
                    monitor: ChatMonitorStatus? = nil, hasBeeperToken: Bool = false, hasGeminiKey: Bool = false) {
            self.hasSlackToken = hasSlackToken
            self.hasBeeperToken = hasBeeperToken
            self.hasGeminiKey = hasGeminiKey
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
        /// The app draws a `chips` block (`ProtocolFeature.chips`): Beeper's
        /// networks are then one block, not a switch each.
        public var offersChips = false
        /// The app groups a page into sections (`ProtocolFeature.sections`).
        public var offersSections = false
        /// The app opens HomeSpeaker's settings panel when the tool's answer
        /// names it (`HomeSpeakerTool.openSettingsFeature`): the island's
        /// last line is then a "More settings…" button, not where to look.
        public var opensSettings = false
        /// Why the settings file does not read, while it does not. Nothing
        /// is saved until it reads again.
        public var configProblem: String?
        /// The section picked, for an app that does not draw sections.
        public var section = Section.general
        /// The setup job HomeSpeaker is running, beside any speaker job.
        public var setupBusy: Job?
        /// The last thing a setup job said.
        public var setupNotice: String?
        public var account = Account()
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
        /// Which HomeSpeaker is in use, and the step the person is on.
        public var door = DoorState()
        /// What the engine said when it last put a speaker back
        /// (`VolumeRestoreCoordinator.lastReport`); nil until it has.
        public var volumeRestoreReport: String?

        public init() {}

        /// Not signed in, or signed in with no speakers yet: the island
        /// offers the first-run steps where the speaker picker would be.
        public var needsSetup: Bool { !account.isSignedIn || config.targets.isEmpty }
    }

    public static let releases = "https://github.com/VitruvianSoftware/vitruvian-core/releases?q=home-speaker"
    public static let maxSpeakerRows = 20
    /// How many of the history's entries the island lists: the island has
    /// little room, and the menu bar app keeps the rest.
    public static let maxRecentBroadcasts = 3
    /// The island's volume menu: every ten, 0 to 100.
    public static let volumeSteps = Array(stride(from: 0, through: 100, by: 10))
    /// How many homes the island's setup offers as buttons.
    public static let maxSetupHomes = 10
    public static let noRecentBroadcasts = "No recent announcements"
    public static let homeSpeakersOff = "Home speakers are off"
    /// A volume or mute that waited, dropped: it was for the old speaker.
    public static let pendingDropped = "The waiting volume or mute change was dropped: the speaker changed"
    /// Where to fix a chat problem, for an app that cannot open HomeSpeaker's
    /// settings (3.57 and before): the Section menu's Chats.
    public static let fixChatInSettings = "Fix it in Vitruvian Settings › Extensions › HomeSpeaker › Section: Chats"
    /// The same, for an app that draws every section on one page: there is
    /// no Section menu, only Chats on the page.
    public static let fixChatInSettingsOnOnePage = "Fix it in Vitruvian Settings › Extensions › HomeSpeaker › Chats"
    /// The warning's button, for an app that can: opens HomeSpeaker's
    /// settings on Chats.
    public static let openChatSettingsButton = "Open Chats…"
    /// The same button for an app that draws every section on one page:
    /// the answer opens Settings at its top and cannot name a section.
    public static let openSettingsButton = "Open Settings…"
    /// The token fields' save buttons, as HomeSpeaker's own Settings has.
    public static let saveTokenButton = "Save Token"
    public static let slackTokenTitle = "User token (xoxp-…)"
    public static let beeperTokenTitle = "Access token"
    /// The island's token fields, under a source switched on with no token.
    public static let pasteSlackToken = "Paste Slack token and press Return"
    public static let pasteBeeperToken = "Paste Beeper token and press Return"
    /// The Gemini API key's field, its island placeholder and its button.
    public static let geminiKeyTitle = "Gemini API key"
    public static let pasteGeminiKey = "Paste Gemini API key and press Return"
    public static let saveKeyButton = "Save Key"
    /// The custom style's field.
    public static let customStyleTitle = "Custom style"
    public static let customStylePlaceholder = "e.g. One short sentence, like a ship captain"
    /// Under the Style picker, for an app that draws help.
    public static let styleHelp = "How a coding agent's reply is worded before it is spoken. "
        + "Anything but As written has a language model say it in a sentence or two; "
        + "chat messages and what you type are always read as written."
    public static let styleModelHelp = "Apple's model runs on this Mac (macOS 26 and Apple Intelligence). "
        + "Gemini sends the reply to Google with your Gemini API key. "
        + "If one fails, the next is used: Gemini, then Apple, then the reply as written."
    public static let geminiKeyHelp = "Make a key at aistudio.google.com › Get API key. "
        + "With Gemini TTS, what this Mac says is sent to Google to be spoken; "
        + "with no key, or when Gemini fails, this Mac uses the Mac voice below."
    /// Where the rest of HomeSpeaker's settings are, at the foot of the
    /// island, for an app that cannot open them (3.57 and before).
    public static let moreSettings = "More settings: Vitruvian Settings › Extensions › HomeSpeaker"
    /// The button that opens them, for an app that can.
    public static let moreSettingsButton = "More settings…"
    /// The island's button that speaks what is on the clipboard.
    public static let sayClipboardButton = "Speak clipboard"
    /// What Preview says, in the voice picked.
    public static let previewText = "This is how announcements will sound on this Mac."

    public enum Block {
        public static let say = "say"
        /// The island's button that speaks the clipboard, as the
        /// `sayClipboard` command does.
        public static let sayClipboard = "sayClipboard"
        public static let broadcasting = "broadcasting"
        public static let quiet = "quiet"
        /// The island's Mute switch: on mutes, off unmutes.
        public static let mute = "mute"
        public static let volume = "volume"
        public static let speakers = "speakers"
        public static let section = "section"
        public static let signIn = "signIn"
        public static let signOut = "signOut"
        public static let importAntigravity = "importAntigravity"
        public static let speechLength = "speechLength"
        public static let announcementStyle = "announcementStyle"
        public static let customStylePrompt = "customStylePrompt"
        public static let styleModel = "styleModel"
        public static let localEngine = "localEngine"
        public static let geminiVoice = "geminiVoice"
        public static let geminiApiKey = "geminiApiKey"
        public static let saveGeminiApiKey = "saveGeminiApiKey"
        public static let clearGeminiApiKey = "clearGeminiApiKey"
        public static let speakHome = "speakHome"
        public static let speakLocal = "speakLocal"
        public static let speakPhone = "speakPhone"
        public static let phonePauseMedia = "phonePauseMedia"
        public static let phoneHeadphonesOnly = "phoneHeadphonesOnly"
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
        /// Saves what was pasted into the Slack token field, as Return does.
        public static let saveSlackToken = "saveSlackToken"
        public static let beeperEnabled = "beeperEnabled"
        public static let beeperToken = "beeperToken"
        public static let clearBeeperToken = "clearBeeperToken"
        public static let saveBeeperToken = "saveBeeperToken"
        public static let beeperAnnounce = "beeperAnnounce"
        public static let googleChatEnabled = "googleChatEnabled"
        /// Each coding agent's own switch, under Broadcasting: on the
        /// island and in Settings › AI Agents.
        public static let claudeCodeEnabled = "claudeCodeEnabled"
        public static let antigravityEnabled = "antigravityEnabled"
        public static let opencodeEnabled = "opencodeEnabled"
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
        /// The island's last line, as a button: opens Settings on
        /// HomeSpeaker's detail.
        public static let moreSettings = "moreSettings"
        /// The island's chat warning, as a button: opens Settings on
        /// HomeSpeaker's Chats.
        public static let openChatSettings = "openChatSettings"
        // The island's first-run setup and its outputs. Their own ids, so
        // the island never answers to a settings control's.
        public static let setupSignIn = "setup.signIn"
        public static let setupImportAntigravity = "setup.importAntigravity"
        public static let setupDiscover = "setup.discover"
        public static let setupDiscoverHomePrefix = "setup.discoverHome."
        public static let outputHome = "output.home"
        public static let outputLocal = "output.local"
        public static let outputPhone = "output.phone"
        /// A Recent Broadcasts row: a tap speaks it again.
        public static let replayPrefix = "replay."
        public static let beeperNetworkPrefix = "beeper.network."
        /// Beeper's networks as one `chips` block, for an app that draws
        /// one (`Status.offersChips`): a chip on reads the network, off
        /// mutes it.
        public static let beeperNetworks = "beeperNetworks"

        /// The switch for `agent`'s announcements.
        public static func agentEnabled(_ agent: CodingAgent) -> String {
            switch agent {
            case .claudeCode: return claudeCodeEnabled
            case .antigravity: return antigravityEnabled
            case .opencode: return opencodeEnabled
            }
        }

        /// The agent a switch's id names; nil for any other id.
        public static func agentEnabledAgent(_ id: String) -> CodingAgent? {
            CodingAgent.allCases.first { agentEnabled($0) == id }
        }

        /// The row of the broadcast `id` in the history. By its id, not its
        /// place: an announcement added between drawing and the tap moves
        /// every row down one, and would replay the wrong one.
        public static func replayBroadcast(_ id: UUID) -> String { "\(replayPrefix)\(id.uuidString)" }

        /// The broadcast a row's id names; nil for any other id.
        public static func replayBroadcastId(_ id: String) -> UUID? {
            guard id.hasPrefix(replayPrefix) else { return nil }
            return UUID(uuidString: String(id.dropFirst(replayPrefix.count)))
        }

        /// A Beeper network's switch: on reads it, off mutes it. By the
        /// network's key (`BeeperClient.networkKey`): only `a-z`, `0-9`,
        /// `_` and `-`, and at most `BeeperClient.maxNetworkKeyLength`
        /// (64) long, which keeps the id within the protocol's 128. The
        /// cap is the engine's; `beeperNetworkKey` checks the characters
        /// only, not the length.
        public static func beeperNetwork(_ key: String) -> String { "\(beeperNetworkPrefix)\(key)" }

        /// The network key a switch's id names; nil for any other id, or a
        /// key no network has.
        public static func beeperNetworkKey(_ id: String) -> String? {
            guard id.hasPrefix(beeperNetworkPrefix) else { return nil }
            let key = id.dropFirst(beeperNetworkPrefix.count)
            guard !key.isEmpty, key.unicodeScalars.allSatisfy({
                ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-"
            }) else { return nil }
            return String(key)
        }

        /// The button that finds the speakers of the home at `index` in
        /// the homes listed.
        public static func setupDiscoverHome(_ index: Int) -> String { "\(setupDiscoverHomePrefix)\(index)" }

        /// The index a home button's id names; nil for any other id.
        public static func setupDiscoverHomeIndex(_ id: String) -> Int? {
            guard id.hasPrefix(setupDiscoverHomePrefix) else { return nil }
            return Int(id.dropFirst(setupDiscoverHomePrefix.count)).flatMap { $0 >= 0 ? $0 : nil }
        }

        /// What every stand-in row id starts with (`rowId`).
        public static let rowIdPrefix = "row."

        /// The id of a list row, or the value of a choice's option, that
        /// stands for `value`: a speaker's key, a home's id, a voice. The
        /// value itself when the protocol takes it as a name
        /// (`ManifestRules.isWellFormedName`), as every value HomeSpeaker
        /// makes is. Else, for one written by hand (`Living Room`,
        /// `den:2`, one too long), `row.` and 16 hex digits made from it,
        /// the same every time: Vitruvian refuses a whole page over one id
        /// it does not take. A value that starts with `row.` is made a
        /// stand-in too, so no value is ever read as another's.
        public static func rowId(_ value: String) -> String {
            if ManifestRules.isWellFormedName(value), !value.hasPrefix(rowIdPrefix) { return value }
            // FNV-1a, 64 bits: not `hashValue`, which changes from run to run.
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in value.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
            let hex = String(hash, radix: 16)
            return rowIdPrefix + String(repeating: "0", count: 16 - hex.count) + hex
        }

        /// The value among `values` that the row or option `id` stands
        /// for (`rowId`); nil for none of them. A value as it is also
        /// reads, as before: a menu an older tool drew answers with the key
        /// itself.
        public static func rowValue(_ id: String?, among values: some Sequence<String>) -> String? {
            guard let id else { return nil }
            let values = Array(values)
            return values.first { rowId($0) == id } ?? values.first { $0 == id }
        }

        /// What a button under AI Agents does to one agent. Its block id is
        /// `<action>.<agent>`, e.g. `installHook.claudeCode`. Never a colon:
        /// a block id is a protocol name (letters, digits, `.`, `-`, `_`),
        /// and Vitruvian refuses the whole page over one that is not
        /// (HomeSpeaker 1.27.1's `installHook:claudeCode` did that).
        public enum AgentAction: String, CaseIterable, Sendable {
            case installHook, removeHook, disableRival, addInstruction
        }

        public static func agent(_ action: AgentAction, _ agent: CodingAgent) -> String {
            "\(action.rawValue).\(agent.rawValue)"
        }

        /// The action and agent an AI Agents button's id names; nil for any
        /// other id. The colon of a page an older tool drew still reads.
        public static func agentAction(_ id: String) -> (AgentAction, CodingAgent)? {
            for separator: Character in [".", ":"] {
                let parts = id.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                if parts.count == 2, let action = AgentAction(rawValue: parts[0]), let agent = CodingAgent(rawValue: parts[1]) {
                    return (action, agent)
                }
            }
            return nil
        }
    }

    // MARK: - The island page

    /// The island. While the other HomeSpeaker is in use, the quiet card
    /// (or the step the person started from it) is all there is; otherwise
    /// the choice card, when there is one, comes first. No heading: the
    /// island's header, and the menu bar panel's card, already name it.
    public static func island(_ status: Status) -> UITree {
        var quietFor: HomeSpeakerProfile.Door?
        if case .quiet(let other) = status.door.role { quietFor = other }
        if let other = quietFor {
            return UITree {
                if status.door.step == nil {
                    quietCardBlocks(other: other, starting: status.door.otherStarting)
                } else {
                    doorCardBlocks(status)
                }
                doorReportBlocks(status)
                moreSettingsBlocks(status)
            }
        }
        return UITree {
            doorCardBlocks(status)
            doorReportBlocks(status)
            configProblemBlocks(status)
            chatWarningBlocks(status)
            // Before setup only this Mac or this phone can speak: offer the field
            // when it would.
            if !status.needsSetup || status.config.effectiveSpeakLocal || status.config.effectiveSpeakPhone {
                field(Block.say, title: "Say something", value: "", placeholder: "Type it and press Return")
                // The `sayClipboard` command, here because the island's
                // Tools grid leaves an extension's commands to its own page.
                button(Block.sayClipboard, UIText.plain(sayClipboardButton))
            }
            if let notice = status.notice { text(UIText.plain(notice), style: .caption) }
            if let busy = shownBusy(status) { text(UIText.plain(busyLine(busy)), style: .caption) }
            toggle(Block.broadcasting, "Broadcasting", isOn: status.config.enabled)
            speakPicker(status)
            stylePicker(status)
            customStyleBlocks(status)
            toggle(Block.quiet, "Quiet hours", isOn: status.config.quietHoursEnabled ?? false)
            // The times only while quiet hours are on: off, they hold nothing.
            if status.config.quietHoursEnabled == true {
                quietHourBlocks(status)
            }
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
            divider()
            sourceBlocks(status)
            divider()
            recentBroadcastBlocks(status)
            moreSettingsBlocks(status)
        }
    }

    /// The speaker job the island mentions. The read on every opening is
    /// not, while a level from before is shown: it would only make the
    /// page jump each time it opens.
    static func shownBusy(_ status: Status) -> Job? {
        guard let busy = status.busy else { return nil }
        if busy == .volume, status.volume?.percent != nil { return nil }
        return busy
    }

    /// The island's last line: the rest of the settings. A button that
    /// opens them, for an app that can; otherwise where to find them.
    static func moreSettingsBlocks(_ status: Status) -> [UIBlock] {
        if status.opensSettings {
            return [button(Block.moreSettings, UIText.plain(moreSettingsButton))]
        }
        return [text(UIText.plain(moreSettings), style: .caption)]
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

    /// The default speaker, its volume and Mute. Where the app draws a
    /// `choice`, the speaker and the volume are one-line menus; before 3.48
    /// they are the list and the typed field. With Home speakers off the
    /// volume is not read, so its controls give way to a note.
    static func speakerBlocks(_ status: Status) -> [UIBlock] {
        let config = status.config
        let speakers = config.uniqueTargets()
        return UITree {
            if status.offersChoice {
                choice(Block.speakers, title: "Speaker", value: config.defaultDevice == nil ? "" : Block.rowId(config.defaultTarget),
                       options: speakerOptions(status))
            } else if !speakers.isEmpty {
                text("Speaker", style: .caption)
                list(Block.speakers, speakerRows(speakers, chosen: config.defaultTarget))
            }
            if config.defaultDevice != nil && config.effectiveSpeakHome {
                if status.offersChoice {
                    choice(Block.volume, title: "Volume", value: status.volume?.percent.map(String.init) ?? "",
                           options: volumeOptions(status.volume?.percent))
                } else {
                    field(Block.volume, title: "Volume (0 to 100)", value: status.volume?.percent.map(String.init) ?? "",
                          placeholder: "Type a level and press Return", kind: .number)
                }
                toggle(Block.mute, "Mute", isOn: status.volume?.muted == true)
            }
            if let note = speakerNote(status) { text(UIText.plain(note), style: .caption) }
        }.blocks
    }

    /// The speaker menu: each speaker once, and "None picked" first while
    /// no speaker is the default, so the menu always shows what is so.
    static func speakerOptions(_ status: Status) -> [UIChoiceOption] {
        var options = status.config.uniqueTargets().map {
            UIChoiceOption(value: Block.rowId($0.key), title: UIText.plain($0.device.displayLine))
        }
        if status.config.defaultDevice == nil { options.insert(UIChoiceOption(value: "", title: "None picked"), at: 0) }
        return Array(options.prefix(UILimits.maxChoiceOptions))
    }

    /// The volume menu: every ten, with the level read kept in its place
    /// when it is between two, so the menu never quietly changes it. "—"
    /// stands first until the level is read.
    public static func volumeOptions(_ percent: Int?) -> [UIChoiceOption] {
        var levels = volumeSteps
        if let percent, !levels.contains(percent) { levels = (levels + [percent]).sorted() }
        var options = levels.map { UIChoiceOption(value: String($0), title: UIText.plain("\($0) %")) }
        if percent == nil { options.insert(UIChoiceOption(value: "", title: "—"), at: 0) }
        return options
    }

    /// What the controls cannot show, only when it is not as usual: Home
    /// speakers off, the speaker offline, or (without a menu) none picked.
    public static func speakerNote(_ status: Status) -> String? {
        guard let device = status.config.defaultDevice else { return status.offersChoice ? nil : "No speaker picked yet" }
        guard status.config.effectiveSpeakHome else { return homeSpeakersOff }
        if status.volume?.online == false { return "\(device.name) is offline" }
        return nil
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

    /// Where announcements go: the outputs and what they add up to.
    static func outputBlocks(_ status: Status) -> [UIBlock] {
        let config = status.config
        let label = config.activeOutputsLabel
        return UITree {
            text("Speak on", style: .caption)
            toggle(Block.outputHome, "Home speakers", isOn: config.effectiveSpeakHome)
            toggle(Block.outputLocal, "This Mac", isOn: config.effectiveSpeakLocal)
            toggle(Block.outputPhone, "This phone", isOn: config.effectiveSpeakPhone)
            // Gemini chosen with no key: the field to paste it, as for a
            // chat source switched on with no token.
            if (config.effectiveSpeakLocal || config.effectiveSpeakPhone)
                && config.effectiveLocalEngine == .gemini && !status.chat.hasGeminiKey {
                field(Block.geminiApiKey, title: UIText.plain(geminiKeyTitle), value: "", placeholder: UIText.plain(pasteGeminiKey),
                      kind: .secret)
                button(Block.saveGeminiApiKey, UIText.plain(saveKeyButton))
            }
            text(UIText.plain(label.isEmpty ? outputsFooter(config) : "Speaking on \(label)"), style: .caption)
        }.blocks
    }

    /// What may speak, under Broadcasting: each coding agent and each chat
    /// app has its own switch, grouped under a caption as "Speak on" is.
    /// With Broadcasting off none of them speaks, and the island says so
    /// rather than greying them out: they can still be set for later.
    static func sourceBlocks(_ status: Status) -> [UIBlock] {
        let config = status.config
        let chat = config.effectiveChatMonitor
        return UITree {
            text("Coding agents", style: .caption)
            for agent in CodingAgent.allCases {
                toggle(Block.agentEnabled(agent), UIText.plain(agent.displayName), isOn: config.announces(agent))
            }
            text("Chat apps", style: .caption)
            toggle(Block.slackEnabled, "Slack", isOn: chat.slackEnabled)
            // On with no token: the field to paste it, right under the
            // switch, so turning a source on is all it takes to find it.
            if chat.slackEnabled && !status.chat.hasSlackToken {
                field(Block.slackToken, title: UIText.plain(slackTokenTitle), value: "", placeholder: UIText.plain(pasteSlackToken),
                      kind: .secret)
                button(Block.saveSlackToken, UIText.plain(saveTokenButton))
            }
            toggle(Block.googleChatEnabled, "Google Chat", isOn: chat.googleChatEnabled)
            toggle(Block.beeperEnabled, "Beeper", isOn: chat.beeperEnabled)
            if chat.beeperEnabled && !status.chat.hasBeeperToken {
                field(Block.beeperToken, title: UIText.plain(beeperTokenTitle), value: "", placeholder: UIText.plain(pasteBeeperToken),
                      kind: .secret)
                button(Block.saveBeeperToken, UIText.plain(saveTokenButton))
            }
            islandBeeperBlocks(status)
            // Skipping your own messages is for every chat app, so it
            // follows them all, and only while one of them reads.
            if chat.anySourceEnabled {
                toggle(Block.muteOwnMessages, "Skip messages I sent", isOn: chat.muteOwnMessages)
            }
            if !config.enabled {
                text(UIText.plain(sourcesSilent), style: .caption)
            }
        }.blocks
    }

    /// What follows Beeper's switch (and its token, when none is saved)
    /// while Beeper is on: which messages it announces, then a switch for
    /// each of its networks. Nothing while it is off.
    static func islandBeeperBlocks(_ status: Status) -> [UIBlock] {
        guard status.config.effectiveChatMonitor.beeperEnabled else { return [] }
        return beeperAnnouncePicker(status) + beeperNetworkBlocks(status)
    }

    /// Under the networks while the monitor has not read Beeper: only the
    /// muted ones are known.
    public static let beeperNetworksLater = BeeperNetworkList.othersLater

    /// The Beeper networks, each with its switch's state, as the app's
    /// Settings window shows them too (`BeeperNetworkList`).
    public static func beeperNetworkList(_ status: Status) -> BeeperNetworkList {
        BeeperNetworkList(listed: beeperNetworksRead(status), muted: status.config.effectiveChatMonitor.beeperMutedNetworks)
    }

    /// The rows of `beeperNetworkList`.
    public static func beeperNetworkRows(_ status: Status) -> [BeeperNetworkState] {
        beeperNetworkList(status).rows
    }

    /// The networks the running monitor last listed; nil while it is not
    /// running or has not read Beeper.
    static func beeperNetworksRead(_ status: Status) -> [BeeperNetworkState]? {
        guard status.chat.monitorRunning else { return nil }
        return status.chat.monitor?.beeperNetworkStates
    }

    /// A switch for each Beeper network, under a caption: on reads it, off
    /// mutes it. A network HomeSpeaker reads itself is shown off and
    /// greyed. With Beeper on and its networks not being read, the caption
    /// and the saved mutes, then where the others will show, even with no
    /// mutes saved. Nothing once the running monitor has listed none, nor
    /// with Beeper off and nothing saved. An app that draws chips gets the
    /// caption and the switches as one block (`beeperNetworkChips`).
    static func beeperNetworkBlocks(_ status: Status) -> [UIBlock] {
        let list = beeperNetworkList(status)
        guard list.shows(beeperEnabled: status.config.effectiveChatMonitor.beeperEnabled) else { return [] }
        return UITree {
            if let networks = beeperNetworkChips(status, rows: list.rows) {
                networks
            } else {
                text(UIText.plain(beeperNetworksTitle), style: .caption)
                // Only a key a network can have (`BeeperClient.networkKey`)
                // gets a switch: a mute saved by hand as `My Network` mutes
                // nothing, and its id would refuse the page.
                for row in list.rows where hasSwitch(row.key) {
                    switch row.state {
                    case .reading:
                        toggle(Block.beeperNetwork(row.key), UIText.plain(row.name), isOn: true)
                    case .muted:
                        toggle(Block.beeperNetwork(row.key), UIText.plain(row.name), isOn: false)
                    case .skipped:
                        toggle(Block.beeperNetwork(row.key), UIText.plain("\(row.name) · \(beeperReadDirectly)"), isOn: false,
                               enabled: false)
                    }
                }
            }
            if !list.isListed {
                text(UIText.plain(beeperNetworksLater), style: .caption)
            }
        }.blocks
    }

    /// A Beeper network key that can be a switch: one `Block.beeperNetwork`
    /// reads back, in an id the protocol takes.
    static func hasSwitch(_ key: String) -> Bool {
        let id = Block.beeperNetwork(key)
        return Block.beeperNetworkKey(id) == key && ManifestRules.isWellFormedName(id)
    }

    /// Over Beeper's networks: the caption, or the chips' title.
    static let beeperNetworksTitle = "Networks"
    /// Why a network HomeSpeaker reads itself cannot be muted.
    static let beeperReadDirectly = "Read directly"

    /// Beeper's networks as one `chips` block titled Networks, for an app
    /// that draws chips: a chip a network, by name, on while it is read.
    /// A network HomeSpeaker reads itself is a dimmed chip that says so.
    /// Nil for an app without chips, with no network to show (the block
    /// needs one), with more than the block may carry, with two rows of
    /// one key, or with a key longer than a chip's value may be (a saved
    /// mute edited by hand): the app would refuse the page, so the
    /// switches stand in.
    static func beeperNetworkChips(_ status: Status, rows: [BeeperNetworkState]) -> UIBlock? {
        guard status.offersChips, (1...UILimits.maxChoiceOptions).contains(rows.count),
              Set(rows.map(\.key)).count == rows.count,
              rows.allSatisfy({ $0.key.unicodeScalars.count <= UILimits.maxChoiceValueLength }) else { return nil }
        return chips(Block.beeperNetworks, title: UIText.plain(beeperNetworksTitle), options: rows.map { row in
            switch row.state {
            case .reading:
                return UIChipOption(value: row.key, title: UIText.plain(row.name), on: true)
            case .muted:
                return UIChipOption(value: row.key, title: UIText.plain(row.name), on: false)
            case .skipped:
                return UIChipOption(value: row.key, title: UIText.plain(row.name), on: false, enabled: false,
                                    reason: UIText.plain(beeperReadDirectly))
            }
        })
    }

    /// Saves a change of the `beeperNetworks` chips into `monitor`, for the
    /// island and Settings alike: `values` are the chips now on, `rows` the
    /// networks as they were drawn, with any HomeSpeaker now reads itself
    /// marked skipped. Every row whose chip
    /// is off is muted and every other read, except a network HomeSpeaker
    /// reads itself, whose saved mute is left as it is; a saved mute with
    /// no row is kept. True when the mutes changed.
    static func saveBeeperNetworkChips(_ values: [String], rows: [BeeperNetworkState],
                                       into monitor: inout ChatMonitorConfig) -> Bool {
        let before = Set(monitor.beeperMutedNetworks)
        for row in rows where row.state != .skipped {
            monitor.setBeeperNetwork(row.key, reading: values.contains(row.key))
        }
        return Set(monitor.beeperMutedNetworks) != before
    }

    /// How much of a reply to speak: one picker for the island and
    /// Settings › General, so the two never drift.
    static func speakPicker(_ status: Status) -> [UIBlock] {
        picker(Block.speechLength, title: "Speak", value: status.config.effectiveSpeechLength.rawValue,
               options: SpeechLength.allCases.map { UIChoiceOption(value: $0.rawValue, title: UIText.plain($0.label)) },
               choice: status.offersChoice)
    }

    /// How an agent's reply is worded: one picker for the island and
    /// Settings › General.
    static func stylePicker(_ status: Status) -> [UIBlock] {
        picker(Block.announcementStyle, title: "Style", value: status.config.effectiveAnnouncementStyle.rawValue,
               options: AnnouncementStyle.allCases.map { UIChoiceOption(value: $0.rawValue, title: UIText.plain($0.label)) },
               choice: status.offersChoice)
    }

    /// The custom style's instruction, while Custom is chosen.
    static func customStyleBlocks(_ status: Status) -> [UIBlock] {
        guard status.config.effectiveAnnouncementStyle == .custom else { return [] }
        return [field(Block.customStylePrompt, title: UIText.plain(customStyleTitle),
                      value: status.config.effectiveCustomStylePrompt, placeholder: UIText.plain(customStylePlaceholder))]
    }

    /// Which model rewords, while a style rewords.
    static func styleModelPicker(_ status: Status) -> [UIBlock] {
        picker(Block.styleModel, title: "Style with", value: status.config.effectiveStyleModel.rawValue,
               options: StyleModel.allCases.map { UIChoiceOption(value: $0.rawValue, title: UIText.plain($0.label)) },
               choice: status.offersChoice)
    }

    /// What speaks on this Mac.
    static func localEnginePicker(_ status: Status) -> [UIBlock] {
        picker(Block.localEngine, title: "Voice engine", value: status.config.effectiveLocalEngine.rawValue,
               options: LocalVoiceEngine.allCases.map { UIChoiceOption(value: $0.rawValue, title: UIText.plain($0.label)) },
               choice: status.offersChoice)
    }

    /// The Gemini voice. One set by hand that is not offered is listed
    /// too, so the picker shows what is in use.
    static func geminiVoicePicker(_ status: Status) -> [UIBlock] {
        let current = status.config.effectiveGeminiVoice
        var options = GeminiVoice.allCases.map { UIChoiceOption(value: $0.rawValue, title: UIText.plain($0.label)) }
        if GeminiVoice(rawValue: current) == nil {
            options.insert(UIChoiceOption(value: current, title: UIText.plain(current)), at: 0)
        }
        return picker(Block.geminiVoice, title: "Gemini voice", value: current, options: options, choice: status.offersChoice)
    }

    /// Speakers › Where to speak shows the Gemini key: Gemini speaks there.
    static func geminiKeyUnderSpeakers(_ config: SpeakerConfig) -> Bool {
        (config.effectiveSpeakLocal || config.effectiveSpeakPhone) && config.effectiveLocalEngine == .gemini
    }

    /// The Gemini API key, as Settings shows a token: the field, Save, and
    /// what is saved.
    static func geminiKeyBlocks(_ status: Status) -> [UIBlock] {
        let saved = status.chat.hasGeminiKey
        return UITree {
            field(Block.geminiApiKey, title: UIText.plain(geminiKeyTitle), value: "",
                  placeholder: saved ? "Paste a new key to replace it" : "Paste the key, then Save Key",
                  kind: .secret, help: help(geminiKeyHelp, true, status))
            button(Block.saveGeminiApiKey, UIText.plain(saveKeyButton), style: .prominent)
            if saved {
                row(nil, "Gemini API key saved", icon: "checkmark.circle.fill")
                button(Block.clearGeminiApiKey, "Clear Gemini Key")
            } else {
                row(nil, "No Gemini API key saved", icon: "exclamationmark.circle")
            }
            captionUnlessHelp(geminiKeyHelp, report: nil, status)
        }.blocks
    }

    /// Which Beeper messages are announced: one picker for the island and
    /// Settings › Chats.
    static func beeperAnnouncePicker(_ status: Status) -> [UIBlock] {
        picker(Block.beeperAnnounce, title: "Announce", value: status.config.effectiveChatMonitor.beeperAnnounce.rawValue,
               options: ChatMonitorConfig.BeeperAnnounce.allCases.map {
                   UIChoiceOption(value: $0.rawValue, title: UIText.plain($0.title))
               },
               choice: status.offersChoice)
    }

    /// Under the sources while Broadcasting is off.
    public static let sourcesSilent = "Broadcasting is off, so none of these speak."

    /// Why the chat monitor, switched on, reads nothing: each problem, then
    /// where to fix it. Empty while every source is off. The extension is
    /// what reads chat, so there is no app to say is not running.
    public static func chatWarnings(_ status: Status) -> [String] {
        guard status.config.effectiveChatMonitor.anySourceEnabled else { return [] }
        return monitorProblemLines(status)
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

    /// The chat warnings, then where to fix them: a button that opens
    /// Chats, for an app that can open HomeSpeaker's settings;
    /// otherwise where that is. An app that draws sections has no Section
    /// menu: Chats is on the one page.
    static func chatWarningBlocks(_ status: Status) -> [UIBlock] {
        let lines = chatWarnings(status)
        guard !lines.isEmpty else { return [] }
        return UITree {
            problemRows(lines)
            if status.opensSettings {
                button(Block.openChatSettings, UIText.plain(status.offersSections ? openSettingsButton : openChatSettingsButton))
            } else {
                text(UIText.plain(status.offersSections ? fixChatInSettingsOnOnePage : fixChatInSettings), style: .caption)
            }
        }.blocks
    }

    /// A warning row a line, with no id to tap.
    static func problemRows(_ lines: [String]) -> [UIBlock] {
        lines.map { row(nil, UIText.plain($0), icon: "exclamationmark.triangle.fill") }
    }

    /// The newest of the shared history, as the menu bar's Recent
    /// Broadcasts lists it. A tap on a row speaks it again (`Job.replay`),
    /// once HomeSpeaker can: installed, and not quiet for the other one.
    static func recentBroadcastBlocks(_ status: Status) -> [UIBlock] {
        let replays = status.installed
        return UITree {
            heading("Recent Broadcasts")
            if status.recentBroadcasts.isEmpty {
                text(UIText.plain(noRecentBroadcasts), style: .secondary)
            } else {
                for item in status.recentBroadcasts.prefix(maxRecentBroadcasts) {
                    row(replays ? Block.replayBroadcast(item.id) : nil, UIText.plain(item.text),
                        subtitle: UIText.plain(broadcastLine(item)), icon: "text.bubble",
                        trailing: replays ? UIText.plain(replayMark) : nil)
                }
                if replays { text(UIText.plain(replayHint), style: .caption) }
            }
        }.blocks
    }

    /// The trailing mark on a row that replays.
    public static let replayMark = "↻"
    public static let replayHint = "Tap one to hear it again."
    /// A tap on a row whose broadcast has since left the history.
    public static let replayGone = "That announcement is no longer in the history"

    /// "Say · Kitchen + This Mac · 14 Oct 2026 at 9:41": who, where, when.
    public static func broadcastLine(_ item: BroadcastLogItem) -> String {
        [item.source, item.targetName, item.timestamp.formatted(date: .abbreviated, time: .shortened)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    public static func busyLine(_ job: Job) -> String {
        switch job {
        case .say: return "Speaking…"
        case .replay: return "Speaking it again…"
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

    public static func speakerRows(_ speakers: [(key: String, device: SpeakerDevice)], chosen: String) -> [UIListRow] {
        speakers.prefix(maxSpeakerRows).map { entry in
            UIListRow(id: Block.rowId(entry.key), title: UIText.plain(entry.device.displayLine),
                      icon: entry.device.isWholeHome ? "house" : "hifispeaker",
                      trailing: entry.key == chosen ? "✓" : nil)
        }
    }

    // MARK: - The settings panel

    // The captions that explain one control each. For an app that draws
    // every section on one page they are that control's help; otherwise
    // the caption under it, as before.
    /// "Announce at a set volume", while it is on.
    public static let announceVolumeHelp =
        "The speaker goes back to its own volume when the announcement ends, unless someone changes it in the meantime."
    /// "Pause media while announcing": what the switch does.
    public static let pauseMediaHelp =
        "Pauses what this Mac is playing while an announcement plays, then resumes it. Works with Chrome, Brave, Edge, Arc, Vivaldi, Safari, Music, Spotify and QuickTime; browsers need Allow JavaScript from Apple Events. Test pauses it for 3 seconds."
    /// Under Pause media's Test button, for an app without sections.
    public static let pauseMediaCaption =
        "Test pauses what this Mac is playing for 3 seconds, then resumes it. Works with Chrome, Brave, Edge, Arc, Vivaldi, Safari, Music, Spotify and QuickTime; browsers need Allow JavaScript from Apple Events."
    /// Under Sign In, signed out with no OAuth client, for an app that draws
    /// every section on one page: Google Cloud is further down the page.
    public static let signInNeedsCloudBelow =
        "Sign In needs a Google Cloud project of your own (Home API enabled) — a few minutes, once. Set it up under Google Cloud below."
    /// "Enable Quiet Hours".
    public static let quietHoursHelp = "Automated announcements are held during quiet hours. What you type yourself still plays."
    /// Settings › Chats' Slack token field.
    public static let slackTokenHelp =
        "Create a Slack app with the search:read user scope and paste its user token. The token is stored only on this Mac."

    /// The settings page. An app that draws sections gets every section at
    /// once, each under a heading that starts it, and no Section picker;
    /// any other gets the picker and the section picked.
    public static func settings(_ status: Status) -> UITree {
        UITree {
            if !status.offersSections {
                picker(Block.section, title: "Section", value: status.section.rawValue,
                       options: Section.allCases.map { UIChoiceOption(value: $0.rawValue, title: UIText.plain($0.title)) },
                       choice: status.offersChoice)
            }
            configProblemBlocks(status)
            if let busy = status.setupBusy { text(UIText.plain(busyLine(busy)), style: .caption) }
            if let notice = status.setupNotice { text(UIText.plain(notice), style: .caption) }
            if status.offersSections {
                for section in Section.allCases {
                    heading(UIText.plain(section.title), section: true)
                    blocks(of: section, status)
                }
            } else {
                blocks(of: status.section, status)
            }
        }
    }

    static func blocks(of section: Section, _ status: Status) -> [UIBlock] {
        switch section {
        case .general: return general(status)
        case .speakers: return speakers(status)
        case .monitor: return monitor(status)
        case .agents: return agents(status)
        case .googleCloud: return googleCloud(status)
        }
    }

    /// A `choice` where the app draws one, else a list whose picked row
    /// carries a tick. Both answer with the option's `Block.rowId`, which
    /// is the value itself for any value the protocol takes as a name: the
    /// choice as `PanelEvent.text`, the list as `PanelEvent.row`. Read it
    /// back with `Block.rowValue`.
    public static func picker(_ id: String, title: String, value: String, options: [UIChoiceOption], choice offersChoice: Bool) -> [UIBlock] {
        if offersChoice {
            // A value that is no option's is drawn as written, as before;
            // one too long for the protocol is left empty, not refused.
            let shown: String
            if options.contains(where: { $0.value == value }) {
                shown = Block.rowId(value)
            } else {
                shown = value.unicodeScalars.count <= UILimits.maxChoiceValueLength ? value : ""
            }
            return [choice(id, title: UIText.plain(title), value: shown, options: options.prefix(UILimits.maxChoiceOptions).map {
                UIChoiceOption(value: Block.rowId($0.value), title: $0.title)
            })]
        }
        return [
            text(UIText.plain(title), style: .secondary),
            list(id, options.prefix(UILimits.maxListRows).map {
                UIListRow(id: Block.rowId($0.value), title: $0.title, trailing: $0.value == value ? "✓" : nil)
            }),
        ]
    }

    static func general(_ status: Status) -> [UIBlock] {
        let config = status.config
        let canRun = status.installed && status.setupBusy == nil
        return UITree {
            doorCardBlocks(status)
            doorReportBlocks(status)
            whichBlocks(status)
            heading("Google Home Account")
            if status.account.isSignedIn {
                row(nil, UIText.plain(status.account.email ?? "Connected"), subtitle: "Signed in", icon: "checkmark.circle.fill")
                button(Block.signOut, "Sign Out", enabled: canRun)
                text("Sign Out also signs out of Google Chat and stops the Chat monitor.", style: .caption)
            } else {
                row(nil, "Not signed in", icon: "exclamationmark.triangle.fill")
                button(Block.signIn, "Sign In…", style: .prominent, enabled: canRun)
                if !status.account.hasOAuthClient {
                    // With every section on one page Google Cloud is
                    // further down: there is no section for Set up… to open.
                    if status.offersSections {
                        text(UIText.plain(signInNeedsCloudBelow), style: .caption)
                    } else {
                        text("Sign In needs a Google Cloud project of your own (Home API enabled) — a few minutes, once.", style: .caption)
                        button(Block.openGoogleCloud, "Set up…")
                    }
                }
                if status.account.hasAntigravityTokens {
                    button(Block.importAntigravity, "Import Antigravity login")
                    text("Reuses the Google Home sign-in from the Antigravity connector on this Mac.", style: .caption)
                }
            }

            heading("Broadcast Controls")
            toggle(Block.broadcasting, "Enable Voice Broadcasting", isOn: config.enabled)
            text(UIText.plain(DoorWords.runsWithVitruvian), style: .caption)
            speakPicker(status)
            stylePicker(status)
            customStyleBlocks(status)
            if config.effectiveAnnouncementStyle != .verbatim {
                styleModelPicker(status)
                // The key, here unless Speakers › This Mac shows it (one
                // place at a time: every section can be on one page).
                if config.effectiveStyleModel == .gemini && !geminiKeyUnderSpeakers(config) {
                    geminiKeyBlocks(status)
                }
            }
            captionUnlessHelp(config.effectiveAnnouncementStyle == .verbatim ? styleHelp : styleModelHelp,
                              report: nil, status)
            // Each switch's caption is its help for an app that draws help;
            // a report of what happened stays a caption. Announce volume's
            // only while it is on, as its caption was; Pause media's, which
            // says what the switch does, always.
            toggle(Block.announceVolume, "Announce at a set volume", isOn: config.effectiveAnnounceVolumeEnabled,
                   help: help(announceVolumeHelp, config.effectiveAnnounceVolumeEnabled, status))
            if config.effectiveAnnounceVolumeEnabled {
                field(Block.announceLevel, title: "Announcement volume (0 to 100)", value: String(config.effectiveAnnounceVolume),
                      kind: .number)
                captionUnlessHelp(announceVolumeHelp, report: status.volumeRestoreReport, status)
            }
            toggle(Block.pauseMedia, "Pause media while announcing", isOn: config.effectivePauseMedia,
                   help: help(pauseMediaHelp, true, status))
            if config.effectivePauseMedia {
                field(Block.pauseExtra, title: "Resume after (0 to 10 s)", value: String(Int(config.effectivePauseMediaExtraSeconds)),
                      kind: .number)
                button(Block.testMediaPause, status.setupBusy == .app(.testMediaPause) ? "Paused…" : "Test", enabled: canRun)
                captionUnlessHelp(pauseMediaCaption, report: status.mediaPauseReport, status)
            }

            heading("Quiet Hours")
            toggle(Block.quiet, "Enable Quiet Hours", isOn: config.quietHoursEnabled ?? false, help: help(quietHoursHelp, true, status))
            quietHourBlocks(status)
            captionUnlessHelp(quietHoursHelp, report: nil, status)
        }.blocks
    }

    /// `caption` as a control's help, for an app that draws help (it draws
    /// sections), while `shown`; nil otherwise.
    static func help(_ caption: String, _ shown: Bool, _ status: Status) -> UIText? {
        status.offersSections && shown ? UIText.plain(caption) : nil
    }

    /// The caption under a control: the report of what it last did, when
    /// there is one; else `caption`, unless the control carries it as help.
    static func captionUnlessHelp(_ caption: String, report: String?, _ status: Status) -> [UIBlock] {
        if let report { return [text(UIText.plain(report), style: .caption)] }
        return status.offersSections ? [] : [text(UIText.plain(caption), style: .caption)]
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
            toggle(Block.speakPhone, "This phone", isOn: config.effectiveSpeakPhone)
            if config.effectiveSpeakLocal || config.effectiveSpeakPhone {
                localEnginePicker(status)
                if config.effectiveLocalEngine == .gemini {
                    geminiVoicePicker(status)
                    geminiKeyBlocks(status)
                }
            }
            if config.effectiveSpeakLocal {
                // The Mac voice always: with Gemini it is what speaks when
                // Gemini cannot.
                picker(Block.voice, title: config.effectiveLocalEngine == .gemini ? "Fallback Mac voice" : "Voice",
                       value: config.effectiveLocalVoice, options: voiceOptions(status), choice: status.offersChoice)
                button(Block.previewVoice, status.previewing ? "Speaking…" : "Preview", enabled: !status.previewing)
            }
            if config.effectiveSpeakPhone {
                toggle(Block.phonePauseMedia, "Pause phone media while announcing", isOn: config.effectivePhonePauseMedia)
                toggle(Block.phoneHeadphonesOnly, "Only announce on phone when headphones are connected",
                       isOn: config.effectivePhoneHeadphonesOnly)
            }
            let footer = outputsFooter(config)
            if !footer.isEmpty { text(UIText.plain(footer), style: .caption) }
        }.blocks
    }

    /// What the chat monitor does with messages, and where they go.
    public static func monitorPrivacyLine(_ config: SpeakerConfig) -> String {
        "HomeSpeaker reads new messages in the background while Slack, Google Chat or Beeper is on, "
            + "and announces them on your speakers. " + config.chatMessagesSentTo
    }

    /// Where the token comes from, and what is skipped.
    public static let beeperHelp = "In Beeper Desktop: Settings › Integrations, turn on the Desktop API, then + next to Approved connections. "
        + "Beeper Desktop must be running; HomeSpeaker only talks to it on this Mac. "
        + "Slack and Google Chat chats in Beeper are skipped while their own switches above are on."

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
                                                hasChatScopes: status.chat.hasChatAccess, gwsInstalled: status.chat.gwsPath != nil,
                                                hasBeeperToken: status.chat.hasBeeperToken)
    }

    /// Chats, as HomeSpeaker's tab of that name: what reads the
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
            text(UIText.plain(monitorPrivacyLine(status.config)), style: .caption)
            if !chat.ownerRunning && monitor.anySourceEnabled {
                text(UIText.plain(notReadingLine(status.door.role)), style: .caption)
            }
            monitorRunBlocks(status)
            problemRows(monitorProblemLines(status))

            heading("Slack")
            toggle(Block.slackEnabled, "Announce Slack messages", isOn: monitor.slackEnabled)
            field(Block.slackToken, title: UIText.plain(slackTokenTitle), value: "",
                  placeholder: chat.hasSlackToken ? "Paste a new token to replace it" : "Paste the token, then Save Token",
                  kind: .secret, help: help(slackTokenHelp, true, status))
            button(Block.saveSlackToken, UIText.plain(saveTokenButton), style: .prominent)
            if chat.hasSlackToken {
                row(nil, "Slack token saved", icon: "checkmark.circle.fill")
                button(Block.clearSlackToken, "Clear Slack Token")
            } else {
                row(nil, "No Slack token saved", icon: "exclamationmark.circle")
            }
            captionUnlessHelp(slackTokenHelp, report: nil, status)

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

            heading("Beeper")
            toggle(Block.beeperEnabled, "Announce Beeper messages", isOn: monitor.beeperEnabled)
            beeperAnnouncePicker(status)
            beeperNetworkBlocks(status)
            field(Block.beeperToken, title: UIText.plain(beeperTokenTitle), value: "",
                  placeholder: chat.hasBeeperToken ? "Paste a new token to replace it" : "Paste the token, then Save Token",
                  kind: .secret)
            button(Block.saveBeeperToken, UIText.plain(saveTokenButton), style: .prominent)
            if chat.hasBeeperToken {
                row(nil, "Beeper token saved", icon: "checkmark.circle.fill")
                button(Block.clearBeeperToken, "Clear Beeper Token")
            } else {
                row(nil, "No Beeper token saved", icon: "exclamationmark.circle")
            }
            text(UIText.plain(beeperHelp), style: .caption)

            heading("Options")
            toggle(Block.muteOwnMessages, "Skip messages I sent", isOn: monitor.muteOwnMessages)
            field(Block.pollInterval, title: UIText.plain(pollIntervalTitle), value: String(monitor.clampedPollInterval), kind: .number)
        }.blocks
    }

    /// The monitor itself, as the app's Settings shows it: Running or
    /// Stopped, Start or Stop while HomeSpeaker runs and a source is on, and
    /// while it runs, when it last polled, who Slack says we are, how
    /// Google Chat is read and which Beeper networks are read.
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
                if let line = ChatMonitorService.beeperReadingLine(
                    networks: monitor.beeperNetworks, skipped: monitor.beeperSkippedNetworks) {
                    text(UIText.plain(line), style: .caption)
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

    /// Under the agents' switches in Settings.
    public static let agentSwitchesHelp =
        "Each agent's announcements, under Enable Voice Broadcasting. Off, the hook or instruction stays as it is and nothing is spoken."

    /// What a hook says when it is there but HomeSpeaker, which it runs, is not.
    public static let hookWithoutHomeSpeaker = "Points at HomeSpeaker, which isn't installed — it can't speak"

    /// AI Agents, as HomeSpeaker's tab of that name: each coding agent's
    /// hook or instruction, and the 1.x launch agent to clean up. Reading
    /// state, removing and the instruction need no HomeSpeaker; installing
    /// a hook does, since a hook runs it.
    static func agents(_ status: Status) -> [UIBlock] {
        UITree {
            heading("Announcements")
            for agent in CodingAgent.allCases {
                toggle(Block.agentEnabled(agent), UIText.plain("Announce \(agent.displayName) replies"),
                       isOn: status.config.announces(agent))
            }
            text(UIText.plain(agentSwitchesHelp), style: .caption)
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
                row(nil, UIText.plain("\(name) \(st.agent.hookKind)"), subtitle: "Not installed on this Mac. Nothing to do here.", icon: "minus.circle")
            case .instructionDriven:
                if st.configuredByInstruction {
                    row(nil, UIText.plain("\(name) announcements"), subtitle: "Configured", icon: "checkmark.circle.fill")
                    text(UIText.plain("\(file) tells \(name) to speak each reply through HomeSpeaker's speaker settings."), style: .caption)
                } else {
                    row(nil, UIText.plain("\(name) announcements"), subtitle: "Not set up", icon: "exclamationmark.circle")
                    button(Block.agent(.addInstruction, st.agent), "Add Instruction", style: .prominent)
                    text(UIText.plain("Adds one line to \(file) asking \(name) to speak each reply."),
                         style: .caption)
                }
            case .hook:
                hookBlocks(st, status)
            }
            text(UIText.plain(st.agent.hookFootnote), style: .caption)
        }.blocks
    }

    /// An agent HomeSpeaker hooks: the "spoken twice" warning, the hook's
    /// state and what it runs. A hook left behind by a HomeSpeaker that is
    /// gone says so and offers Remove, never an update it cannot make.
    static func hookBlocks(_ st: AgentIntegration.AgentStatus, _ status: Status) -> [UIBlock] {
        let name = st.agent.displayName
        let title = UIText.plain("\(name) \(st.agent.hookKind)")
        let quiet = status.door.role.isQuiet
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
            case .stale where quiet:
                row(nil, title, subtitle: "Installed on the HomeSpeaker app", icon: "checkmark.circle")
            case .stale:
                row(nil, title, subtitle: "Needs update", icon: "arrow.triangle.2.circlepath")
                button(Block.agent(.installHook, st.agent), "Update Hook", style: .prominent)
            case .notInstalled:
                row(nil, title, subtitle: "Not installed", icon: "circle")
                if !quiet {
                    button(Block.agent(.installHook, st.agent), "Install Hook", style: .prominent, enabled: status.installed)
                }
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
            row(nil, "History", subtitle: UIText.plain(status.files.history))
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
            return UIListRow(id: Block.rowId(key), title: UIText.plain(device.name), subtitle: UIText.plain(subtitle),
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

    /// What the outputs mean together, as HomeSpeaker's Settings says it.
    public static func outputsFooter(_ config: SpeakerConfig) -> String {
        if !config.effectiveSpeakHome && !config.effectiveSpeakLocal && !config.effectiveSpeakPhone {
            return "Both are off, so nothing is spoken anywhere."
        }
        var lines: [String] = []
        if config.effectiveSpeakLocal {
            lines.append("This Mac speaks at its own volume. More voices: System Settings › Accessibility › Read & Speak › System voice › ⓘ › Voice, then download an \"(Enhanced)\" voice.")
        }
        if config.effectiveSpeakPhone {
            lines.append(config.effectiveLocalEngine == .gemini
                ? "This phone plays the Gemini voice (or Android's on-device voice when Gemini is unavailable) via Vitruvian Remote."
                : "This phone speaks with Android's on-device voice via Vitruvian Remote.")
        }
        if config.effectiveSpeakHome && config.effectiveSpeakLocal {
            lines.append("Both speak at the same time. Quiet hours and pausing media cover both.")
        }
        return lines.joined(separator: " ")
    }
}
