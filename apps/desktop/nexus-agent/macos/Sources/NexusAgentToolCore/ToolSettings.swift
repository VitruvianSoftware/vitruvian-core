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
import NexusAgentCore
import VitruvianToolProtocol

/// What the shared engine asks its app, answered by the tool: the settings
/// the Vitruvian app draws and hands over (`storage`), and the ones only
/// the tool keeps, in `settings.json` in the folder the app gives it.
///
/// Four preferences have a title in the manifest, so the app draws them in
/// the tool's detail and is their keeper: the bot folder, starting the bot
/// at launch, plan mode and worktree mode. They are read from what the app
/// hands over at every start and on every `preferences/changed`, and when
/// the chat changes one (plan mode, worktree mode) the tool tells the app
/// through `preferenceChanged`, so the app's copy follows. The six others
/// have no title: the provider chosen, the providers of the person's own,
/// the prompt history, the archived Claude sessions, the model chosen for
/// each provider, and the sessions pinned or renamed in the drawer. The
/// app's Nexus Agent feature hands them over once, on the tool's first run;
/// from then on this file is the one copy, and the handed copies are
/// cleared. The archived sessions are the one exception that is written
/// back: when the chat archives or restores one, the app's copy is told,
/// so the app's own feature lists the same sessions.
@MainActor
public final class ToolSettings: NexusAgentHost {
    /// The preferences, by the ids the manifest declares.
    public enum Key {
        public static let botDirectory = "botDirectory"
        public static let autoStart = "autoStart"
        public static let planMode = "planMode"
        public static let worktreeMode = "worktreeMode"
        public static let chosenProvider = "chosenProvider"
        public static let savedProviders = "savedProviders"
        public static let promptHistory = "promptHistory"
        public static let hiddenClaudeSessions = "hiddenClaudeSessions"
        public static let chosenModels = "chosenModels"
        public static let sessionPreferences = "sessionPreferences"
        /// The ones the app draws and keeps.
        public static let titled = [botDirectory, autoStart, planMode, worktreeMode]
        /// The ones handed over once.
        public static let untitled = [chosenProvider, savedProviders, promptHistory, hiddenClaudeSessions,
                                      chosenModels, sessionPreferences]
    }

    /// Everything kept, as `settings.json` holds it.
    public struct Values: Codable, Equatable, Sendable {
        public var botDirectory = ""
        public var autoStart = false
        public var planMode = false
        public var worktreeMode = false
        public var chosenProvider = ""
        public var savedProviders: [NexusAgentCLIProvider] = []
        public var promptHistory: [String] = []
        public var hiddenClaudeSessions: [String] = []
        /// The model chosen for each provider, by the provider's id as text.
        public var chosenModels: [String: String] = [:]
        public var sessionPreferences = NexusAgentSessionPreferences()

        public init() {}

        private enum CodingKeys: String, CodingKey {
            case botDirectory, autoStart, planMode, worktreeMode, chosenProvider, savedProviders, promptHistory
            case hiddenClaudeSessions, chosenModels, sessionPreferences
        }

