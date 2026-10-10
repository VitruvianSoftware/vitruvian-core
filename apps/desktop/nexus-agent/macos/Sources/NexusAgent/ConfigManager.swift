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

import SwiftUI
import Foundation
import Combine
import NexusAgentCore

// MARK: - CLI Provider Model

/// Represents a CLI backend that can handle prompts.
/// Use `{prompt}` and optionally `{model}` as placeholders in commandTemplate.
struct CLIProvider: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var commandTemplate: String
    var isBuiltIn: Bool

    /// Same id the Gemini CLI provider used, so a saved selection carries over.
    static let antigravity = CLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Antigravity CLI",
        commandTemplate: "agy -p \"{prompt}\" --output-format stream-json --dangerously-skip-permissions",
        isBuiltIn: true
    )

    static let ollama = CLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Ollama (claude)",
        commandTemplate: "ollama launch claude --model {model} -- -p \"{prompt}\"",
        isBuiltIn: true
    )

    static let claude = CLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Claude Code",
        commandTemplate: "claude -p \"{prompt}\"",
        isBuiltIn: true
    )

    init(id: UUID, name: String, commandTemplate: String, isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.commandTemplate = commandTemplate
        self.isBuiltIn = isBuiltIn
    }

    /// The same provider as the shared code holds it: field for field.
    init(_ shared: NexusAgentCLIProvider) {
        self.init(id: shared.id, name: shared.name,
                  commandTemplate: shared.commandTemplate, isBuiltIn: shared.isBuiltIn)
    }

    var shared: NexusAgentCLIProvider {
        NexusAgentCLIProvider(id: id, name: name, commandTemplate: commandTemplate, isBuiltIn: isBuiltIn)
    }
}

/// Reads and writes the bot's .env configuration file.
@MainActor
class ConfigManager: ObservableObject {
    @Published var botToken: String = ""
    @Published var allowedUserIds: String = ""
    @Published var workingDirectory: String = ""
    @Published var approvalMode: String = ConfigManager.defaultApprovalMode
    @Published var model: String = ""
    /// The row of the effort picker that is selected, by its tag: empty for
    /// agy's default, `low`, `medium` or `high`, or the `.env` line itself
    /// when it is a word that is none of those (`max`). See `EnvFields`
    /// for how the file's two lines become a row, and `save()` for how a
    /// row becomes the two lines.
    @Published var effort: String = ""

    /// The tags of the effort picker's four fixed rows.
    static let namedEfforts = NexusAgentEffort.allCases.map(\.rawValue)

    /// The `.env` effort line as written, when it is what is selected and
    /// it is none of the four fixed rows: the picker then has one more
    /// row, for it. Nil once a fixed row is picked, and the row goes.
    var effortFromFile: String? {
        Self.namedEfforts.contains(effort) ? nil : effort
    }
    @Published var autoStart: Bool = false

    // Hotkey config (stored in UserDefaults, not .env)
    @Published var hotkeyKey: String = "g"
    @Published var hotkeyModifiers: Int = 0  // NSEvent.ModifierFlags raw value

    // AI Backend providers.
    //
    // There is one record of them, and this class keeps no copy of it: the
    // chat chooses a provider through the engine, and a copy here would put
    // the old choice back on the next save. Reading goes through the engine;
    // a change is written through the host, at once, and the engine is told
    // so the chat follows. The views bind to these as they always did.

    /// The built-in providers, then the user's own.
    var providers: [CLIProvider] {
        get { engine.providers.map { CLIProvider($0) } }
        set {
            objectWillChange.send()
            host.savedProviders = newValue.map(\.shared)
            // Also falls back to Antigravity if the chosen provider was removed.
            engine.providersChanged()
        }
    }

    var activeProviderId: UUID {
        get { engine.activeProvider.id }
        set {
            objectWillChange.send()
            host.chosenProviderID = newValue
            engine.providersChanged()
        }
    }

    // Update preferences
    @Published var autoCheckUpdates: Bool = true

    /// The currently selected provider.
    var activeProvider: CLIProvider { CLIProvider(engine.activeProvider) }
    
