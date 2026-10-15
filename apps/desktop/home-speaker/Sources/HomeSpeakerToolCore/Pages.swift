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
        case general, speakers

        public var title: String {
            switch self {
            case .general: return "General"
            case .speakers: return "Speakers"
            }
        }
    }

    /// The Google Home sign-in, as Settings shows it: never a token.
    public struct Account: Equatable, Sendable {
        public var isSignedIn = false
        public var email: String?
        public var hasOAuthClient = false
        public var hasAntigravityTokens = false

        public init(isSignedIn: Bool = false, email: String? = nil, hasOAuthClient: Bool = false, hasAntigravityTokens: Bool = false) {
            self.isSignedIn = isSignedIn
            self.email = email
            self.hasOAuthClient = hasOAuthClient
            self.hasAntigravityTokens = hasAntigravityTokens
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

        public init() {}
    }

    public static let releases = "https://github.com/VitruvianSoftware/vitruvian-core/releases?q=home-speaker"
    public static let maxSpeakerRows = 20
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
    }

    // MARK: - The island page

    public static func island(_ status: Status) -> UITree {
        UITree {
            heading("HomeSpeaker")
            if !status.installed {
                text("HomeSpeaker is not installed on this Mac. The tool speaks through it.", style: .secondary)
                link("Get HomeSpeaker", url: releases)
            } else {
                field(Block.say, title: "Say something", value: "", placeholder: "Type it and press Return")
                if let notice = status.notice { text(UIText.plain(notice), style: .caption) }
                if let busy = status.busy { text(UIText.plain(busyLine(busy)), style: .caption) }
                toggle(Block.broadcasting, "Broadcasting", isOn: status.config.enabled)
                toggle(Block.quiet, "Quiet hours", isOn: status.config.quietHoursEnabled ?? false)
                if status.quietNow, let until = status.config.quietHoursEnd {
                    text(UIText.plain("Quiet hours until \(until): what you type still plays"), style: .caption)
                }
                divider()
                row(nil, UIText.plain(status.config.defaultDevice?.name ?? "No speaker picked"),
                    subtitle: UIText.plain(volumeLine(status)), icon: "hifispeaker.2")
                if status.config.defaultDevice != nil {
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
                    text("Speak on", style: .caption)
                    list(Block.speakers, speakerRows(speakers, chosen: status.config.defaultTarget))
                }
            }
        }
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
            if let problem = status.configProblem {
                row(nil, "The settings file does not read", subtitle: UIText.plain(problem), icon: "exclamationmark.triangle.fill")
                text("Nothing is saved until it reads again: fix or remove the file.", style: .caption)
            }
            if let busy = status.setupBusy { text(UIText.plain(busyLine(busy)), style: .caption) }
            if let notice = status.setupNotice { text(UIText.plain(notice), style: .caption) }
            switch status.section {
            case .general: general(status)
            case .speakers: speakers(status)
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
                    text("Sign In needs a Google Cloud OAuth client: configure one in HomeSpeaker, under Settings > Google Cloud.",
                         style: .caption)
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
            text("The Slack and Google Chat monitors and the coding-agent hooks are set up in HomeSpeaker.", style: .caption)
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
