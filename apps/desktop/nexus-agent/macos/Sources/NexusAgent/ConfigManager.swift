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

    static let builtIns: [CLIProvider] = [.antigravity, .claude, .ollama]
}

/// Reads and writes the bot's .env configuration file.
@MainActor
class ConfigManager: ObservableObject {
    /// Shared instance — set during app init for cross-component access.
    static var shared: ConfigManager!
    @Published var botToken: String = ""
    @Published var allowedUserIds: String = ""
    @Published var workingDirectory: String = ""
    @Published var approvalMode: String = ConfigManager.defaultApprovalMode
    @Published var model: String = ""
    /// agy --effort (low|medium|high); empty means agy's default.
    @Published var effort: String = ""
    @Published var autoStart: Bool = false



    // Hotkey config (stored in UserDefaults, not .env)
    @Published var hotkeyKey: String = "g"
    @Published var hotkeyModifiers: Int = 0  // NSEvent.ModifierFlags raw value

    // AI Backend providers (stored in UserDefaults)
    @Published var providers: [CLIProvider] = CLIProvider.builtIns
    @Published var activeProviderId: UUID = CLIProvider.antigravity.id

    // Update preferences
    @Published var autoCheckUpdates: Bool = true

    /// The currently selected provider.
    var activeProvider: CLIProvider {
        providers.first { $0.id == activeProviderId } ?? CLIProvider.antigravity
    }
    
    var hotkeyDisplayString: String {
        var parts: [String] = []
        let mods = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers))
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        parts.append(hotkeyKey.uppercased())
        return parts.joined()
    }

    /// What the approval mode shows when `.env` does not say.
    private static let defaultApprovalMode = "yolo"

    /// Reads and writes `.env` by the rules this app shares with Vitruvian.
    private let engine: NexusAgentEngine

    init(engine: NexusAgentEngine) {
        self.engine = engine

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

        // Load providers from UserDefaults
        loadProviders()

        load()
    }

    // MARK: - Provider Persistence

    private func loadProviders() {
        // Load user-defined (non-built-in) providers
        if let data = UserDefaults.standard.data(forKey: "customProviders"),
           let custom = try? JSONDecoder().decode([CLIProvider].self, from: data) {
            // Merge built-ins (always fresh) + user custom providers
            providers = CLIProvider.builtIns + custom.filter { !$0.isBuiltIn }
        } else {
            providers = CLIProvider.builtIns
        }

        // Load saved built-in templates (user may have edited them).
        //
        // The key is versioned: a v2 blob holds the retired Gemini CLI
        // template for what is now the Antigravity provider (same UUID), and
        // restoring it would show `gemini -p …` in Settings for a binary that
        // no longer runs. Bumping to v3 drops those once; the user's own
        // custom providers live under a separate key and are untouched.
        UserDefaults.standard.removeObject(forKey: "builtInProviders_v2")
        if let data = UserDefaults.standard.data(forKey: "builtInProviders_v3"),
           let saved = try? JSONDecoder().decode([CLIProvider].self, from: data) {
            for saved in saved {
                if let idx = providers.firstIndex(where: { $0.id == saved.id }) {
                    providers[idx].commandTemplate = saved.commandTemplate
                }
            }
        }

        // Load active provider
        if let uuidString = UserDefaults.standard.string(forKey: "activeProviderId"),
           let uuid = UUID(uuidString: uuidString) {
            activeProviderId = uuid
        } else {
            activeProviderId = CLIProvider.antigravity.id
        }
    }

    func saveProviders() {
        let custom = providers.filter { !$0.isBuiltIn }
        let builtIn = providers.filter { $0.isBuiltIn }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: "customProviders")
        }
        if let data = try? JSONEncoder().encode(builtIn) {
            UserDefaults.standard.set(data, forKey: "builtInProviders_v3")
        }
        UserDefaults.standard.set(activeProviderId.uuidString, forKey: "activeProviderId")
    }

    // MARK: - Load .env

    /// Called once, at launch. The engine reads `.env` again whenever it
    /// polls or starts the bot, but the fields below are filled only here, so
    /// nothing overwrites what the user is typing in Settings.
    func load() {
        engine.load()
        if let content = try? String(contentsOfFile: engine.envFilePath, encoding: .utf8) {
            show(engine.configuration, fileValues: NexusAgentEnvFile.values(in: content))
        } else {
            // No .env yet: try .env.example as a template
            let examplePath = (engine.botDirectory as NSString).appendingPathComponent(".env.example")
            if let example = try? String(contentsOfFile: examplePath, encoding: .utf8) {
                show(NexusAgentEnvFile.parse(example), fileValues: NexusAgentEnvFile.values(in: example))
            }
        }
    }

    /// Copies what the file says into the fields the views bind to.
    private func show(_ configuration: NexusAgentConfiguration, fileValues: [String: String]) {
        botToken = configuration.botToken
        allowedUserIds = configuration.allowedUserIDs
        workingDirectory = configuration.workingDirectory
        model = configuration.model
        effort = configuration.effort.rawValue
        // An approval mode line with nothing after the `=` shows this app's
        // default, as it always has here. The shared reading alone would show
        // "default" for it, which is how the bot itself takes an empty value.
        let written = fileValues[NexusAgentEnvFile.approvalModeKey] ?? fileValues["GEMINI_APPROVAL_MODE"]
        approvalMode = written == "" ? Self.defaultApprovalMode : configuration.approvalMode.rawValue
    }

    // MARK: - Save .env

    func save() {
        var configuration = NexusAgentConfiguration(
            botToken: botToken,
            allowedUserIDs: allowedUserIds,
            workingDirectory: workingDirectory,
            approvalMode: .parse(approvalMode),
            model: model,
            effort: .parse(effort))
        // Which program the bot runs is this app's own saved choice. It is
        // handed over on every save: the engine does not keep it, and forgets
        // it each time it reads the file.
        let provider = activeProvider
        configuration.botProvider = NexusAgentCLIProvider(
            id: provider.id, name: provider.name,
            commandTemplate: provider.commandTemplate, isBuiltIn: provider.isBuiltIn)
        // A save that fails leaves the reason with the engine, which the log
        // panel shows.
        engine.save(configuration)

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
