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

        public init(link: ToolLink, store: ConfigStore, driver: SpeakerDriver,
                    later: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void, now: @escaping () -> Date = Date.init) {
            self.link = link
            self.store = store
            self.driver = driver
            self.later = later
            self.now = now
        }
    }

    public let parts: Parts
    public private(set) var config = SpeakerConfig()
    public private(set) var volume: Volume?
    public private(set) var busy: Job?
    public private(set) var notice: String?
    public private(set) var openPanels: Set<String> = []

    public init(parts: Parts) {
        self.parts = parts
    }

    // MARK: - The app's messages

    public func start() {
        reload()
        if parts.driver.isInstalled, config.defaultDevice != nil { try? run(.volume) }
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
        openPanels.insert(Self.islandPanel)
        reload()
        if parts.driver.isInstalled, config.defaultDevice != nil, volume == nil, busy == nil { try? run(.volume) }
        return Pages.island(status())
    }

    public func islandEvent(_ event: PanelEvent) -> PanelAnswer {
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
                if parts.driver.isInstalled { try run(.volume) }
            default:
                return .keep
            }
        } catch {
            notice = "\(error)"
        }
        return .page(Pages.island(status()))
    }

    public func settingsPage() -> UITree {
        openPanels.insert(Self.settingsPanel)
        reload()
        return Pages.settings(status())
    }

    public func settingsEvent(_ event: PanelEvent) -> PanelAnswer {
        reload()
        switch event.block {
        case Pages.Block.speechLength?:
            guard let id = event.row, let length = SpeechLength(rawValue: id) else { return .keep }
            config.effectiveSpeechLength = length
        case Pages.Block.speakHome?:
            guard let isOn = event.isOn else { return .keep }
            config.effectiveSpeakHome = isOn
        case Pages.Block.speakLocal?:
            guard let isOn = event.isOn else { return .keep }
            config.effectiveSpeakLocal = isOn
        case Pages.Block.announceVolume?:
            guard let isOn = event.isOn else { return .keep }
            config.effectiveAnnounceVolumeEnabled = isOn
        case Pages.Block.announceLevel?:
            guard let text = event.text, let level = Int(text.trimmingCharacters(in: .whitespaces)) else { return .keep }
            config.effectiveAnnounceVolume = level
        case Pages.Block.pauseMedia?:
            guard let isOn = event.isOn else { return .keep }
            config.effectivePauseMedia = isOn
        case Pages.Block.quiet?:
            guard let isOn = event.isOn else { return .keep }
            config.quietHoursEnabled = isOn
        case Pages.Block.quietStart?:
            guard let text = event.text, let hour = SpeakerConfig.quietHour(text) else { return .keep }
            config.quietHoursStart = hour
        case Pages.Block.quietEnd?:
            guard let text = event.text, let hour = SpeakerConfig.quietHour(text) else { return .keep }
            config.quietHoursEnd = hour
        default:
            return .keep
        }
        do {
            try save()
        } catch {
            parts.link.log("the settings could not be saved: \(error)")
            reload()
        }
        return .page(Pages.settings(status()))
    }

    public func panelClosed(_ panel: String) {
        openPanels.remove(panel)
    }

    // MARK: - HomeSpeaker's program

    /// HomeSpeaker's program ended a job: what it said, drawn again.
    public func finished(_ job: Job, _ result: JobResult) {
        if busy == job { busy = nil }
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
        case .unavailable(let why):
            volume = nil
            notice = why.capitalizingFirst
        }
        refreshOpenPanels()
    }

    public func status() -> Pages.Status {
        var status = Pages.Status()
        status.installed = parts.driver.isInstalled
        status.config = config
        status.volume = volume
        status.busy = busy
        status.notice = notice
        status.quietNow = config.isInQuietHours(at: parts.now())
        return status
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

    /// One job at a time: HomeSpeaker's program takes seconds, and two at
    /// once would read a volume the other is setting. A second is refused,
    /// saying what is still running.
    private func run(_ job: Job) throws {
        if let busy { throw CommandRefused("HomeSpeaker is busy: \(Pages.busyLine(busy))") }
        busy = job
        notice = nil
        let later = parts.later
        parts.driver.run(job) { [weak self] result in
            later { [weak self] in self?.finished(job, result) }
        }
    }

    private func reload() {
        if let read = parts.store.load() { config = read }
    }

    private func save() throws {
        try parts.store.save(config)
    }

    private func refreshOpenPanels() {
        if openPanels.contains(Self.islandPanel) { parts.link.render(panel: Self.islandPanel, Pages.island(status())) }
        if openPanels.contains(Self.settingsPanel) { parts.link.render(panel: Self.settingsPanel, Pages.settings(status())) }
    }
}

extension String {
    var capitalizingFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
