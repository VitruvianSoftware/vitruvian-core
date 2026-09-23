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
import HomeSpeakerCore

@MainActor
public class MenuBarViewModel: ObservableObject {
    /// One instance for the app; see SettingsViewModel.shared for why.
    public static let shared = MenuBarViewModel()

    @Published public var quickText: String = ""
    @Published public var isBroadcasting: Bool = false
    @Published public var broadcastFeedback: String?
    @Published public var feedbackIsError: Bool = false
    @Published public var isBusy: Bool = false

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
        self.viewModel = .shared
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
                    Image(systemName: configManager.config.enabled ? "dot.radiowaves.left.and.right" : "speaker.slash.fill")
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

            if !configManager.isConnectedToGoogle {
                setupStep(
                    icon: "person.crop.circle.badge.exclamationmark",
                    title: "Sign in to Google Home",
                    detail: "HomeSpeaker needs permission to talk to your speakers.",
                    button: "Sign in…") { signIn() }
            } else if !configManager.config.hasSpeakers {
                setupStep(
                    icon: "hifispeaker.2",
                    title: "Find your speakers",
                    detail: "Signed in\(configManager.googleEmail.map { " as \($0)" } ?? ""). Load the speakers and displays in your home.",
                    button: "Find speakers") { discover() }
            } else {
                speakerPicker
                Divider()
                quickAnnounce
            }

            if let problem = monitorService.lastError {
                monitorProblem(problem)
            }
            Divider()
            recentBroadcasts
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            configManager.checkConnection()
            // The popover window is not yet key when onAppear fires; defer one
            // runloop hop so the focus request lands.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                quickTextFocused = true
            }
        }
    }

    // MARK: Sections

    private func setupStep(icon: String, title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(button, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.isBusy)
                if viewModel.isBusy { ProgressView().controlSize(.small) }
            }
            if let feedback = viewModel.broadcastFeedback {
                Text(feedback)
                    .font(.caption2)
                    .foregroundStyle(viewModel.feedbackIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speakerPicker: some View {
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

            if let target = configManager.config.defaultDevice {
                SpeakerVolumeControl(target: target, structureId: configManager.config.structureId)
                    .padding(.top, 2)
            }
        }
    }

    private var quickAnnounce: some View {
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
    }

    private var recentBroadcasts: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent Broadcasts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if monitorService.isRunning, let lastTime = monitorService.lastPollTime {
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
    }

    /// A chat source the user switched on but that is not running.
    ///
    /// Without this the only sign was inside Settings, and the menu bar kept
    /// showing "Polled 1:42 PM" because the OTHER source was fine: Slack was
    /// on, had no token, and was skipped for days while every visible signal
    /// said the monitor was healthy.
    private func monitorProblem(_ problem: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(problem)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            SettingsLink { Text("Fix") }
                .controlSize(.small)
                .accessibilityLabel("Open Settings to fix: \(problem)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
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

    // MARK: Actions

    private func signIn() {
        viewModel.isBusy = true
        viewModel.setFeedback("Finish signing in in your browser…", autoClearAfter: nil)
        Task {
            do {
                _ = try await GoogleAuth.shared.signIn(openBrowser: { url in
                    Task { @MainActor in NSWorkspace.shared.open(url) }
                })
                configManager.checkConnection()
                viewModel.setFeedback(nil)
                discover()
            } catch {
                viewModel.setFeedback(error.localizedDescription, isError: true, autoClearAfter: 8)
                viewModel.isBusy = false
            }
        }
    }

    private func discover() {
        viewModel.isBusy = true
        viewModel.setFeedback("Looking for speakers…", autoClearAfter: nil)
        Task {
            do {
                let homes = try await GoogleHomeClient.shared.listHomes()
                guard let home = homes.first(where: { $0.id == configManager.config.structureId }) ?? homes.first else {
                    throw BroadcastError.mcp("No home found on this Google account.")
                }
                let targets = try await GoogleHomeClient.shared.discoverBroadcastTargets(structureId: home.id)
                configManager.applyDiscovery(structure: home, targets: targets)
                viewModel.setFeedback(targets.isEmpty ? "No speakers or displays found in \(home.name)." : nil,
                                      isError: targets.isEmpty, autoClearAfter: 8)
            } catch {
                viewModel.setFeedback(error.localizedDescription, isError: true, autoClearAfter: 8)
            }
            viewModel.isBusy = false
        }
    }

    private func speakText() {
        let msg = viewModel.quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !viewModel.isBroadcasting else { return }

        viewModel.isBroadcasting = true
        viewModel.setFeedback("Broadcasting...", autoClearAfter: nil)

        let config = configManager.config
        guard let target = config.defaultDevice else {
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
                if success {
                    configManager.addLogItem(BroadcastLogItem(
                        text: msg,
                        targetName: target.name,
                        source: "Quick Announce"
                    ))
                    viewModel.setFeedback("Sent to \(target.name).")
                    viewModel.quickText = ""
                } else {
                    viewModel.setFeedback("Nothing to say after cleaning up the text.", isError: true)
                }
            } catch {
                viewModel.setFeedback("Error: \(error.localizedDescription)", isError: true, autoClearAfter: 6)
            }
            viewModel.isBroadcasting = false
        }
    }
}
