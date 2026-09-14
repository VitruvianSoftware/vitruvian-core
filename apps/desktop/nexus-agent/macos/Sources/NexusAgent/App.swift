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
        let config = ConfigManager()
        let updater = UpdateChecker()
        ConfigManager.shared = config
        self.botManager = bot
        self.configManager = config
        self.updateChecker = updater

        // Register global hotkey for Quick Prompt (⌘+Shift+G)
        QuickPromptWindowController.shared.registerHotkey()

        // Request notification permission for background generation alerts
        BackgroundNotificationManager.shared.requestPermission()

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
