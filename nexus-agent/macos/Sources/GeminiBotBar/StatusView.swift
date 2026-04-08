import SwiftUI

/// The menu bar dropdown content.
struct StatusView: View {
    @ObservedObject var botManager: BotManager
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var updateChecker: UpdateChecker
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Status Header ──
            HStack(spacing: 8) {
                Circle()
                    .fill(botManager.isRunning ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(botManager.isRunning ? "Running" : "Stopped")
                    .font(.headline)
                Spacer()
                if let pid = botManager.pid {
                    Text("PID \(pid)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if !configManager.isConfigured {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Bot token not configured")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            // ── Update Banner ──
            if updateChecker.updateAvailable && !updateChecker.dismissed {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update available: v\(updateChecker.latestVersion)")
                            .font(.caption)
                            .fontWeight(.medium)
                        if updateChecker.isDownloading {
                            ProgressView(value: updateChecker.downloadProgress)
                                .progressViewStyle(.linear)
                        } else if updateChecker.isInstalling {
                            Text("Installing…")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if !updateChecker.isDownloading && !updateChecker.isInstalling {
                        Button("Update") {
                            Task { await updateChecker.downloadAndInstall() }
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        Button(action: { updateChecker.dismissed = true }) {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.08))
            }

            Divider()

            // ── Controls ──
            Group {
                if botManager.isRunning {
                    Button(action: { botManager.stop() }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    Button(action: { botManager.restart() }) {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                } else {
                    Button(action: { botManager.start() }) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .disabled(!configManager.isConfigured)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            Divider()

            // ── Info ──
            if !configManager.workingDirectory.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(abbreviatePath(configManager.workingDirectory))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            // ── Recent Logs ──
            if !botManager.lastLogLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Logs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(botManager.lastLogLines.suffix(5), id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(maxHeight: 60)
                }
                .padding(.vertical, 4)

                Divider()
            }

            // ── Actions ──
            Button(action: { botManager.openLogs() }) {
                Label("Open Logs", systemImage: "doc.text")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            Button(action: {
                QuickPromptWindowController.shared.toggle()
            }) {
                Label("Quick Prompt (⌘⇧G)", systemImage: "sparkles")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            Button(action: {
                showSettings = true
                openSettingsWindow(configManager: configManager, botManager: botManager, updateChecker: updateChecker)
            }) {
                Label("Settings…", systemImage: "gearshape")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)

            Divider()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit", systemImage: "power")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .frame(width: 280)
        .padding(.vertical, 4)
    }

    private func abbreviatePath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

// MARK: - Settings Window

/// Floating panel that accepts keyboard input — standard NSWindow at .floating level
/// silently refuses to become key, which blocks all text field interaction.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Holds strong references to managers for the settings window context.
private var _settingsWindow: NSWindow?
private var _settingsConfigManager: ConfigManager?
private var _settingsBotManager: BotManager?

func openSettingsWindow(configManager: ConfigManager, botManager: BotManager, updateChecker: UpdateChecker) {
    // Reuse existing window if open
    if let existing = _settingsWindow, existing.isVisible {
        existing.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    // Keep strong references so they aren't deallocated
    _settingsConfigManager = configManager
    _settingsBotManager = botManager

    let settingsView = SettingsView(configManager: configManager, botManager: botManager, updateChecker: updateChecker)
    let hostingView = NSHostingView(rootView: settingsView)

    let window = KeyablePanel(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    window.title = "Gemini Bot Settings"
    window.titlebarAppearsTransparent = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.isFloatingPanel = true
    window.becomesKeyOnlyIfNeeded = false

    // Frosted glass effect
    let visualEffect = NSVisualEffectView()
    visualEffect.material = .hudWindow
    visualEffect.blendingMode = .behindWindow
    visualEffect.state = .active
    visualEffect.autoresizingMask = [.width, .height]

    hostingView.autoresizingMask = [.width, .height]
    hostingView.frame = visualEffect.bounds

    visualEffect.addSubview(hostingView)
    window.contentView = visualEffect

    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    window.level = .floating
    NSApp.activate(ignoringOtherApps: true)

    _settingsWindow = window
}