    /// What the approval mode shows when `.env` does not say.
    private static let defaultApprovalMode = "yolo"

    /// Reads and writes `.env` by the rules this app shares with Vitruvian.
    private let engine: NexusAgentEngine
    /// Keeps the saved providers and the chosen one.
    private let host: StandaloneHost
    private var cancellables: Set<AnyCancellable> = []

    /// The six values of `.env` that Settings shows, as text.
    private struct EnvFields {
        var botToken = ""
        var allowedUserIds = ""
        var workingDirectory = ""
        var approvalMode = ""
        var model = ""
        var effort = ""

        init() {}

        init(_ configuration: NexusAgentConfiguration) {
            botToken = configuration.botToken
            allowedUserIds = configuration.allowedUserIDs
            workingDirectory = configuration.workingDirectory
            // Shown exactly as the bot reads it. A line with nothing after the `=`
            // is "default" (ask each time) to the bot, so it is here too: showing
            // YOLO for it meant the next save wrote `yolo` and silently let the
            // bot skip every permission prompt.
            approvalMode = configuration.approvalMode.rawValue
            model = configuration.model
            // The row for what the file's two lines say, AGY_EFFORT and
            // AGY_THINKING:
            //   an effort that is a row's name, in any letter-case: that row
            //   any other effort (`max`): a row of its own, as written
            //   no effort, and thinking exactly `true`: High
            //   no effort otherwise: agy default
            // An effort line wins over the thinking line, as it does for
            // the bot.
            effort = configuration.unnamedEffort ?? configuration.effort.rawValue
        }

        /// Each of the six, to go through them one by one.
        static let each: [WritableKeyPath<EnvFields, String>] = [
            \.botToken, \.allowedUserIds, \.workingDirectory, \.approvalMode, \.model, \.effort,
        ]
    }

    /// The six fields the views bind to, read and set together. Setting
    /// leaves alone a field that already holds its value, so the views are
    /// told only of a real change.
    private var fields: EnvFields {
        get {
            var values = EnvFields()
            values.botToken = botToken
            values.allowedUserIds = allowedUserIds
            values.workingDirectory = workingDirectory
            values.approvalMode = approvalMode
            values.model = model
            values.effort = effort
            return values
        }
        set {
            if botToken != newValue.botToken { botToken = newValue.botToken }
            if allowedUserIds != newValue.allowedUserIds { allowedUserIds = newValue.allowedUserIds }
            if workingDirectory != newValue.workingDirectory { workingDirectory = newValue.workingDirectory }
            if approvalMode != newValue.approvalMode { approvalMode = newValue.approvalMode }
            if model != newValue.model { model = newValue.model }
            if effort != newValue.effort { effort = newValue.effort }
        }
    }

    /// What the fields were last filled with, or last saved as: a field
    /// that still holds this has not been touched by the user since.
    private var untouched = EnvFields()
    /// The engine's configuration as it last stood, to tell which of its
    /// values a change changed.
    private var engineHeld = EnvFields()
    /// The configuration the effort row was last filled from. It holds the
    /// effort as the file says it, which the row alone does not: High may
    /// be `HIGH`, or no effort line and `AGY_THINKING=true`.
    private var effortRead = NexusAgentConfiguration()

    init(engine: NexusAgentEngine, host: StandaloneHost) {
        self.engine = engine
        self.host = host

        // Load preferences from UserDefaults
        autoStart = UserDefaults.standard.bool(forKey: "autoStart")
        hotkeyKey = UserDefaults.standard.string(forKey: "hotkeyKey") ?? "g"
        hotkeyModifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        if hotkeyModifiers == 0 {
            // Default: ⌘+Shift
            hotkeyModifiers = Int(NSEvent.ModifierFlags([.command, .shift]).rawValue)
        }


        // Update preferences
        if UserDefaults.standard.object(forKey: "autoCheckUpdates") != nil {
            autoCheckUpdates = UserDefaults.standard.bool(forKey: "autoCheckUpdates")
        }

        // A built-in list from before the Gemini CLI became Antigravity
        // holds the retired `gemini -p …` template for the same provider.
        // The list's key was bumped to v3 to drop those once; the old one is
        // removed here. The user's own providers are under another key.
        UserDefaults.standard.removeObject(forKey: "builtInProviders_v2")

        // The chat chooses a provider through the engine, not through this
        // class, and Settings must show it. The publisher fires just before
        // the engine takes the new value, which is when SwiftUI wants to
        // be told.
        engine.$configuration
            .map(\.activeProvider)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        load()

        // The chat saves the model and the working folder through the
        // engine, and the engine reads `.env` again each time the chat is
        // shown. Settings follows: otherwise it would go on showing the old
        // value and write it back on its next save.
        engineHeld = EnvFields(engine.configuration)
        engine.$configuration
            .dropFirst()
            .sink { [weak self] configuration in self?.follow(EnvFields(configuration), read: configuration) }
            .store(in: &cancellables)
    }

