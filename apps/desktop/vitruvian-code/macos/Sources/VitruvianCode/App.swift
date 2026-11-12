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
import VitruvianCodeCore

/// Carries a value to another thread that the caller promises not to touch
/// meanwhile.
private final class Handoff<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

@main
struct VitruvianCodeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            if let loaded = appState.loaded {
                StatusView(botManager: loaded.botManager, configManager: loaded.configManager,
                           updateChecker: loaded.updateChecker)
            } else {
                // Only while a person who used Nexus Agent has their folders
                // copied across (the first launch, and only if they are big).
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Moving your Nexus Agent data to Vitruvian Code…")
                        .font(.caption)
                }
                .frame(width: 280)
                .padding(12)
            }
        } label: {
            Image(systemName: appState.loaded?.botManager.isRunning == true ? "paperplane.fill" : "paperplane")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Shared app state that owns both managers with proper lifecycle.
@MainActor
class AppState: ObservableObject {
    struct Loaded {
        let botManager: BotManager
        let configManager: ConfigManager
        let updateChecker: UpdateChecker
    }

    /// The managers, once the person's things from Nexus Agent are in place.
    /// Nil only while that is still being done.
    @Published private(set) var loaded: Loaded?

    private let migration: VitruvianCodeLegacyMigration?

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
            self.migration = nil
            let paths = VitruvianCodeSupport.statePaths(
                home: NSHomeDirectory(),
                stateDirectoryOverride: stateDirectoryOverride
            )
            for directory in [paths.botDirectory, paths.stateDirectory, paths.logsDirectory] {
                try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            }
            start(migrated: nil, stateDirectoryOverride: stateDirectoryOverride)
            return
        }

        // Before anything reads the settings or the folders: a person who
        // used Nexus Agent finds their things here, not an empty app.
        let executable = Bundle.main.executablePath ?? "/Applications/Vitruvian Code.app/Contents/MacOS/VitruvianCode"
        let migration = VitruvianCodeLegacyMigration(environment: .live(executablePath: executable))
        self.migration = migration

        // The settings come in at once: they are small, and the managers read
        // them as they start. The folders can be big (a bot folder holds its
        // node_modules), so with any to copy, that is done off the main
        // thread, the menu bar item is there meanwhile, and the managers start
        // when it is finished: they read the bot's folder as they start too.
        let prelude = migration.begin()
        if prelude.alreadyDone {
            start(migrated: migration.finish(prelude), stateDirectoryOverride: nil)
        } else {
            let work = Handoff((migration, prelude))
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let outcome = Handoff(work.value.0.finish(work.value.1))
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.start(migrated: outcome.value, stateDirectoryOverride: nil)
                    }
                }
            }
        }
    }

    private func start(migrated: VitruvianCodeLegacyMigration.Outcome?, stateDirectoryOverride: String?) {
        let migration = self.migration
        let bot = BotManager(stateDirectoryOverride: stateDirectoryOverride)
        // The bot manager owns the shared engine; settings are read and saved through it.
        let config = ConfigManager(engine: bot.engine, host: bot.host)
        let updater = UpdateChecker()
        self.loaded = Loaded(botManager: bot, configManager: config, updateChecker: updater)

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

        // Tell the person what moved over and what macOS will ask again, once;
        // or what did not move, which the next launch tries again.
        if let migrated, let migration, migrated.needsNotice {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                openLegacyMigrationWindow(outcome: migrated) {
                    if migrated.completed { migration.markPermissionsExplained() }
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
