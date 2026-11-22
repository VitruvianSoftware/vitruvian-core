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
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import Foundation

/// Sensitive environment values (an API key, a gateway token) kept per provider in one JSON file
/// in the app's state folder, readable by the user alone (mode 0600), so none sits in the plain
/// settings or the bot's `.env`.
///
/// The file moves with `--state-dir` because it lives under `Environment.stateDirectory`. It is
/// written through `Environment.writePrivateFile`, the way the bot's own secrets are. The
/// Keychain is a follow-up once Developer ID signing ships (docs/designs/vitruvian-code-acp.md,
/// section 3). Values are only ever read to hand to the Claude helper in its first message:
/// nothing here puts one in a command line, an environment or a log, and `keys(for:)` never
/// returns one.
@MainActor
public struct AgentSecrets {
    /// The file's name inside the state folder.
    public static let fileName = "agent-secrets.json"

    /// Where the file is.
    public let path: String

    private let readFile: (String) -> String?
    private let fileExists: (String) -> Bool
    private let writePrivateFile: (String, String) -> Bool

    public init(environment: VitruvianCodeEngine.Environment) {
        self.init(
            stateDirectory: environment.stateDirectory,
            readFile: environment.readFile,
            fileExists: environment.fileExists,
            writePrivateFile: environment.writePrivateFile
        )
    }

    public init(
        stateDirectory: String,
        readFile: @escaping (String) -> String?,
        fileExists: @escaping (String) -> Bool,
        writePrivateFile: @escaping (String, String) -> Bool
    ) {
        self.path = (stateDirectory as NSString).appendingPathComponent(Self.fileName)
        self.readFile = readFile
        self.fileExists = fileExists
        self.writePrivateFile = writePrivateFile
    }

    private struct Stored: Codable {
        var version: Int = 1
        /// Provider ID (the UUID string) to environment variable name to value.
        var providers: [String: [String: String]] = [:]
    }

    private enum Loaded {
        case stored(Stored)
        /// There is a file and it cannot be read as ours. It is never written over.
        case unreadable
    }

    private func load() -> Loaded {
        guard fileExists(path) else { return .stored(Stored()) }
        guard let text = readFile(path),
              let stored = try? JSONDecoder().decode(Stored.self, from: Data(text.utf8)) else {
            return .unreadable
        }
        return .stored(stored)
    }

    private func save(_ stored: Stored) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(stored),
              let text = String(data: data, encoding: .utf8) else { return false }
        return writePrivateFile(path, text)
    }

    /// True for a name an environment variable can have: not empty, no `=` and no NUL.
    public static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && !key.contains("=") && !key.contains("\0")
    }

    /// The provider's values, keyed by variable name. Empty when it has none or the file cannot
    /// be read.
    public func values(for providerID: UUID) -> [String: String] {
        guard case .stored(let stored) = load() else { return [:] }
        return stored.providers[providerID.uuidString] ?? [:]
    }

    /// The names of the provider's values, sorted. Never a value.
    public func keys(for providerID: UUID) -> [String] {
        values(for: providerID).keys.sorted()
    }

    /// Stores `value` under `key` for the provider. False when the name is not a valid one, the
    /// file is there but unreadable (it is left as it is), or the write failed.
    @discardableResult
    public func set(_ value: String, forKey key: String, provider providerID: UUID) -> Bool {
        guard Self.isValidKey(key), !value.contains("\0"), case .stored(var stored) = load() else { return false }
        var mine = stored.providers[providerID.uuidString] ?? [:]
        mine[key] = value
        stored.providers[providerID.uuidString] = mine
        return save(stored)
    }

    /// Removes the value stored under `key`. True when it is gone afterwards, including when it
    /// was never there.
    @discardableResult
    public func remove(key: String, provider providerID: UUID) -> Bool {
        guard case .stored(var stored) = load() else { return false }
        guard var mine = stored.providers[providerID.uuidString], mine[key] != nil else { return true }
        mine.removeValue(forKey: key)
        if mine.isEmpty {
            stored.providers.removeValue(forKey: providerID.uuidString)
        } else {
            stored.providers[providerID.uuidString] = mine
        }
        return save(stored)
    }
}
