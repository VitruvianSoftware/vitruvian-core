// Copyright (c) 2026 VitruvianSoftware

import SwiftUI
import HomeSpeakerCore

@MainActor
public class MenuBarViewModel: ObservableObject {
    @Published public var quickText: String = ""
    @Published public var isBroadcasting: Bool = false
    @Published public var broadcastFeedback: String?
    @Published public var feedbackIsError: Bool = false

    private var clearTask: Task<Void, Never>?

    public init() {}

    /// Shows a transient status line. Final states (success/failure) clear
    /// themselves after `autoClearAfter` so the banner never lingers; the
    /// in-progress "Broadcasting..." state passes nil and stays until replaced.
    public func setFeedback(_ text: String?, isError: Bool = false, autoClearAfter seconds: Double? = 3) {
        clearTask?.cancel()
        broadcastFeedback = text
        feedbackIsError = isError
        guard text != nil, let seconds else { return }
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.broadcastFeedback = nil
        }
    }
}

@MainActor
public struct MenuBarView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var monitorService: ChatMonitorService
    @ObservedObject var viewModel: MenuBarViewModel
    @FocusState private var quickTextFocused: Bool

    public init(
        configManager: ConfigManager,
        monitorService: ChatMonitorService,
        viewModel: MenuBarViewModel
    ) {
        self.configManager = configManager
        self.monitorService = monitorService
        self.viewModel = viewModel
    }

    public init() {
        self.configManager = .shared
        self.monitorService = .shared
        self.viewModel = MenuBarViewModel()
    }

    private var broadcastingBinding: Binding<Bool> {
        Binding(
            get: { configManager.config.enabled },
            set: { newValue in
                guard newValue != configManager.config.enabled else { return }
                configManager.toggleEnabled()
            }
        )
    }

    private var inQuietHours: Bool { configManager.config.isInQuietHours() }

    public var body: some View {
        VStack(spacing: 12) {
            // Header: single switch that both shows and controls the state.
            Toggle(isOn: broadcastingBinding) {
                HStack(spacing: 8) {
                    Image(systemName: configManager.config.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundStyle(configManager.config.enabled ? Color.accentColor : Color.secondary)
                    Text("Broadcasting")
                        .font(.headline)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("Broadcasting")
            .accessibilityHint("Turns spoken announcements on or off")

            if inQuietHours, let until = configManager.config.quietHoursEnd {
                Label("Quiet hours until \(until)", systemImage: "moon.zzz.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Quiet hours active until \(until)")
            }

            Divider()

            // Active Speaker Target (one entry per physical device)
            VStack(alignment: .leading, spacing: 4) {
                Text("Speaker")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Speaker", selection: Binding(
                    get: { configManager.config.defaultTarget },
                    set: { configManager.setTarget($0) }
                )) {
                    ForEach(configManager.config.uniqueTargets(), id: \.key) { entry in
                        Text(entry.device.displayLine).tag(entry.key)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Speaker target")
            }

            Divider()

            // Quick Announce
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick Announcement")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Type a message to speak aloud...", text: $viewModel.quickText)
                        .textFieldStyle(.roundedBorder)
                        .focused($quickTextFocused)
                        .onSubmit { speakText() }
                        .accessibilityLabel("Announcement text")

                    Button {
                        speakText()
                    } label: {
                        if viewModel.isBroadcasting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Speak")
                        }
                    }
                    .disabled(viewModel.quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isBroadcasting)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(viewModel.isBroadcasting ? "Broadcasting" : "Speak announcement")
                }

                if let feedback = viewModel.broadcastFeedback {
                    Text(feedback)
                        .font(.caption2)
                        .foregroundStyle(viewModel.feedbackIsError ? Color.red : Color.secondary)
                        .transition(.opacity)
                        .accessibilityLabel(feedback)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.broadcastFeedback)

            Divider()

            // Recent Broadcasts Feed
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Recent Broadcasts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let lastTime = monitorService.lastPollTime {
                        Text("Polled \(lastTime, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if configManager.recentBroadcasts.isEmpty {
                    Text("No recent announcements")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(configManager.recentBroadcasts.prefix(5)) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(item.source)
                                            .font(.caption2)
                                            .bold()
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(item.timestamp, style: .time)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text(item.text)
                                        .font(.caption)
                                        .lineLimit(2)
                                }
                                .padding(6)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(4)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            Divider()

            // Footer / Actions
            HStack {
                SettingsLink {
                    Label("Settings...", systemImage: "gear")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel("Open Settings")

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityLabel("Quit HomeSpeaker")
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            // The popover window is not yet key when onAppear fires; defer one
            // runloop hop so the focus request lands.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                quickTextFocused = true
            }
        }
    }

    private func speakText() {
        let msg = viewModel.quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !viewModel.isBroadcasting else { return }

        viewModel.isBroadcasting = true
        viewModel.setFeedback("Broadcasting...", autoClearAfter: nil)

        let config = configManager.config
        let targetKey = config.defaultTarget
        guard let target = config.targets[targetKey] else {
            viewModel.isBroadcasting = false
            viewModel.setFeedback("No speaker selected. Pick a target above.", isError: true)
            return
        }

        Task {
            do {
                // Quick Announce is a deliberate human action, so it overrides
                // quiet hours (force: true). Automated callers must not.
                let success = try await GoogleHomeClient.shared.broadcast(
                    text: msg,
                    target: target,
                    structureId: config.structureId,
                    config: config,
                    force: true
                )
                await MainActor.run {
                    if success {
                        configManager.addLogItem(BroadcastLogItem(
                            text: msg,
                            targetName: target.name,
                            source: "Quick Announce"
                        ))
                        viewModel.setFeedback("Sent to \(target.name).")
                        viewModel.quickText = ""
                    } else {
                        viewModel.setFeedback("Failed to broadcast: speaker unreachable.", isError: true)
                    }
                    viewModel.isBroadcasting = false
                }
            } catch {
                await MainActor.run {
                    viewModel.setFeedback("Error: \(error.localizedDescription)", isError: true)
                    viewModel.isBroadcasting = false
                }
            }
        }
    }
}
