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
    public struct Status: Equatable {
        public var installed = true
        public var config = SpeakerConfig()
        public var volume: Volume?
        /// What HomeSpeaker is doing for the tool right now, if anything.
        public var busy: Job?
        /// The last thing worth saying: where a text was spoken, or why not.
        public var notice: String?
        public var quietNow = false

        public init() {}
    }

    public static let releases = "https://github.com/VitruvianSoftware/vitruvian-core/releases?q=home-speaker"
    public static let maxSpeakerRows = 20

    public enum Block {
        public static let say = "say"
        public static let broadcasting = "broadcasting"
        public static let quiet = "quiet"
        public static let mute = "mute"
        public static let unmute = "unmute"
        public static let volume = "volume"
        public static let refresh = "refresh"
        public static let speakers = "speakers"
        public static let speechLength = "speechLength"
        public static let speakHome = "speakHome"
        public static let speakLocal = "speakLocal"
        public static let announceVolume = "announceVolume"
        public static let announceLevel = "announceLevel"
        public static let pauseMedia = "pauseMedia"
        public static let quietStart = "quietStart"
        public static let quietEnd = "quietEnd"
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
        let config = status.config
        return UITree {
            if !status.installed {
                text("HomeSpeaker is not installed on this Mac; these are its settings, which it reads too.", style: .caption)
            }
            text("How much of a reply to speak", style: .secondary)
            list(Block.speechLength, SpeechLength.allCases.map { length in
                UIListRow(id: length.rawValue, title: UIText.plain(length.label),
                          trailing: length == config.effectiveSpeechLength ? "✓" : nil)
            })
            toggle(Block.speakHome, "Home speakers", isOn: config.effectiveSpeakHome)
            toggle(Block.speakLocal, "This Mac", isOn: config.effectiveSpeakLocal)
            toggle(Block.announceVolume, "Announce at a set volume", isOn: config.effectiveAnnounceVolumeEnabled)
            if config.effectiveAnnounceVolumeEnabled {
                field(Block.announceLevel, title: "Announcement volume (0 to 100)", value: String(config.effectiveAnnounceVolume),
                      kind: .number)
                text("The speaker goes back to its own volume when the announcement ends. Needs HomeSpeaker running to put it back.",
                     style: .caption)
            }
            toggle(Block.pauseMedia, "Pause media while announcing", isOn: config.effectivePauseMedia)
            divider()
            toggle(Block.quiet, "Quiet hours", isOn: config.quietHoursEnabled ?? false)
            field(Block.quietStart, title: "From (HH:mm)", value: config.quietHoursStart ?? "22:00")
            field(Block.quietEnd, title: "Until (HH:mm)", value: config.quietHoursEnd ?? "07:00")
            text("Automated announcements are held during quiet hours. What you type yourself still plays.", style: .caption)
            text("Signing in, finding speakers and the Slack and Google Chat monitors stay in HomeSpeaker.", style: .caption)
        }
    }
}