        /// Every key may be missing: a file an earlier version wrote lacks
        /// the newer ones, and is read with their defaults rather than
        /// thrown away as unreadable, which would start a first run again.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            botDirectory = try container.decodeIfPresent(String.self, forKey: .botDirectory) ?? ""
            autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
            planMode = try container.decodeIfPresent(Bool.self, forKey: .planMode) ?? false
            worktreeMode = try container.decodeIfPresent(Bool.self, forKey: .worktreeMode) ?? false
            chosenProvider = try container.decodeIfPresent(String.self, forKey: .chosenProvider) ?? ""
            savedProviders = try container.decodeIfPresent([NexusAgentCLIProvider].self, forKey: .savedProviders) ?? []
            promptHistory = try container.decodeIfPresent([String].self, forKey: .promptHistory) ?? []
            hiddenClaudeSessions = try container.decodeIfPresent([String].self, forKey: .hiddenClaudeSessions) ?? []
            chosenModels = try container.decodeIfPresent([String: String].self, forKey: .chosenModels) ?? [:]
            sessionPreferences = try container.decodeIfPresent(NexusAgentSessionPreferences.self,
                                                               forKey: .sessionPreferences) ?? NexusAgentSessionPreferences()
        }
    }

    public static let fileName = "settings.json"

    public private(set) var values: Values
    /// True until the first `apply(handed:)` has written the file: the
    /// untitled preferences are then taken from what the app handed over.
    public private(set) var isFirstRun: Bool
    /// The app's language, as a tag; the host's strings follow it.
    public var language = "en"
    /// Told of a titled preference the tool changed itself, with the value
    /// the app should keep.
    public var preferenceChanged: (String, JSONValue) -> Void = { _, _ in }
    /// Told of a turn that stopped for approval, and of one that ended,
    /// with whether the chat was on screen.
    public var onApproval: (NexusAgentTurnNotice) -> Void = { _ in }
    public var onFinished: (NexusAgentTurnNotice, Bool) -> Void = { _, _ in }

    private let file: URL
    private let log: (String) -> Void

    /// Reads `settings.json` in `folder`, if there is one.
    public init(folder: URL, log: @escaping (String) -> Void = { _ in }) {
        file = folder.appendingPathComponent(Self.fileName)
        self.log = log
        if let data = try? Data(contentsOf: file), let read = try? JSONDecoder().decode(Values.self, from: data) {
            values = read
            isFirstRun = false
        } else {
            values = Values()
            isFirstRun = true
        }
    }

    // MARK: - What the app hands over

    /// Takes what the app handed over: the titled preferences always, the
    /// untitled ones on the first run only, and writes the file. Returns
    /// the untitled keys that were taken, for the caller to clear in the
    /// app's storage. A value of the wrong kind is left out and logged.
    @discardableResult
    public func apply(handed: [String: JSONValue]) -> [String] {
        var taken: [String] = []
        for (key, value) in handed where Key.titled.contains(key) {
            if !take(key, value) { log("the preference \(key) is not of its kind: \(value)") }
        }
        if isFirstRun {
            for (key, value) in handed where Key.untitled.contains(key) {
                guard let text = value.stringValue, !text.isEmpty else { continue }
                if take(key, value) { taken.append(key) } else { log("the handed \(key) could not be read") }
            }
        }
        isFirstRun = false
        save()
        return taken.sorted()
    }

    /// The person changed a titled preference in the app.
    public func changed(_ handed: [String: JSONValue]) {
        for (key, value) in handed where Key.titled.contains(key) {
            if !take(key, value) { log("the preference \(key) is not of its kind: \(value)") }
        }
        save()
    }

    private func take(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case Key.botDirectory:
            guard let text = value.stringValue else { return false }
            values.botDirectory = text
        case Key.autoStart:
            guard let flag = value.boolValue else { return false }
            values.autoStart = flag
        case Key.planMode:
            guard let flag = value.boolValue else { return false }
            values.planMode = flag
        case Key.worktreeMode:
            guard let flag = value.boolValue else { return false }
            values.worktreeMode = flag
        case Key.chosenProvider:
            guard let text = value.stringValue else { return false }
            values.chosenProvider = text
        case Key.savedProviders:
            guard let list = Self.decode([NexusAgentCLIProvider].self, value) else { return false }
            values.savedProviders = list
        case Key.promptHistory:
            guard let list = Self.decode([String].self, value) else { return false }
            values.promptHistory = list
        case Key.hiddenClaudeSessions:
            guard let list = Self.decode([String].self, value) else { return false }
            values.hiddenClaudeSessions = list
        case Key.chosenModels:
            guard let models = Self.decode([String: String].self, value) else { return false }
            values.chosenModels = models
        case Key.sessionPreferences:
            guard let preferences = Self.decode(NexusAgentSessionPreferences.self, value) else { return false }
            values.sessionPreferences = preferences
        default:
            return false
        }
        return true
    }

    /// A handed list is JSON text, as the app's feature kept it.
    private static func decode<Value: Decodable>(_ type: Value.Type, _ value: JSONValue) -> Value? {
        guard let text = value.stringValue, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(values) else { return }
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            log("settings.json could not be written: \(error)")
        }
    }

    // MARK: - NexusAgentHost

    public var configuredBotDirectory: String { values.botDirectory }

    public var startsBotAtLaunch: Bool { values.autoStart }

    public var planMode: Bool {
        get { values.planMode }
        set {
            guard values.planMode != newValue else { return }
            values.planMode = newValue
            save()
            preferenceChanged(Key.planMode, .bool(newValue))
        }
    }

    public var worktreeMode: Bool {
        get { values.worktreeMode }
        set {
            guard values.worktreeMode != newValue else { return }
            values.worktreeMode = newValue
            save()
            preferenceChanged(Key.worktreeMode, .bool(newValue))
        }
    }

    public var hiddenClaudeSessionIDs: [String] {
        get { values.hiddenClaudeSessions }
        set {
            let changed = newValue != values.hiddenClaudeSessions
            values.hiddenClaudeSessions = newValue
            save()
            // The app keeps it as JSON text, as it handed it over.
            if changed, let data = try? JSONEncoder().encode(newValue) {
                preferenceChanged(Key.hiddenClaudeSessions, .string(String(decoding: data, as: UTF8.self)))
            }
        }
    }

    /// Kept by the provider's id as text, which JSON can key an object by.
    public var chosenModels: [UUID: String] {
        get {
            Dictionary(values.chosenModels.compactMap { key, model in UUID(uuidString: key).map { ($0, model) } },
                       uniquingKeysWith: { first, _ in first })
        }
        set {
            values.chosenModels = Dictionary(newValue.map { ($0.key.uuidString, $0.value) },
                                             uniquingKeysWith: { first, _ in first })
            save()
        }
    }

    public var sessionPreferences: NexusAgentSessionPreferences {
        get { values.sessionPreferences }
        set {
            values.sessionPreferences = newValue
            save()
        }
    }

    public var chosenProviderID: UUID? {
        get { UUID(uuidString: values.chosenProvider) }
        set {
            values.chosenProvider = newValue?.uuidString ?? ""
            save()
        }
    }

    public var savedProviders: [NexusAgentCLIProvider] {
        get { values.savedProviders }
        set {
            values.savedProviders = newValue
            save()
        }
    }

    public var promptHistory: [String] {
        get { values.promptHistory }
        set {
            values.promptHistory = newValue
            save()
        }
    }

    public var strings: NexusAgentHostStrings { Self.strings(for: language) }

    /// The engine's text in `language`: the tool's words where it has
    /// them, and the shared English for the rest.
    public static func strings(for language: String) -> NexusAgentHostStrings {
        NexusAgentHostStrings(untitledSession: Words.text("untitledSession", language),
                              missingAgent: Words.text("missingAgent", language),
                              agentFailed: Words.text("agentFailed", language),
                              replyStopped: Words.text("replyStopped", language),
                              emptyReply: Words.text("emptyReply", language))
    }

    public func turnNeedsApproval(_ notice: NexusAgentTurnNotice) {
        onApproval(notice)
    }

    public func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {
        onFinished(notice, isChatVisible)
    }
}
