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

@MainActor
public class ConfigManager: ObservableObject {
    /// The app's settings, on the app's history and secrets: the parts of
    /// `HomeSpeakerEngine.app`.
    public static let shared = ConfigManager(
        configPath: ConfigManager.defaultConfigURL(), history: .shared, secrets: .shared)

    @Published public var config: SpeakerConfig
    @Published public var recentBroadcasts: [BroadcastLogItem] = []
    @Published public var isConnectedToGoogle: Bool = false
    @Published public var googleEmail: String?
    /// Set when the config file exists but does not read as a config (bad
    /// JSON, a wrong type, no permission). While set, nothing is saved: the
    /// in-memory settings are built-in defaults, and writing them would wipe
    /// whatever the phone, the CLI or the person put in the file. Cleared
    /// as soon as the file reads again.
    @Published public private(set) var configProblem: String?

    /// Told when an edit from outside (the phone, the CLI) changes the
    /// chat monitor's settings, so the running poller follows. Weak: the
    /// service holds this manager, not the other way round.
    public weak var chatMonitor: (any ChatMonitorControlling)?

    private let fileManager = FileManager.default
    private let configPath: URL
    private let file: SpeakerConfigFile
    /// The history list this manager adds to and shows.
    public let history: BroadcastHistory
    /// The secrets the Google connection is read from.
    public let secrets: SecretStore

    /// The bytes this process last wrote to the config file, so a change
    /// notification for our own save is not mistaken for someone else's edit.
    private var lastWritten: Data?
    private var watcher: DispatchSourceFileSystemObject?