    /// Takes over the values the engine's configuration has just changed,
    /// but never one the user is editing: a field is refreshed only if it
    /// still holds what it was last filled with. A value the engine did not
    /// change is left alone too, which keeps the template shown when there
    /// is no `.env` yet.
    ///
    /// Nothing is taken over unless `.env` is there to be read and has
    /// something in it. This is for the file that has been DELETED while
    /// the app runs. The engine keeps its settings when the file is there
    /// but unreadable or blank; when the file is gone it rightly holds the
    /// empty configuration (no token, no whitelist, approval mode `yolo`),
    /// as the bot would. Settings is another matter: following that would
    /// blank every untouched field, and the next Save would write the
    /// blanks, a bot anyone may use that skips every permission prompt. So
    /// the fields stay, and Save puts the file back. The same guard covers
    /// a deleted file that comes back unreadable or blank, where the engine
    /// has nothing left to keep and is empty still. The record of what the
    /// engine held is not moved either, so the file's return is compared
    /// with what Settings last saw in it.
    private func follow(_ fresh: EnvFields, read: NexusAgentConfiguration) {
        guard envFileHasText else { return }
        var shown = fields
        for field in EnvFields.each {
            let value = fresh[keyPath: field]
            if value != engineHeld[keyPath: field], shown[keyPath: field] == untouched[keyPath: field] {
                shown[keyPath: field] = value
            }
            if shown[keyPath: field] == value {
                untouched[keyPath: field] = value
            }
        }
        fields = shown
        engineHeld = fresh
        // The row shows what the file now says: remember how it says it.
        if shown.effort == fresh.effort { effortRead = read }
    }

