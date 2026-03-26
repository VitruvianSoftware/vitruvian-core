import SwiftUI
import Foundation

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

        load()
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
        """

        do {
            try content.write(toFile: envFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save .env: \(error)")
        }

        // Save all UserDefaults preferences
        UserDefaults.standard.set(autoStart, forKey: "autoStart")
        UserDefaults.standard.set(hotkeyKey, forKey: "hotkeyKey")
        UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers")
        if !botDirectoryOverride.isEmpty {
            UserDefaults.standard.set(botDirectoryOverride, forKey: "botDirectory")
        }
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