    /// The config lives at ~/.gemini/speaker_broadcast.json because the
    /// `speaker-broadcast` CLI and the Gemini/Antigravity skills read the same
    /// file; moving it would silently split the two. Only non-secret settings
    /// are stored here (see SecretStore for tokens).
    nonisolated public static func defaultConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/speaker_broadcast.json")
    }

    nonisolated public static func defaultHistoryURL() -> URL {
        BroadcastHistory.defaultURL()
    }

    public convenience init(
        configPath: URL = ConfigManager.defaultConfigURL(),
        historyPath: URL = ConfigManager.defaultHistoryURL(),
        secrets: SecretStore = .shared,
        fileSystem: ConfigFileSystem = LocalConfigFileSystem()
    ) {
        self.init(
            configPath: configPath, history: BroadcastHistory(fileURL: historyPath),
            secrets: secrets, fileSystem: fileSystem)
    }

    /// The settings at `configPath`, adding to `history` and reading the
    /// Google connection from `secrets`: the objects an engine shares.
    public init(
        configPath: URL,
        history: BroadcastHistory,
        secrets: SecretStore,
        fileSystem: ConfigFileSystem = LocalConfigFileSystem()
    ) {
        self.configPath = configPath
        self.file = SpeakerConfigFile(url: configPath, fileSystem: fileSystem)
        self.history = history
        self.secrets = secrets
        self.config = SpeakerConfig()
        loadConfig()
        reloadHistory()
        checkConnection()
    }

    /// Reads the file. No file: the defaults are written, so the CLI and
    /// the phone find one. A file that does not read: the defaults stay in
    /// memory, `configProblem` says why, and nothing is written.
    public func loadConfig() {
        switch file.read() {
        case .missing:
            configProblem = nil
            saveConfig()
        case .loaded(let loaded):
            configProblem = nil
            config = loaded
        case .unreadable(let why):
            configProblem = why.localizedDescription
            print("Error loading speaker config: \(why.localizedDescription)")
        }
    }

    /// Saves, or logs why not. False when nothing was written.
    @discardableResult
    public func saveConfig() -> Bool {
        do {
            try trySaveConfig()
            return true
        } catch {
            print("Error saving speaker config: \(error.localizedDescription)")
            return false
        }
    }

    /// Saves, merged into the file so keys other writers own survive.
    /// Throws, writing nothing, while `configProblem` is set or when the
    /// file on disk has stopped reading as a config since it was loaded.
    public func trySaveConfig() throws {
        if let configProblem {
            throw ConfigFileError.unreadable(path: configPath.path, reason: "refusing to save: \(configProblem)")
        }
        do {
            lastWritten = try file.write(config)
        } catch let error as ConfigFileError {
            configProblem = error.localizedDescription
            throw error
        }
    }

    /// Re-reads the config when something other than this process changes the
    /// file: the `speaker-broadcast` CLI, a skill, or the Mac agent acting for
    /// the phone. Without this the menu bar kept showing whatever it loaded at
    /// launch and would write that stale copy back on its next save, silently
    /// undoing the remote change.
    ///
    /// The DIRECTORY is watched, not the file. Every writer here (including
    /// `saveConfig`) replaces the file atomically, which is a rename: a
    /// descriptor on the old file would see one delete event and then watch
    /// an unlinked inode forever.
    public func startWatchingConfigFile() {
        guard watcher == nil else { return }
        let folder = configPath.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.folderChanged() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    /// Told on every change in the watched folder, after the settings are
    /// re-read. The app reads its role from the choice file here, which sits
    /// in the same folder (`~/.gemini/speaker_door.json`), so a choice made
    /// in the extension reaches it within a second.
    public var onFolderChange: (@MainActor () -> Void)?

    /// Something in the watched folder changed: the settings are re-read,
    /// then `onFolderChange` is told. Public so a test can drive it.
    public func folderChanged() {
        reloadIfChangedExternally()
        onFolderChange?()
    }

    public func stopWatchingConfigFile() {
        watcher?.cancel()
        watcher = nil
    }

    /// Applies the on-disk config when it differs from what this process
    /// last wrote. Public so a test can drive it without a real file event.
    ///
    /// A file that no longer reads sets `configProblem` (so nothing saves
    /// over it) and keeps the settings in memory. A chat-monitor change is
    /// passed on to `chatMonitor`, which starts, stops or restarts to match.
    public func reloadIfChangedExternally() {
        guard let data = try? file.fileSystem.read(configPath), data != lastWritten else { return }
        switch file.decode(data) {
        case .loaded(let fresh):
            lastWritten = data
            configProblem = nil
            let before = config.effectiveChatMonitor
            if fresh != config { config = fresh }
            reconcileChatMonitor(from: before, to: fresh.effectiveChatMonitor)
        case .unreadable(let why):
            configProblem = why.localizedDescription
        case .missing:
            break
        }
    }

    private func reconcileChatMonitor(from before: ChatMonitorConfig, to after: ChatMonitorConfig) {
        guard let monitor = chatMonitor else { return }
        switch ChatMonitorReconciliation.decide(old: before, new: after, isRunning: monitor.isRunning) {
        case .none: break
        case .start: monitor.start()
        case .stop: monitor.stop()
        case .restart:
            monitor.stop()
            monitor.start()
        }
    }

    /// Switches one chat source here, saves, and brings `chatMonitor`
    /// along as an edit on disk would: on from all off starts it, the last
    /// one off stops it, any other change restarts it. A change this
    /// process saves is not seen by the file watcher (`lastWritten`), so
    /// without this the menu bar's switches would leave the monitor as it
    /// was. False, with nothing changed, when the value was already so or
    /// the file would not take it.
    @discardableResult
    public func setChatSource(_ source: WritableKeyPath<ChatMonitorConfig, Bool>, _ isOn: Bool) -> Bool {
        let before = config.effectiveChatMonitor
        guard before[keyPath: source] != isOn else { return false }
        config.effectiveChatMonitor[keyPath: source] = isOn
        guard saveConfig() else {
            config.effectiveChatMonitor = before
            return false
        }
        reconcileChatMonitor(from: before, to: config.effectiveChatMonitor)
        return true
    }

    /// Mutes one Beeper network (`reading` false) or reads it again, and
    /// saves. The monitor is left alone: each poll reads the mutes fresh,
    /// and a restart would drop what arrived meanwhile. False, with
    /// nothing changed, when it was already so or the file would not take it.
    @discardableResult
    public func setBeeperNetwork(_ key: String, reading: Bool) -> Bool {
        let before = config.effectiveChatMonitor
        var after = before
        after.setBeeperNetwork(key, reading: reading)
        guard after.beeperMutedNetworks != before.beeperMutedNetworks else { return false }
        config.effectiveChatMonitor = after
        guard saveConfig() else {
            config.effectiveChatMonitor = before
            return false
        }
        return true
    }

    /// Switches one coding agent's announcements and saves. False, with
    /// nothing changed, when it was already so or the file would not take it.
    @discardableResult
    public func setAnnounces(_ agent: CodingAgent, _ isOn: Bool) -> Bool {
        let before = config
        guard before.announces(agent) != isOn else { return false }
        config.setAnnounces(agent, isOn)
        guard saveConfig() else {
            config = before
            return false
        }
        return true
    }

    public func toggleEnabled() {
        config.enabled.toggle()
        saveConfig()
    }

    public func setTarget(_ targetKey: String) {
        config.defaultTarget = targetKey
        saveConfig()
    }

    public func removeTarget(_ key: String) {
        config.removeTarget(key)
        saveConfig()
    }

    @discardableResult
    public func applyDiscovery(structure: HomeStructure, targets: [String: SpeakerDevice]) -> Bool {
        guard !targets.isEmpty else { return false }
        let changed = config.applyDiscovery(structureId: structure.id, structureName: structure.name, targets: targets)
        if changed { saveConfig() }
        return changed
    }

    /// Adds `item` to the history file -- under its lock, on top of whatever
    /// the CLI or the Stop hook added meanwhile -- and shows the result. If
    /// the file cannot be written the entry still shows, as before.
    public func addLogItem(_ item: BroadcastLogItem) {
        do {
            recentBroadcasts = try history.append(item)
        } catch {
            print("Error saving broadcast history: \(error.localizedDescription)")
            recentBroadcasts = Array(([item] + recentBroadcasts).prefix(BroadcastHistory.limit))
        }
    }

    /// Re-reads the history file, so entries `HomeSpeaker --say`, the Stop
    /// hook or another copy of the app wrote show up. The menu calls this
    /// each time it opens.
    public func reloadHistory() {
        let items = history.load()
        if items != recentBroadcasts { recentBroadcasts = items }
    }

    /// Re-reads the secret store; the Google login is "connected" when a
    /// refresh token is present.
    public func checkConnection() {
        let google = secrets.load().google
        isConnectedToGoogle = !(google?.refreshToken.isEmpty ?? true)
        googleEmail = google?.email
    }
}
