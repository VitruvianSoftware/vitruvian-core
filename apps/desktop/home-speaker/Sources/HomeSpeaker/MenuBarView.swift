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
    @ObservedObject var door: AppDoor = AppSide.shared.door
    @ObservedObject var switcher: AppSwitch = AppSide.shared.switcher

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
            // Which HomeSpeaker (design 7.4): a line at the top while the
            // app asks or is quiet, not only the window, which is easy to miss.
            if door.plan.asks || door.plan.showsQuiet || door.plan.inTrash || switcher.step != nil {
                DoorCard(door: door, switcher: switcher, compact: true)
                Divider()
            }
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

            // Off, the switch is the menu: automatic broadcasting controls collapse,
            // while manual quick announcements and recent broadcasts remain accessible.
            if !configManager.config.enabled {
                Text(SpeakerConfig.broadcastingOffLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if inQuietHours, let until = configManager.config.quietHoursEnd {
                Label("Quiet hours until \(until)", systemImage: "moon.zzz.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Quiet hours active until \(until)")
            }

            // The settings file did not read: say so, since nothing changed
            // here will be saved until it does.
            if let problem = configManager.configProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Settings file problem: \(problem)")
            }

            if configManager.config.enabled {
                broadcastingControls
            }

            Divider()
            quickAnnounce
            Divider()
            recentBroadcasts
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            configManager.checkConnection()
            // `--say` and the Stop hook add to the history from their own
            // processes; show what they wrote since the menu last opened.
            configManager.reloadHistory()
            // The popover window is not yet key when onAppear fires; defer one
            // runloop hop so the focus request lands.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                quickTextFocused = true
            }
        }
    }

    // MARK: Sections

    /// Everything the Broadcasting switch governs: where to speak,
    /// the style, what may speak and background monitoring problems.
    @ViewBuilder
    private var broadcastingControls: some View {
        Divider()
        speakerPicker

        // The style only rewords coding agents' replies: with every agent
        // off there is nothing for it to word.
        if configManager.config.showsAnnouncementStyle {
            stylePicker
        }

        Divider()
        sourceSwitches
        if let problem = monitorService.lastError {
            monitorProblem(problem)
        }
    }

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
            // Where to speak, one click away. Always available when broadcasting is on.
            Text("Speak on")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Toggle("Home speakers", isOn: Binding(
                    get: { configManager.config.effectiveSpeakHome },
                    set: {
                        configManager.config.effectiveSpeakHome = $0
                        configManager.saveConfig()
                    }
                ))
                .accessibilityHint("Plays announcements on the Google Home speaker below")
                Toggle("This Mac", isOn: Binding(
                    get: { configManager.config.effectiveSpeakLocal },
                    set: {
                        configManager.config.effectiveSpeakLocal = $0
                        configManager.saveConfig()
                    }
                ))
                .accessibilityHint("Reads announcements aloud on this Mac")
                Toggle("Your phone", isOn: Binding(
                    get: { configManager.config.effectiveSpeakPhone },
                    set: {
                        configManager.config.effectiveSpeakPhone = $0
                        configManager.saveConfig()
                    }
                ))
                .accessibilityHint("Plays announcements on the paired Android phone")
            }
            .toggleStyle(.checkbox)
            .padding(.bottom, 4)

            // The speaker and its volume only while Home speakers speak:
            // off, they are hidden completely.
            if configManager.config.effectiveSpeakHome {
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
            outputsLine
                .padding(.top, 2)
        }
    }

    /// How coding agents' replies are worded, one click away; the model
    /// and a custom style are in Settings › General.
    private var stylePicker: some View {
        HStack {
            Text("Style")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Style", selection: Binding(
                get: { configManager.config.effectiveAnnouncementStyle },
                set: {
                    configManager.config.effectiveAnnouncementStyle = $0
                    configManager.saveConfig()
                }
            )) {
                ForEach(AnnouncementStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Announcement style")
            .accessibilityHint("How a coding agent's reply is worded before it is spoken")
        }
    }

    /// Where announcements go right now: "Speaking on Lake Office + This Mac".
    private var outputsLine: some View {
        let where_ = configManager.config.activeOutputsLabel
        let text = where_.isEmpty
            ? "Not speaking anywhere: all outputs are off"
            : "Speaking on \(where_)"
        return Label(text, systemImage: where_.isEmpty ? "speaker.slash" : "speaker.wave.2")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }

    /// What may speak, under Broadcasting (and only while it is on): each
    /// coding agent and each chat app, one click away, as the extension's
    /// island has them. A chat switch starts, stops or restarts the monitor
    /// to match.
    private var sourceSwitches: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Coding agents")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ForEach(CodingAgent.allCases, id: \.self) { agent in
                    Toggle(agent.displayName, isOn: Binding(
                        get: { configManager.config.announces(agent) },
                        set: { configManager.setAnnounces(agent, $0) }
                    ))
                    .accessibilityHint("Speaks what \(agent.displayName) sends")
                }
            }
            .toggleStyle(.checkbox)
            .padding(.bottom, 4)

            Text("Chat apps")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                chatSwitch("Slack", \.slackEnabled)
                chatSwitch("Google Chat", \.googleChatEnabled)
                chatSwitch("Beeper", \.beeperEnabled)
            }
            .toggleStyle(.checkbox)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chatSwitch(_ title: String, _ source: WritableKeyPath<ChatMonitorConfig, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { configManager.config.effectiveChatMonitor[keyPath: source] },
            set: { configManager.setChatSource(source, $0) }
        ))
        .accessibilityHint("Announces new \(title) messages")
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
                            Button { replay(item) } label: {
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isBroadcasting)
                            .help("Click to hear it again")
                            .accessibilityElement(children: .combine)
                            .accessibilityHint("Speaks this announcement again")
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
                if !targets.isEmpty {
                    configManager.applyDiscovery(structure: home, targets: targets)
                }
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
        guard !msg.isEmpty else { return }
        announce(msg, logAs: "Quick Announce") { viewModel.quickText = "" }
    }

    /// A Recent Broadcasts row, clicked: spoken again as Quick Announce
    /// speaks (the master switch holds, quiet hours do not), and not added
    /// to the history a second time.
    private func replay(_ item: BroadcastLogItem) {
        announce(item.text, logAs: nil) {}
    }

    /// Speaks `msg` as the person asked. When heard, adds it to the history
    /// under `logAs` (nil adds nothing) and runs `heard`.
    private func announce(_ msg: String, logAs source: String?, heard: @escaping () -> Void) {
        guard !viewModel.isBroadcasting else { return }

        viewModel.isBroadcasting = true
        viewModel.setFeedback("Broadcasting...", autoClearAfter: nil)

        let config = configManager.config
        if config.effectiveSpeakHome && !config.effectiveSpeakLocal && !config.effectiveSpeakPhone && config.defaultDevice == nil {
            viewModel.isBroadcasting = false
            viewModel.setFeedback("No speaker selected. Pick a target above.", isError: true)
            return
        }

        Task {
            // Quick Announce is a deliberate human action, so it overrides
            // quiet hours (force: true). Automated callers must not.
            let outcome = await Announcer.shared.announce(msg, config: config, force: true)
            let homeName = config.defaultDevice?.name ?? "Home speakers"
            switch outcome {
            case .disabled:
                viewModel.setFeedback("Broadcasting is switched off.", isError: true)
            case .quietHours(let until):
                viewModel.setFeedback("Quiet hours until \(until).", isError: true)
            case .noOutputs:
                viewModel.setFeedback("All outputs are off. Turn one on in Settings.", isError: true)
            case .nothingToSay:
                viewModel.setFeedback("Nothing to say after cleaning up the text.", isError: true)
            case .announced:
                if outcome.anySpoke {
                    if let source {
                        configManager.addLogItem(BroadcastLogItem(
                            text: msg,
                            targetName: outcome.spokenLabel(homeName: homeName),
                            source: source
                        ))
                    }
                    heard()
                }
                let failures = outcome.failureMessages
                if failures.isEmpty {
                    if outcome.anySpoke {
                        viewModel.setFeedback("Sent to \(outcome.spokenLabel(homeName: homeName)).")
                    } else if case .announced(_, _, .skipped(let why)) = outcome {
                        viewModel.setFeedback("Skipped on your phone (\(why)).")
                    }
                } else if case .announced(.failed(let why), .spoken, .off) = outcome {
                    // The same words `--say` prints, and so the tool shows.
                    viewModel.setFeedback(AnnounceOutcome.spokeLocallyHomeFailed(why), isError: true, autoClearAfter: 6)
                } else {
                    let heard = outcome.anySpoke ? "Sent to \(outcome.spokenLabel(homeName: homeName)). " : ""
                    viewModel.setFeedback(heard + "Error: " + failures.joined(separator: " "), isError: true, autoClearAfter: 6)
                }
            }
            viewModel.isBroadcasting = false
        }
    }
}
