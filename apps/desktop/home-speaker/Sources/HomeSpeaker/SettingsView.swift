// Copyright (c) 2026 VitruvianSoftware

import SwiftUI
import HomeSpeakerCore

@MainActor
public class SettingsViewModel: ObservableObject {
    @Published public var claudeHookInstalled: Bool = false
    @Published public var launchAgentInstalled: Bool = false
    @Published public var statusMessage: String?

    public init() {}
}

@MainActor
public struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var monitorService: ChatMonitorService
    @ObservedObject var viewModel: SettingsViewModel

    public init(
        configManager: ConfigManager,
        monitorService: ChatMonitorService,
        viewModel: SettingsViewModel
    ) {
        self.configManager = configManager
        self.monitorService = monitorService
        self.viewModel = viewModel
    }

    public init() {
        self.configManager = .shared
        self.monitorService = .shared
        self.viewModel = SettingsViewModel()
    }

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            speakersTab
                .tabItem {
                    Label("Speakers", systemImage: "hifispeaker.2")
                }

            monitorTab
                .tabItem {
                    Label("Chat & Slack", systemImage: "bubble.left.and.bubble.right")
                }

            agentsTab
                .tabItem {
                    Label("AI Agents", systemImage: "terminal")
                }
        }
        .frame(width: 520, height: 400)
        .onAppear {
            refreshIntegrationStatus()
            configManager.checkConnection()
        }
    }

    // MARK: - Bindings

    /// Bridges a "HH:mm" config string to a DatePicker. Falls back to
    /// `fallback` when the stored text is missing or malformed.
    private func timeBinding(
        _ keyPath: WritableKeyPath<SpeakerConfig, String?>,
        fallback: String
    ) -> Binding<Date> {
        Binding(
            get: {
                let text = configManager.config[keyPath: keyPath] ?? fallback
                let minutes = SpeakerConfig.minutesSinceMidnight(text)
                    ?? SpeakerConfig.minutesSinceMidnight(fallback) ?? 0
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                configManager.config[keyPath: keyPath] = String(
                    format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
                configManager.saveConfig()
            }
        )
    }

    private func monitorBinding<T: Equatable>(_ keyPath: WritableKeyPath<ChatMonitorConfig, T>) -> Binding<T> {
        Binding(
            get: { configManager.config.effectiveChatMonitor[keyPath: keyPath] },
            set: { newValue in
                guard configManager.config.effectiveChatMonitor[keyPath: keyPath] != newValue else { return }
                configManager.config.effectiveChatMonitor[keyPath: keyPath] = newValue
                configManager.saveConfig()
                monitorService.restartIfRunning()
            }
        )
    }

    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section("Broadcast Controls") {
                Toggle("Enable Voice Broadcasting", isOn: $configManager.config.enabled)
                    .onChange(of: configManager.config.enabled) { _, _ in
                        configManager.saveConfig()
                    }
                    .accessibilityHint("Turns all spoken announcements on or off")

                LabeledContent("Google Home Account") {
                    HStack(spacing: 8) {
                        if configManager.isConnectedToGoogle {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Google Home account connected")
                        } else {
                            Label("Not Connected", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Google Home account not connected")
                        }
                        Button("Re-check") { configManager.checkConnection() }
                            .controlSize(.small)
                            .accessibilityLabel("Re-check Google Home connection")
                    }
                }

                if !configManager.isConnectedToGoogle {
                    Text("Sign in to Google Home once through the Antigravity Google Home connector; this app reuses that login from ~/.gemini/antigravity/mcp_oauth_tokens.json.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Enable Quiet Hours", isOn: Binding(
                    get: { configManager.config.quietHoursEnabled ?? false },
                    set: {
                        configManager.config.quietHoursEnabled = $0
                        configManager.saveConfig()
                    }
                ))
                .accessibilityHint("Pauses automated announcements during the window below")

                DatePicker(
                    "Start",
                    selection: timeBinding(\.quietHoursStart, fallback: "22:00"),
                    displayedComponents: .hourAndMinute
                )
                .disabled(!(configManager.config.quietHoursEnabled ?? false))
                .accessibilityLabel("Quiet hours start time")

                DatePicker(
                    "End",
                    selection: timeBinding(\.quietHoursEnd, fallback: "07:00"),
                    displayedComponents: .hourAndMinute
                )
                .disabled(!(configManager.config.quietHoursEnabled ?? false))
                .accessibilityLabel("Quiet hours end time")
            } header: {
                Text("Quiet Hours")
            } footer: {
                Text("Announcements sent through this app are held during quiet hours. Quick Announcements you type yourself still play.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Speakers Tab
    private var speakersTab: some View {
        Form {
            Section {
                ForEach(Array(configManager.config.targets.keys.sorted()), id: \.self) { key in
                    if let device = configManager.config.targets[key] {
                        speakerRow(key: key, device: device)
                    }
                }
            } header: {
                Text("Configured Speakers & Displays")
            } footer: {
                Text("Aliases that point at the same device are listed here individually but appear once in the menu bar picker.")
            }
        }
        .formStyle(.grouped)
    }

    private func speakerRow(key: String, device: SpeakerDevice) -> some View {
        let isDefault = key == configManager.config.defaultTarget
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body)
                    .bold()
                HStack(spacing: 6) {
                    Text("Alias: \(key)")
                    if let room = device.room {
                        Text("•")
                        Text("Room: \(room)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if isDefault {
                Text("Default")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
                    .accessibilityLabel("Current default speaker")
            }
            Button("Set Default") {
                configManager.setTarget(key)
            }
            .disabled(isDefault)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Set \(device.name) as default speaker")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Monitor Tab
    private var monitorTab: some View {
        let monitor = configManager.config.effectiveChatMonitor
        return Form {
            Section("Background Monitoring") {
                LabeledContent("Daemon Status") {
                    HStack(spacing: 8) {
                        if monitorService.isRunning {
                            Label("Running", systemImage: "bolt.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Monitor daemon running")
                            Button("Stop") { monitorService.stop() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("Stop monitor daemon")
                        } else {
                            Label("Stopped", systemImage: "moon.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Monitor daemon stopped")
                            Button("Start") { monitorService.start() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(monitor.daemonArguments == nil)
                                .accessibilityLabel("Start monitor daemon")
                        }
                    }
                }

                if let error = monitorService.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Daemon error: \(error)")
                }
            }

            Section {
                Toggle("Monitor Google Chat", isOn: monitorBinding(\.googleChatEnabled))
                    .accessibilityHint("Announces new Google Chat messages aloud")
                Toggle("Monitor Slack Channels & DMs", isOn: monitorBinding(\.slackEnabled))
                    .accessibilityHint("Announces new Slack messages aloud")

                Stepper(
                    value: monitorBinding(\.pollIntervalSeconds),
                    in: ChatMonitorConfig.minPollInterval...ChatMonitorConfig.maxPollInterval,
                    step: 5
                ) {
                    LabeledContent("Poll Interval", value: "\(monitor.clampedPollInterval) s")
                }
                .accessibilityLabel("Poll interval")
                .accessibilityValue("\(monitor.clampedPollInterval) seconds")
            } header: {
                Text("Sources")
            } footer: {
                Text(monitor.daemonArguments == nil
                     ? "Both sources are off, so the daemon will not run."
                     : "Changes restart the daemon automatically when it is running.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Coding Agents Tab
    private var agentsTab: some View {
        Form {
            Section("Claude Code Integration") {
                LabeledContent {
                    if viewModel.claudeHookInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Claude Code stop hook installed")
                    } else {
                        Button("Install Hook") {
                            do {
                                try AgentIntegration.shared.installClaudeCodeHook()
                                viewModel.claudeHookInstalled = true
                                viewModel.statusMessage = "Claude Code Stop Hook installed successfully."
                            } catch {
                                viewModel.statusMessage = "Error: \(error.localizedDescription)"
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Install Claude Code stop hook")
                    }
                } label: {
                    Text("Lifecycle Stop Hook")
                    Text("Automatically broadcasts responses aloud after every prompt turn.")
                }
            }

            Section("macOS Background Service (LaunchAgent)") {
                LabeledContent {
                    if viewModel.launchAgentInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Launch agent installed")
                    } else {
                        Button("Install Service") {
                            do {
                                try AgentIntegration.shared.installLaunchAgent()
                                viewModel.launchAgentInstalled = true
                                viewModel.statusMessage = "LaunchAgent installed to ~/Library/LaunchAgents/."
                            } catch {
                                viewModel.statusMessage = "Error: \(error.localizedDescription)"
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel("Install launch agent service")
                    }
                } label: {
                    Text("Auto-Start at Login")
                    Text("Keeps the speaker broadcast daemon alive 24/7 independent of IDEs.")
                }
            }

            if let msg = viewModel.statusMessage {
                Section {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.hasPrefix("Error") ? Color.orange : Color.secondary)
                        .accessibilityLabel(msg)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func refreshIntegrationStatus() {
        viewModel.claudeHookInstalled = AgentIntegration.shared.isClaudeCodeHookInstalled()
        viewModel.launchAgentInstalled = AgentIntegration.shared.isLaunchAgentInstalled()
    }
}
