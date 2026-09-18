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

    private let fileManager = FileManager.default
    private let configPath: URL
    private let tokensPath: URL
    private let logHistoryPath: URL

    public init() {
        let home = fileManager.homeDirectoryForCurrentUser
        self.configPath = home.appendingPathComponent(".gemini/speaker_broadcast.json")
        self.tokensPath = home.appendingPathComponent(".gemini/antigravity/mcp_oauth_tokens.json")
        self.logHistoryPath = home.appendingPathComponent(".gemini/speaker_history.json")

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
            let decoded = try JSONDecoder().decode(SpeakerConfig.self, from: data)
            self.config = decoded
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
            try data.write(to: configPath, options: .atomic)
        } catch {
            print("Error saving speaker config: \(error)")
        }
    }

    public func toggleEnabled() {
        config.enabled.toggle()
        saveConfig()
    }

    public func setTarget(_ targetKey: String) {
        config.defaultTarget = targetKey
        saveConfig()
    }

    public func addLogItem(_ item: BroadcastLogItem) {
        recentBroadcasts.insert(item, at: 0)
        if recentBroadcasts.count > 30 {
            recentBroadcasts = Array(recentBroadcasts.prefix(30))
        }
        saveHistory()
    }

    public func checkConnection() {
        if fileManager.fileExists(atPath: tokensPath.path) {
            do {
                let data = try Data(contentsOf: tokensPath)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["https://home.googleapis.com/mcp"] != nil {
                    self.isConnectedToGoogle = true
                    return
                }
            } catch {}
        }
        self.isConnectedToGoogle = false
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
            let encoder = JSONEncoder()
            let data = try encoder.encode(recentBroadcasts)
            try data.write(to: logHistoryPath, options: .atomic)
        } catch {}
    }
}