    /// Whether `.env` can be read right now and holds more than blank lines.
    private var envFileHasText: Bool {
        guard let text = try? String(contentsOfFile: engine.envFilePath, encoding: .utf8) else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The fields as they stand, which is what an untouched field holds
    /// from now on.
    private func markFieldsUntouched() {
        untouched = fields
    }

    // MARK: - Provider Persistence

    /// Writes the record as it stands: both lists and the choice. Every
    /// change is already written when it is made, so this adds nothing for
    /// a user who has saved before; on a first save it puts the three keys
    /// in place, as this app always has.
    func saveProviders() {
        host.savedProviders = engine.providers
        host.chosenProviderID = engine.activeProvider.id
        engine.providersChanged()
    }

    // MARK: - Load .env

    /// Called once, at launch, and fills every field. The engine reads
    /// `.env` again when polling starts, when the bot is started and when
    /// the chat is shown (the 2-second timer only refreshes status and the
    /// log); after this a field follows the engine only while the user has
    /// not touched it (`follow`), so nothing overwrites what is being typed
    /// in Settings.
    func load() {
        engine.load()
        if (try? String(contentsOfFile: engine.envFilePath, encoding: .utf8)) != nil {
            show(engine.configuration)
        } else {
            // No .env yet: try .env.example as a template
            let examplePath = (engine.botDirectory as NSString).appendingPathComponent(".env.example")
            if let example = try? String(contentsOfFile: examplePath, encoding: .utf8) {
                show(NexusAgentEnvFile.parse(example))
            }
        }
        markFieldsUntouched()
    }

    /// Copies what the file says into the fields the views bind to.
    private func show(_ configuration: NexusAgentConfiguration) {
        fields = EnvFields(configuration)
        effortRead = configuration
    }

    // MARK: - Save .env

    /// Returns whether the `.env` was written. The preferences and the hotkey
    /// are saved either way.
    @discardableResult
    func save() -> Bool {
        // The effort row becomes the file's two lines, AGY_EFFORT and
        // AGY_THINKING, by the shared rule (`NexusAgentEnvFile.render`):
        //   the row the file was read as, not changed: both lines stay as
        //     they are (`HIGH` stays `HIGH`, `max` stays `max`, a High
        //     that is `AGY_THINKING=true` stays an empty effort line)
        //   Low, Medium or High, picked: AGY_EFFORT is that name, and
        //     AGY_THINKING stays as it is, since the effort line wins
        //   agy default, picked: AGY_EFFORT is empty, and an
        //     AGY_THINKING=true becomes false, or it would still mean High
        // Starting from what was read is what tells the first case from
        // the others: setting the effort is the user's choice.
        var configuration = effortRead
        if EnvFields(effortRead).effort != effort { configuration.effort = .parse(effort) }
        configuration.botToken = botToken
        configuration.allowedUserIDs = allowedUserIds
        configuration.workingDirectory = workingDirectory
        configuration.approvalMode = .parse(approvalMode)
        configuration.model = model
        // Which program the bot runs is this app's own saved choice. It is
        // handed over on every save: the engine does not keep it, and forgets
        // it each time it reads the file.
        let provider = activeProvider
        configuration.botProvider = NexusAgentCLIProvider(
            id: provider.id, name: provider.name,
            commandTemplate: provider.commandTemplate, isBuiltIn: provider.isBuiltIn)
        // A save that fails leaves the reason with the engine, which the log
        // panel shows.
        let saved = engine.save(configuration)
        // What was just written is what the fields hold: they count as
        // untouched again, and follow the chat's next change.
        if saved {
            markFieldsUntouched()
            effortRead = engine.configuration
        }

        // Save all UserDefaults preferences
        UserDefaults.standard.set(autoStart, forKey: "autoStart")
        UserDefaults.standard.set(autoCheckUpdates, forKey: "autoCheckUpdates")
        UserDefaults.standard.set(hotkeyKey, forKey: "hotkeyKey")
        UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers")

        saveProviders()
        UserDefaults.standard.synchronize()

        // Notify hotkey controller to re-register
        QuickPromptWindowController.shared.updateHotkey(
            key: hotkeyKey,
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers))
        )
        return saved
    }

    // MARK: - Validation

    var isConfigured: Bool {
        !botToken.isEmpty && botToken != "your_bot_token_here"
    }

    var configStatus: String {
        if !isConfigured {
            return "⚠️ Bot token not configured"
        }
        if allowedUserIds.isEmpty {
            return "⚠️ No user whitelist (anyone can use the bot)"
        }
        return "✅ Configured"
    }
}

// MARK: - Antigravity CLI detection

/// What the Settings window shows about the agy install. Runs the binary,
/// so call it off the main thread.
enum AgyInfo {
    struct Model: Identifiable, Hashable {
        let id: String
        let name: String
    }

    /// AGY_BIN, then the usual install locations, then nil.
    static func locate() -> String? {
        NexusAgentSupport.locateAgent(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory(),
                                      isExecutable: FileManager.default.isExecutableFile(atPath:))
    }

    static func run(_ arguments: [String], timeout: TimeInterval = 20) -> String? {
        guard let bin = locate() else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = arguments
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        proc.environment = env
        do { try proc.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if proc.isRunning { proc.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func version() -> String? {
        guard let out = run(["--version"]) else { return nil }
        return out.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    /// `agy models` prints a "Fetching…" line, then `id<TAB>display name` rows.
    static func parseModels(_ raw: String) -> [Model] {
        NexusAgentSupport.parseModels(raw).map { Model(id: $0.id, name: $0.name) }
    }

    static func models() -> [Model] {
        parseModels(run(["models"], timeout: 60) ?? "")
    }
}
