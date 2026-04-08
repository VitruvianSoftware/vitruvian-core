import SwiftUI
import Foundation

// MARK: - CLI Provider Model

/// Represents a CLI backend that can handle prompts.
/// Use `{prompt}` and optionally `{model}` as placeholders in commandTemplate.
struct CLIProvider: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var commandTemplate: String
    var isBuiltIn: Bool

    static let gemini = CLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Gemini CLI",
        commandTemplate: "/opt/homebrew/bin/gemini -p \"{prompt}\" --output-format json --approval-mode yolo",
        isBuiltIn: true
    )

    static let ollama = CLIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Ollama (claude)",
        commandTemplate: "ollama launch claude --model {model} -- -p \"{prompt}\"",
        isBuiltIn: true
    )

    static let builtIns: [CLIProvider] = [.gemini, .ollama]
}

/// Reads and writes the bot's .env configuration file.
@MainActor
class ConfigManager: ObservableObject {
    /// Shared instance — set during app init for cross-component access.
    static var shared: ConfigManager!
    @Published var botToken: String = ""
    @Published var allowedUserIds: String = ""
    @Published var workingDirectory: String = ""
    @Published var approvalMode: String = "yolo"
    @Published var model: String = ""
    @Published var thinking: Bool = false
    @Published var autoStart: Bool = false

    // Bot directory (stored in UserDefaults so it survives .app bundle launches)
    @Published var botDirectoryOverride: String = ""

    // Hotkey config (stored in UserDefaults, not .env)
    @Published var hotkeyKey: String = "g"
    @Published var hotkeyModifiers: Int = 0  // NSEvent.ModifierFlags raw value

    // AI Backend providers (stored in UserDefaults)
    @Published var providers: [CLIProvider] = CLIProvider.builtIns
    @Published var activeProviderId: UUID = CLIProvider.gemini.id

    // Update preferences
    @Published var autoCheckUpdates: Bool = true

    /// The currently selected provider.
    var activeProvider: CLIProvider {
        providers.first { $0.id == activeProviderId } ?? CLIProvider.gemini
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

    let botDirectory: String
    private var envFilePath: String { "\(botDirectory)/.env" }

    init(botDirectory: String) {
        self.botDirectory = botDirectory

        // Load preferences from UserDefaults
        autoStart = UserDefaults.standard.bool(forKey: "autoStart")
        hotkeyKey = UserDefaults.standard.string(forKey: "hotkeyKey") ?? "g"
        hotkeyModifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        if hotkeyModifiers == 0 {
            // Default: ⌘+Shift
            hotkeyModifiers = Int(NSEvent.ModifierFlags([.command, .shift]).rawValue)
        }
        botDirectoryOverride = UserDefaults.standard.string(forKey: "botDirectory") ?? botDirectory

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

        // Load saved built-in templates (user may have edited them)
        if let data = UserDefaults.standard.data(forKey: "builtInProviders_v2"),
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
            activeProviderId = CLIProvider.gemini.id
        }
    }

    func saveProviders() {
        let custom = providers.filter { !$0.isBuiltIn }
        let builtIn = providers.filter { $0.isBuiltIn }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: "customProviders")
        }
        if let data = try? JSONEncoder().encode(builtIn) {
            UserDefaults.standard.set(data, forKey: "builtInProviders_v2")
        }
        UserDefaults.standard.set(activeProviderId.uuidString, forKey: "activeProviderId")
    }

    // MARK: - Load .env

    func load() {
        guard FileManager.default.fileExists(atPath: envFilePath),
              let content = try? String(contentsOfFile: envFilePath, encoding: .utf8) else {
            // Try .env.example as a template
            let examplePath = "\(botDirectory)/.env.example"
            if let example = try? String(contentsOfFile: examplePath, encoding: .utf8) {
                parseEnv(example)
            }
            return
        }
        parseEnv(content)
    }

    private func parseEnv(_ content: String) {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "TELEGRAM_BOT_TOKEN":
                botToken = value
            case "ALLOWED_USER_IDS":
                allowedUserIds = value
            case "GEMINI_WORKING_DIR":
                workingDirectory = value
            case "GEMINI_APPROVAL_MODE":
                approvalMode = value
            case "GEMINI_MODEL":
                model = value
            case "GEMINI_THINKING":
                thinking = value.lowercased() == "true"
            default:
                break
            }
        }
    }

    // MARK: - Save .env

    func save() {
        let provider = activeProvider
        let isGemini = provider.id == CLIProvider.gemini.id
        let cliProvider = isGemini ? "gemini" : "custom"
        let cliTemplate = isGemini ? "" : provider.commandTemplate

        let content = """
        # Telegram Bot Token (get from @BotFather on Telegram)
        TELEGRAM_BOT_TOKEN=\(botToken)

        # Comma-separated list of allowed Telegram user IDs
        ALLOWED_USER_IDS=\(allowedUserIds)

        # Working directory for Gemini CLI
        GEMINI_WORKING_DIR=\(workingDirectory)

        # Max execution time per prompt in milliseconds
        GEMINI_TIMEOUT_MS=300000

        # Gemini CLI approval mode: default, auto_edit, yolo
        GEMINI_APPROVAL_MODE=\(approvalMode)

        # Gemini CLI model (optional)
        GEMINI_MODEL=\(model)

        # Enable thinking mode (deep reasoning with gemini-2.5-flash)
        GEMINI_THINKING=\(thinking ? "true" : "false")

        # AI backend provider: gemini or custom
        CLI_PROVIDER=\(cliProvider)

        # Command template for custom provider ({prompt} and {model} are substituted at runtime)
        CLI_COMMAND_TEMPLATE=\(cliTemplate)
        """

        do {
            try content.write(toFile: envFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save .env: \(error)")
        }

        // Save all UserDefaults preferences
        UserDefaults.standard.set(autoStart, forKey: "autoStart")
        UserDefaults.standard.set(autoCheckUpdates, forKey: "autoCheckUpdates")
        UserDefaults.standard.set(hotkeyKey, forKey: "hotkeyKey")
        UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers")
        if !botDirectoryOverride.isEmpty {
            UserDefaults.standard.set(botDirectoryOverride, forKey: "botDirectory")
        }
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
