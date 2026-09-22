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
    public static let shared = ConfigManager()

    @Published public var config: SpeakerConfig
    @Published public var recentBroadcasts: [BroadcastLogItem] = []
    @Published public var isConnectedToGoogle: Bool = false
    @Published public var googleEmail: String?

    private let fileManager = FileManager.default
    private let configPath: URL
    private let logHistoryPath: URL
    private let secrets: SecretStore

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
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/speaker_history.json")
    }

    public init(
        configPath: URL = ConfigManager.defaultConfigURL(),
        historyPath: URL = ConfigManager.defaultHistoryURL(),
        secrets: SecretStore = .shared
    ) {
        self.configPath = configPath
        self.logHistoryPath = historyPath
        self.secrets = secrets
        self.config = SpeakerConfig()
        loadConfig()
        loadHistory()
        checkConnection()
    }

    public func loadConfig() {
        guard fileManager.fileExists(atPath: configPath.path) else {
            saveConfig()
            return
        }
        do {
            let data = try Data(contentsOf: configPath)
            self.config = try JSONDecoder().decode(SpeakerConfig.self, from: data)
        } catch {
            print("Error loading speaker config: \(error)")
        }
    }

    public func saveConfig() {
        do {
            let folder = configPath.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: folder.path) {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            lastWritten = data
            try data.write(to: configPath, options: .atomic)
        } catch {
            print("Error saving speaker config: \(error)")
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
        source.setEventHandler { [weak self] in self?.reloadIfChangedExternally() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    public func stopWatchingConfigFile() {
        watcher?.cancel()
        watcher = nil
    }

    /// Applies the on-disk config when it differs from what this process
    /// last wrote. Public so a test can drive it without a real file event.
    public func reloadIfChangedExternally() {
        guard let data = try? Data(contentsOf: configPath), data != lastWritten else { return }
        guard let fresh = try? JSONDecoder().decode(SpeakerConfig.self, from: data) else { return }
        lastWritten = data
        if fresh != config { config = fresh }
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
        config.targets.removeValue(forKey: key)
        if config.defaultTarget == key {
            config.defaultTarget = config.uniqueTargets().first?.key ?? ""
        }
        saveConfig()
    }

    public func applyDiscovery(structure: HomeStructure, targets: [String: SpeakerDevice]) {
        config.applyDiscovery(structureId: structure.id, structureName: structure.name, targets: targets)
        saveConfig()
    }

    public func addLogItem(_ item: BroadcastLogItem) {
        recentBroadcasts.insert(item, at: 0)
        if recentBroadcasts.count > 30 {
            recentBroadcasts = Array(recentBroadcasts.prefix(30))
        }
        saveHistory()
    }

    /// Re-reads the secret store; the Google login is "connected" when a
    /// refresh token is present.
    public func checkConnection() {
        let google = secrets.load().google
        isConnectedToGoogle = !(google?.refreshToken.isEmpty ?? true)
        googleEmail = google?.email
    }

    private func loadHistory() {
        guard fileManager.fileExists(atPath: logHistoryPath.path) else { return }
        do {
            let data = try Data(contentsOf: logHistoryPath)
            self.recentBroadcasts = try JSONDecoder().decode([BroadcastLogItem].self, from: data)
        } catch {}
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(recentBroadcasts)
            try data.write(to: logHistoryPath, options: .atomic)
        } catch {}
    }
}
