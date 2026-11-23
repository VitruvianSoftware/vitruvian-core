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

#if canImport(SentryLite)
import SentryLite
#endif
import AppKit
import SwiftUI
import VitruvianCodeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var botManager: BotManager?
    private var isTerminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating, let botManager = Self.botManager else {
            return .terminateNow
        }
        isTerminating = true
        Task { @MainActor in
            await botManager.stopForQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// The program's entry. `--run-automation <id>` (a LaunchAgent that a schedule
/// exported starts the app this way) runs one task with no window and exits;
/// anything else is the menu bar app.
@main
@MainActor
enum VitruvianCodeLauncher {
    static func main() {
        let arguments = ProcessInfo.processInfo.arguments
        switch VitruvianCodeAutomationLaunch.parse(arguments: arguments) {
        case .none:
            VitruvianCodeApp.main()
        case .invalid(let reason):
            FileHandle.standardError.write(Data("VitruvianCode: \(reason)\n".utf8))
            exit(2)
        case .run(let id):
            HeadlessAutomation.start(taskID: id, arguments: arguments)
        }
    }
}

struct VitruvianCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
#if canImport(SentryLite)
        SentryLite.start(
            dsn: "https://259b457f48de7e350f152674cb029dda@sentry-ingest.ipv1337.dev/8",
            release: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
            tags: ["app": "vitruvian-code", "platform": "macos"]
        )
#endif
    }

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

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let stateDirectoryOverride: String?
        do {
            stateDirectoryOverride = try VitruvianCodeSupport.stateDirectoryOverride(arguments: arguments)
        } catch {
            // A bad `--state-dir` stops the launch, before anything is read or written.
            FileHandle.standardError.write(Data("VitruvianCode: \(error)\n".utf8))
            exit(2)
        }
        if let stateDirectoryOverride {
            // An isolated test copy keeps its bot folder, state folder, logs
            // and settings apart from the real app's.
            AppPreferences.useSuite(forStateDirectory: stateDirectoryOverride)
            let paths = VitruvianCodeSupport.statePaths(
                home: NSHomeDirectory(),
                stateDirectoryOverride: stateDirectoryOverride
            )
            for directory in [paths.botDirectory, paths.stateDirectory, paths.logsDirectory] {
                try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            }
        }
        let bot = BotManager(stateDirectoryOverride: stateDirectoryOverride)
        // The bot manager owns the shared engine; settings are read and saved through it.
        let config = ConfigManager(engine: bot.engine, host: bot.host)
        let updater = UpdateChecker()
        self.botManager = bot
        self.configManager = config
        self.updateChecker = updater
        AppDelegate.botManager = bot

        // The chat window shows the engine's chat, and tells the engine
        // whether it is on screen.
        QuickPromptWindowController.shared.configure(engine: bot.engine)

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
