import SwiftUI

@main
struct GeminiBotBarApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            StatusView(botManager: appState.botManager, configManager: appState.configManager)
        } label: {
            Image(systemName: appState.botManager.isRunning ? "paperplane.fill" : "paperplane")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Shared app state that owns both managers with proper lifecycle.
@MainActor
class AppState: ObservableObject {
    let botManager: BotManager
    let configManager: ConfigManager

    init() {
        let bot = BotManager()
        let config = ConfigManager(botDirectory: bot.botDirectory)
        ConfigManager.shared = config
        self.botManager = bot
        self.configManager = config

        // Register global hotkey for Quick Prompt (⌘+Shift+G)
        QuickPromptWindowController.shared.registerHotkey()

        // Auto-start if configured
        if config.autoStart && config.isConfigured {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if !bot.isRunning {
                    bot.start()
                }
            }
        }
    }
}
