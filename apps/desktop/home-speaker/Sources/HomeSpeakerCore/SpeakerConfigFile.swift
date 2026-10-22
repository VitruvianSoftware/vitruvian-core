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

/// The bytes of the config file, behind a protocol so tests can stand in
/// for the disk.
public protocol ConfigFileSystem: Sendable {
    /// The file's bytes, or nil when there is no file.
    func read(_ url: URL) throws -> Data?
    /// Replaces the file in one move, creating its folder if needed.
    func write(_ data: Data, to url: URL) throws
}

public struct LocalConfigFileSystem: ConfigFileSystem {
    public init() {}

    public func read(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }
}

public enum ConfigFileError: Error, Equatable, LocalizedError {
    /// The file is there but is not a config this app can read. Writing
    /// over it would replace whatever is in it with built-in defaults.
    case unreadable(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path, let reason):
            return "\(path) could not be read (\(reason)). HomeSpeaker will not save over it until it reads again; fix or remove the file."
        }
    }
}

public enum ConfigFileRead: Equatable {
    case missing
    case loaded(SpeakerConfig)
    case unreadable(ConfigFileError)
}

/// `~/.gemini/speaker_broadcast.json`, read and written the one safe way.
///
/// The file is a shared contract: the Android remote's `macagent`, the
/// `speaker-broadcast` command and other local tooling write it too, and
/// some of them keep keys this app has never heard of. So a save:
/// - merges into the JSON already on disk, keeping every key that is not
///   this app's (top level, inside `chat_monitor`, and on each speaker);
/// - refuses outright when the file on disk does not read as a config,
///   rather than replace it with this process's defaults.
public struct SpeakerConfigFile: Sendable {
    public let url: URL
    public let fileSystem: ConfigFileSystem
    public var lockURL: URL { url.appendingPathExtension("lock") }

    public init(url: URL, fileSystem: ConfigFileSystem = LocalConfigFileSystem()) {
        self.url = url
        self.fileSystem = fileSystem
    }

    public func read() -> ConfigFileRead {
        do {
            guard let data = try fileSystem.read(url) else { return .missing }
            return decode(data)
        } catch {
            return .unreadable(.unreadable(path: url.path, reason: error.localizedDescription))
        }
    }

    public func decode(_ data: Data) -> ConfigFileRead {
        do {
            return .loaded(try JSONDecoder().decode(SpeakerConfig.self, from: data))
        } catch {
            return .unreadable(.unreadable(path: url.path, reason: Self.describe(error)))
        }
    }

    /// Writes `config`, merged into what is on disk, under `lockURL`.
    /// Returns the bytes written. Throws `ConfigFileError.unreadable`,
    /// writing nothing, when the file exists but cannot be read as a config.
    @discardableResult
    public func write(_ config: SpeakerConfig) throws -> Data {
        if fileSystem is LocalConfigFileSystem {
            return try FileLock.withExclusiveLock(at: lockURL) {
                try writeUnlocked(config)
            }
        } else {
            return try writeUnlocked(config)
        }
    }

    private func writeUnlocked(_ config: SpeakerConfig) throws -> Data {
        let existing: Data?
        do {
            existing = try fileSystem.read(url)
        } catch {
            throw ConfigFileError.unreadable(path: url.path, reason: error.localizedDescription)
        }
        var base: [String: Any] = [:]
        if let existing {
            if case .unreadable(let why) = decode(existing) { throw why }
            guard let object = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                throw ConfigFileError.unreadable(path: url.path, reason: "not a JSON object")
            }
            base = object
        }
        let data = try Self.encode(config, preserving: base)
        try fileSystem.write(data, to: url)
        return data
    }

    /// Reads the config (or defaults if missing), applies `update`, and writes
    /// it back merged into what is on disk, all under `lockURL`.
    @discardableResult
    public func modify(_ update: (inout SpeakerConfig) -> Void) throws -> Data {
        if fileSystem is LocalConfigFileSystem {
            return try FileLock.withExclusiveLock(at: lockURL) {
                try modifyUnlocked(update)
            }
        } else {
            return try modifyUnlocked(update)
        }
    }

    private func modifyUnlocked(_ update: (inout SpeakerConfig) -> Void) throws -> Data {
        let current: SpeakerConfig
        switch read() {
        case .loaded(let cfg): current = cfg
        case .missing: current = SpeakerConfig()
        case .unreadable(let err): throw err
        }
        var next = current
        update(&next)
        return try writeUnlocked(next)
    }

    /// `config` as JSON, laid over `existing`: pretty, keys sorted, as the
    /// app has always written it.
    public static func encode(_ config: SpeakerConfig, preserving existing: [String: Any]) throws -> Data {
        let ours = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any] ?? [:]
        let merged = merge(ours, over: existing)
        return try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
    }

    static let configKeys = Set(SpeakerConfig.CodingKeys.allCases.map(\.rawValue))
    static let chatMonitorKeys = Set(ChatMonitorConfig.CodingKeys.allCases.map(\.rawValue))
    static let deviceKeys = Set(SpeakerDevice.CodingKeys.allCases.map(\.rawValue))

    /// What is not ours in `old`, plus all of `new`. A key of ours that
    /// `new` leaves out (an optional set to nil) is removed: this app's view
    /// of its own keys wins, as it did when the whole file was rewritten.
    static func merge(_ new: [String: Any], over old: [String: Any]) -> [String: Any] {
        var out = layer(new, over: old, ours: configKeys)
        if let newMonitor = new["chat_monitor"] as? [String: Any], let oldMonitor = old["chat_monitor"] as? [String: Any] {
            out["chat_monitor"] = layer(newMonitor, over: oldMonitor, ours: chatMonitorKeys)
        }
        // Cloned custom voices configured from the Android app or remote agent are
        // preserved if this instance of the config did not specify any custom_voices.
        if new["custom_voices"] == nil, let oldVoices = old["custom_voices"] {
            out["custom_voices"] = oldVoices
        }
        // `targets` is a map, not a record: an alias this app dropped stays
        // dropped. A speaker that is still there keeps its foreign fields.
        if let newTargets = new["targets"] as? [String: Any], let oldTargets = old["targets"] as? [String: Any] {
            var targets = newTargets
            for (alias, device) in newTargets {
                if let device = device as? [String: Any], let before = oldTargets[alias] as? [String: Any] {
                    targets[alias] = layer(device, over: before, ours: deviceKeys)
                }
            }
            out["targets"] = targets
        }
        return out
    }

    private static func layer(_ new: [String: Any], over old: [String: Any], ours: Set<String>) -> [String: Any] {
        var out = old.filter { !ours.contains($0.key) }
        for (key, value) in new { out[key] = value }
        return out
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let c):
            return c.underlyingError.map { "not valid JSON: \($0.localizedDescription)" } ?? c.debugDescription
        case DecodingError.keyNotFound(let key, _):
            return "\"\(key.stringValue)\" is missing"
        case DecodingError.typeMismatch(_, let c), DecodingError.valueNotFound(_, let c):
            let path = c.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? c.debugDescription : "\"\(path)\" has the wrong type"
        default:
            return error.localizedDescription
        }
    }
}
