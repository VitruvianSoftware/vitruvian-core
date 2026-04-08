import SwiftUI

@main
struct NexusAgentApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            StatusView(botManager: appState.botManager, configManager: appState.configManager,
                       updateChecker: appState.updateChecker)
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
    let updateChecker: UpdateChecker

    init() {
        let bot = BotManager()
        let config = ConfigManager(botDirectory: bot.botDirectory)
        let updater = UpdateChecker()
        ConfigManager.shared = config
        self.botManager = bot
        self.configManager = config
        self.updateChecker = updater

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

        // Check for updates on launch (if enabled)
        if config.autoCheckUpdates {
            Task {
                // Slight delay so the app fully initializes first
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await updater.checkForUpdates()
            }
        }
    }
}
