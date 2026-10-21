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
public class SettingsViewModel: ObservableObject {
    /// One instance for the app. The Settings scene re-creates its view on
    /// every App re-render; a per-view model would reset to defaults and
    /// show "Install Hook" over an installed hook.
    public static let shared = SettingsViewModel()

    @Published public var agents: [AgentIntegration.AgentStatus] = []
    @Published public var legacyLaunchAgentInstalled: Bool = false
    @Published public var launchAtLogin: Bool = false
    @Published public var statusMessage: String?
    @Published public var isBusy: Bool = false
    @Published public var homes: [HomeStructure] = []
    @Published public var selectedHomeId: String = ""
    @Published public var slackToken: String = ""
    @Published public var showReplaceSlackToken: Bool = false
    @Published public var beeperToken: String = ""
    @Published public var showReplaceBeeperToken: Bool = false
    @Published public var geminiApiKey: String = ""
    @Published public var showReplaceGeminiKey: Bool = false
    @Published public var oauthClientId: String = ""
    @Published public var oauthClientSecret: String = ""
    @Published public var hasBundledOAuthClient: Bool = false
    /// Which Settings pane is showing. Lives here rather than in an @State so
    /// the General pane can jump to Google Cloud setup, and because the
    /// Command Line Tools toolchain has no SwiftUI macro plugin for @State.
    @Published public var selectedTab: Tab = .general
    /// Installed English voices for the "This Mac" picker, best first.
    @Published public var macVoices: [LocalVoice] = []
    @Published public var isPreviewingVoice = false

    public enum Tab: Hashable { case general, speakers, monitor, agents, googleCloud }

    public init() {}

    func refresh(secrets: SecretStore = .shared) {
        agents = CodingAgent.allCases.map { AgentIntegration.shared.status(of: $0) }
        legacyLaunchAgentInstalled = AgentIntegration.shared.isLegacyLaunchAgentInstalled()
        launchAtLogin = LoginItem.isEnabled
        let s = secrets.load()
        slackToken = s.slackToken ?? ""
        showReplaceSlackToken = false
        beeperToken = s.beeperToken ?? ""
        showReplaceBeeperToken = false
        geminiApiKey = s.geminiApiKey ?? ""
        showReplaceGeminiKey = false
        oauthClientId = s.oauthClientIdOverride ?? ""
        oauthClientSecret = s.oauthClientSecretOverride ?? ""
        hasBundledOAuthClient = HomeSpeakerProfile.current.shippedClient != nil
        macVoices = LocalSpeaker.shared.englishVoices()
    }
}

@MainActor
public struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var monitorService: ChatMonitorService
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var mediaPause: MediaPauseCoordinator = .shared
    @ObservedObject var volumeRestore: VolumeRestoreCoordinator = .shared
    @ObservedObject var door: AppDoor = AppSide.shared.door
    @ObservedObject var switcher: AppSwitch = AppSide.shared.switcher

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
        self.viewModel = .shared
    }

    public var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsViewModel.Tab.general)
            speakersTab
                .tabItem { Label("Speakers", systemImage: "hifispeaker.2") }
                .tag(SettingsViewModel.Tab.speakers)
            monitorTab
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .tag(SettingsViewModel.Tab.monitor)
            agentsTab
                .tabItem { Label("AI Agents", systemImage: "terminal") }
                .tag(SettingsViewModel.Tab.agents)
            googleCloudTab
                .tabItem { Label("Google Cloud", systemImage: "cloud") }
                .tag(SettingsViewModel.Tab.googleCloud)
        }
        .frame(width: 540, height: 440)
        .onAppear {
            viewModel.refresh()
            configManager.checkConnection()
            viewModel.selectedHomeId = configManager.config.structureId
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

    /// A Beeper network's switch: on reads it, off mutes it. Saved only:
    /// unlike `monitorBinding`, the monitor is not restarted, because each
    /// poll reads the mutes fresh and a restart would drop what arrived
    /// meanwhile (`ConfigManager.setBeeperNetwork`).
    private func beeperNetworkBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !configManager.config.effectiveChatMonitor.beeperMutedNetworks.contains(key) },
            set: { configManager.setBeeperNetwork(key, reading: $0) }
        )
    }

    /// The Beeper networks to show a switch for, as the extension's pages
    /// show them: what the running monitor last listed, and the saved
    /// mutes, so the mutes show while it is stopped too.
    private var beeperNetworkList: BeeperNetworkList {
        BeeperNetworkList(
            listed: monitorService.isRunning ? monitorService.beeperNetworkStates : nil,
            muted: configManager.config.effectiveChatMonitor.beeperMutedNetworks)
    }

    /// A chat source's switch: saved, and the monitor brought along
    /// (`ConfigManager.setChatSource`), so switching one on from all off
    /// starts it, as the menu bar's switch does.
    private func sourceBinding(_ source: WritableKeyPath<ChatMonitorConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { configManager.config.effectiveChatMonitor[keyPath: source] },
            set: { configManager.setChatSource(source, $0) }
        )
    }

    private func status(_ text: String, isError: Bool = false) {
        viewModel.statusMessage = (isError ? "Error: " : "") + text
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            if let problem = configManager.configProblem {
                Section("Settings File") {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            WhichHomeSpeakerSection(door: door, switcher: switcher)
            Section("Google Home Account") {
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        if configManager.isConnectedToGoogle {
                            Label(configManager.googleEmail ?? "Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Google Home account connected")
                            Button("Sign Out") { signOut() }
                                .controlSize(.small)
                        } else {
                            Label("Not signed in", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Google Home account not connected")
                            Button("Sign In…") { signIn() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(viewModel.isBusy)
                        }
                    }
                }
                if !configManager.isConnectedToGoogle {
                    if OAuthClient.resolve(secrets: SecretStore.shared.load(), shipped: HomeSpeakerProfile.current.shippedClient) == nil {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Sign In needs a Google Cloud project of your own (Home API enabled) — a few minutes, once.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Set up…") { viewModel.selectedTab = .googleCloud }
                                .controlSize(.small)
                        }
                    }
                    if FileManager.default.fileExists(atPath: SecretStore.antigravityTokensURL.path) {
                        Button("Import Antigravity login") { importAntigravity() }
                            .controlSize(.small)
                        Text("Reuses the Google Home sign-in from the Antigravity connector on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Broadcast Controls") {
                Toggle("Enable Voice Broadcasting", isOn: $configManager.config.enabled)
                    .onChange(of: configManager.config.enabled) { _, _ in
                        configManager.saveConfig()
                    }
                    .accessibilityHint("Turns all spoken announcements on or off")

                Toggle("Open HomeSpeaker at Login", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { on in
                        do {
                            try LoginItem.setEnabled(on)
                            viewModel.launchAtLogin = LoginItem.isEnabled
                            if on && LoginItem.requiresApproval {
                                status(DoorWords.approveLoginItem)
                            }
                        } catch {
                            status(error.localizedDescription, isError: true)
                        }
                    }
                ))
                .accessibilityHint("Starts the menu bar app when you log in")

                Picker("Speak", selection: Binding(
                    get: { configManager.config.effectiveSpeechLength },
                    set: {
                        configManager.config.effectiveSpeechLength = $0
                        configManager.saveConfig()
                    }
                )) {
                    ForEach(SpeechLength.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .accessibilityHint("How much of each reply is read out")

                // The style rewords coding agents' replies only, and the set
                // volume is the Home speaker's: each while it can matter.
                if configManager.config.showsAnnouncementStyle {
                    styleControls
                }

                if configManager.config.showsHomeControls {
                    Toggle("Announce at a set volume", isOn: Binding(
                        get: { configManager.config.effectiveAnnounceVolumeEnabled },
                        set: {
                            configManager.config.effectiveAnnounceVolumeEnabled = $0
                            configManager.saveConfig()
                        }
                    ))
                    .accessibilityHint("Sets the speaker to one volume for each announcement, then puts it back")

                    if configManager.config.effectiveAnnounceVolumeEnabled {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(configManager.config.effectiveAnnounceVolume) },
                                    set: { configManager.config.effectiveAnnounceVolume = Int($0) }
                                ),
                                in: 0...100, step: 5
                            ) { editing in
                                if !editing { configManager.saveConfig() }
                            }
                            .accessibilityLabel("Announcement volume")
                            Text("\(configManager.config.effectiveAnnounceVolume)%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 40, alignment: .trailing)
                        }
                        Text(volumeRestore.lastReport ?? "The speaker goes back to its own volume when the announcement ends -- unless someone changes it in the meantime. Needs HomeSpeaker running to put it back.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Toggle("Pause media while announcing", isOn: Binding(
                    get: { configManager.config.effectivePauseMedia },
                    set: {
                        configManager.config.effectivePauseMedia = $0
                        configManager.saveConfig()
                    }
                ))
                .accessibilityHint("Pauses YouTube, Music, Spotify or QuickTime on this Mac while the speaker talks, then resumes it")

                if configManager.config.effectivePauseMedia {
                    Stepper(
                        "Resume \(Int(configManager.config.effectivePauseMediaExtraSeconds)) s after it finishes",
                        value: Binding(
                            get: { configManager.config.effectivePauseMediaExtraSeconds },
                            set: {
                                configManager.config.effectivePauseMediaExtraSeconds = $0
                                configManager.saveConfig()
                            }
                        ),
                        in: 0...10, step: 1)
                    .font(.caption)

                    HStack(alignment: .firstTextBaseline) {
                        Text(mediaPause.lastReport ?? "Works with Chrome, Brave, Edge, Arc, Vivaldi, Safari, Music, Spotify and QuickTime. Browsers need Allow JavaScript from Apple Events turned on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        // Pauses what is playing now for three seconds. Also
                        // where macOS asks, once, to let HomeSpeaker control
                        // each app -- better here than mid-announcement.
                        Button(mediaPause.isHolding ? "Paused…" : "Test") {
                            Task { await mediaPause.pause(for: 3) }
                        }
                        .controlSize(.small)
                        .disabled(mediaPause.isHolding)
                    }
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

                if configManager.config.quietHoursEnabled ?? false {
                    DatePicker("Start", selection: timeBinding(\.quietHoursStart, fallback: "22:00"), displayedComponents: .hourAndMinute)
                        .accessibilityLabel("Quiet hours start time")

                    DatePicker("End", selection: timeBinding(\.quietHoursEnd, fallback: "07:00"), displayedComponents: .hourAndMinute)
                        .accessibilityLabel("Quiet hours end time")
                }
            } header: {
                Text("Quiet Hours")
            } footer: {
                Text("Automated announcements are held during quiet hours. Quick Announcements you type yourself still play.")
            }

            statusSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Speakers Tab

    private var speakersTab: some View {
        Form {
            outputsSection

            if configManager.config.effectiveSpeakHome {
                Section {
                    if !viewModel.homes.isEmpty {
                        Picker("Home", selection: $viewModel.selectedHomeId) {
                            ForEach(viewModel.homes) { Text($0.name).tag($0.id) }
                        }
                    } else if let name = configManager.config.structureName {
                        LabeledContent("Home", value: name)
                    }
                    HStack {
                        Button(configManager.config.hasSpeakers ? "Refresh from Google Home" : "Find Speakers") { discover() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!configManager.isConnectedToGoogle || viewModel.isBusy)
                        if viewModel.isBusy { ProgressView().controlSize(.small) }
                    }
                } header: {
                    Text("Discovery")
                } footer: {
                    Text(configManager.isConnectedToGoogle
                         ? "Lists every speaker and display in your home that can play announcements."
                         : "Sign in under General first.")
                }

                Section {
                    if configManager.config.targets.isEmpty {
                        Text("No speakers yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(configManager.config.targets.keys.sorted()), id: \.self) { key in
                        if let device = configManager.config.targets[key] {
                            speakerRow(key: key, device: device)
                        }
                    }
                } header: {
                    Text("Speakers & Displays")
                } footer: {
                    Text("Aliases that point at the same device appear once in the menu bar picker.")
                }
            }

            statusSection
        }
        .formStyle(.grouped)
    }

    /// How a coding agent's reply is worded, and by which model: the same
    /// controls as the extension's Settings › General.
    @ViewBuilder
    private var styleControls: some View {
        Picker("Style", selection: Binding(
            get: { configManager.config.effectiveAnnouncementStyle },
            set: {
                configManager.config.effectiveAnnouncementStyle = $0
                configManager.saveConfig()
            }
        )) {
            ForEach(AnnouncementStyle.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .accessibilityHint("How a coding agent's reply is worded before it is spoken")

        if configManager.config.effectiveAnnouncementStyle == .custom {
            TextField("Custom style", text: Binding(
                get: { configManager.config.customStylePrompt ?? "" },
                set: {
                    configManager.config.customStylePrompt = $0
                    configManager.saveConfig()
                }
            ), prompt: Text("e.g. One short sentence, like a ship captain"))
            .accessibilityHint("The instruction the model follows")
        }

        if configManager.config.effectiveAnnouncementStyle != .verbatim {
            Picker("Style with", selection: Binding(
                get: { configManager.config.effectiveStyleModel },
                set: {
                    configManager.config.effectiveStyleModel = $0
                    configManager.saveConfig()
                }
            )) {
                ForEach(StyleModel.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .accessibilityHint("Which model rewords the reply")
            // The key, here unless Speakers › This Mac shows it.
            if configManager.config.effectiveStyleModel == .gemini && !geminiSpeaksHere {
                geminiKeyControls
            }
            Text("Apple's model runs on this Mac (macOS 26 and Apple Intelligence). Gemini sends the reply to Google with your Gemini API key. If one fails, the next is used: Gemini, then Apple, then the reply as written. Chat messages and what you type are always read as written.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Gemini speaks on the Home speakers, this Mac or this phone: Speakers ›
    /// Where to speak shows its key.
    private var geminiSpeaksHere: Bool {
        configManager.config.geminiSpeaks
    }

    /// The Gemini API key, as a token is shown: the field, Save Key, Clear.
    @ViewBuilder
    private var geminiKeyControls: some View {
        let hasSavedKey = !(SecretStore.shared.load().geminiApiKey ?? "").isEmpty
        if hasSavedKey && !viewModel.showReplaceGeminiKey {
            HStack {
                Label("Gemini API key saved", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
                Button("Replace Key…") { viewModel.showReplaceGeminiKey = true }
                    .controlSize(.small)
                Button("Clear Gemini Key") {
                    viewModel.geminiApiKey = ""
                    saveGeminiKey()
                }
                .controlSize(.small)
            }
        } else {
            SecureField("Gemini API key", text: $viewModel.geminiApiKey, prompt: Text("Paste the key, then Save Key"))
                .onSubmit {
                    saveGeminiKey()
                    viewModel.showReplaceGeminiKey = false
                }
            HStack {
                Button("Save Key") {
                    saveGeminiKey()
                    viewModel.showReplaceGeminiKey = false
                }
                .controlSize(.small)
                if hasSavedKey {
                    Button("Cancel") { viewModel.showReplaceGeminiKey = false }
                        .controlSize(.small)
                    Button("Clear Gemini Key") {
                        viewModel.geminiApiKey = ""
                        saveGeminiKey()
                        viewModel.showReplaceGeminiKey = false
                    }
                    .controlSize(.small)
                }
            }
        }
        Text("Make a key at aistudio.google.com › Get API key.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func saveGeminiKey() {
        do {
            let key = viewModel.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try SecretStore.shared.update { $0.geminiApiKey = key.isEmpty ? nil : key }
            status(key.isEmpty ? "Gemini API key cleared." : "Gemini API key saved.")
        } catch { status(error.localizedDescription, isError: true) }
    }

    /// Where announcements play: the Google Home speaker, this Mac, this phone, or any combination.
    private var outputsSection: some View {
        Section {
            Toggle("Home speakers", isOn: Binding(
                get: { configManager.config.effectiveSpeakHome },
                set: {
                    configManager.config.effectiveSpeakHome = $0
                    configManager.saveConfig()
                }
            ))
            .accessibilityHint("Plays announcements on the default Google Home speaker")

            if configManager.config.effectiveSpeakHome {
                // Casting needs the Gemini engine: offered once it is picked.
                if configManager.config.showsHomeCastVoice {
                    Toggle("Use selected voice on Home speakers (Cast)", isOn: Binding(
                        get: { configManager.config.effectiveHomeCastVoice },
                        set: {
                            configManager.config.effectiveHomeCastVoice = $0
                            configManager.saveConfig()
                        }
                    ))
                    .accessibilityHint("Casts the Gemini voice to your Home speakers over this Wi-Fi network. When the speaker can't be found, is playing something else, or the cast fails, Google Assistant Broadcast says it instead.")
                    Text("Casts the Gemini voice to your Home speakers over this Wi-Fi network. When the speaker can't be found, is playing something else, or the cast fails, Google Assistant Broadcast says it instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !configManager.config.targets.isEmpty {
                    Picker("Default speaker", selection: Binding(
                        get: { configManager.config.defaultTarget },
                        set: { configManager.setTarget($0) }
                    )) {
                        ForEach(configManager.config.uniqueTargets(), id: \.key) { entry in
                            Text(entry.device.displayLine).tag(entry.key)
                        }
                    }
                    .accessibilityLabel("Default speaker")
                }
            }

            Toggle("This Mac", isOn: Binding(
                get: { configManager.config.effectiveSpeakLocal },
                set: {
                    configManager.config.effectiveSpeakLocal = $0
                    configManager.saveConfig()
                }
            ))
            .accessibilityHint("Also reads announcements aloud on this Mac")

            Toggle("Your phone", isOn: Binding(
                get: { configManager.config.effectiveSpeakPhone },
                set: {
                    configManager.config.effectiveSpeakPhone = $0
                    configManager.saveConfig()
                }
            ))
            .accessibilityHint("Plays announcements on the paired Android phone")

            if configManager.config.showsVoiceEngine {
                Picker("Voice engine", selection: Binding(
                    get: { configManager.config.effectiveLocalEngine },
                    set: {
                        configManager.config.effectiveLocalEngine = $0
                        configManager.saveConfig()
                    }
                )) {
                    ForEach(LocalVoiceEngine.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .accessibilityHint("What speaks on this Mac, your phone, and the Home speakers when they use the selected voice")

                if configManager.config.showsGeminiVoice {
                    Picker("Gemini voice", selection: Binding(
                        get: { configManager.config.effectiveGeminiVoice },
                        set: {
                            configManager.config.effectiveGeminiVoice = $0
                            configManager.saveConfig()
                        }
                    )) {
                        if GeminiVoice(rawValue: configManager.config.effectiveGeminiVoice) == nil {
                            Text(configManager.config.effectiveGeminiVoice).tag(configManager.config.effectiveGeminiVoice)
                        }
                        ForEach(GeminiVoice.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                    .accessibilityHint("The Gemini voice this Mac, your phone and the Home speakers (Cast) speak in")
                    geminiKeyControls
                }
            }

            if configManager.config.effectiveSpeakLocal {
                HStack {
                    Picker(configManager.config.effectiveLocalEngine == .gemini ? "Fallback Mac voice" : "Voice", selection: Binding(
                        get: { configManager.config.effectiveLocalVoice },
                        set: {
                            configManager.config.effectiveLocalVoice = $0
                            configManager.saveConfig()
                        }
                    )) {
                        // The saved voice stays selectable even when it is not
                        // installed, so the picker never silently changes it.
                        if !viewModel.macVoices.contains(where: { $0.id == configManager.config.effectiveLocalVoice }) {
                            Text(missingVoiceLabel).tag(configManager.config.effectiveLocalVoice)
                        }
                        ForEach(viewModel.macVoices) { Text($0.pickerLabel).tag($0.id) }
                    }
                    .accessibilityHint("The voice this Mac speaks in")
                    Button(viewModel.isPreviewingVoice ? "Speaking…" : "Preview") { previewVoice() }
                        .controlSize(.small)
                        .disabled(viewModel.isPreviewingVoice)
                        .accessibilityHint("Speaks a short sample in this voice")
                }
            }

            if configManager.config.effectiveSpeakPhone {
                Toggle("Pause phone media while announcing", isOn: Binding(
                    get: { configManager.config.effectivePhonePauseMedia },
                    set: {
                        configManager.config.effectivePhonePauseMedia = $0
                        configManager.saveConfig()
                    }
                ))
                .accessibilityHint("Ducks or pauses media playing on the phone while the announcement plays")

                Toggle("Only announce on phone when headphones are connected", isOn: Binding(
                    get: { configManager.config.effectivePhoneHeadphonesOnly },
                    set: {
                        configManager.config.effectivePhoneHeadphonesOnly = $0
                        configManager.saveConfig()
                    }
                ))
                .accessibilityHint("Skips the phone announcement when no Bluetooth or wired headphones are connected to the phone")
            }
        } header: {
            Text("Where to speak")
        } footer: {
            Text(outputsFooter)
        }
    }

    private var missingVoiceLabel: String {
        let id = configManager.config.effectiveLocalVoice
        let name = id.split(separator: ".").last.map(String.init) ?? id
        let fallback = LocalSpeaker.chooseVoice(requested: id, from: viewModel.macVoices).voice?.name ?? "the system voice"
        return "\(name) (not installed; using \(fallback))"
    }

    private var outputsFooter: String {
        let c = configManager.config
        if !c.effectiveSpeakHome && !c.effectiveSpeakLocal && !c.effectiveSpeakPhone {
            return "All outputs are off, so nothing is spoken anywhere."
        }
        var lines: [String] = []
        if (c.effectiveSpeakLocal || c.effectiveSpeakPhone) && c.effectiveLocalEngine == .gemini {
            lines.append("Gemini TTS sends what this Mac says to Google to be spoken; with no key, or when Gemini fails, the Mac voice speaks instead.")
        }
        if let cast = SpeakerConfig.homeCastFooter(c) { lines.append(cast) }
        if c.effectiveSpeakLocal {
            lines.append("This Mac speaks at its own volume. More voices: System Settings › Accessibility › Read & Speak › System voice › ⓘ › Voice, then download an \"(Enhanced)\" voice.")
        }
        if c.effectiveSpeakPhone {
            lines.append(c.effectiveLocalEngine == .gemini
                ? "Your phone plays the Gemini voice (or Android's on-device voice when Gemini is unavailable) via Vitruvian Remote."
                : "Your phone speaks with Android's on-device voice via Vitruvian Remote.")
        }
        if c.effectiveSpeakHome && c.effectiveSpeakLocal {
            lines.append("Both speak at the same time. Quiet hours and pausing media cover both.")
        }
        return lines.joined(separator: " ")
    }

    private func previewVoice() {
        let voice = configManager.config.effectiveLocalVoice
        viewModel.isPreviewingVoice = true
        Task {
            do {
                try await LocalSpeaker.shared.speak("This is how announcements will sound on this Mac.", voiceID: voice)
            } catch {
                status(error.localizedDescription, isError: true)
            }
            viewModel.isPreviewingVoice = false
        }
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
            Button("Set Default") { configManager.setTarget(key) }
                .disabled(isDefault)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Set \(device.name) as default speaker")
            Button { configManager.removeTarget(key) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove \(device.name)")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Monitor Tab

    private var monitorTab: some View {
        let monitor = configManager.config.effectiveChatMonitor
        return Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        if monitorService.isRunning {
                            Label("Running", systemImage: "bolt.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Monitor running")
                            Button("Stop") { monitorService.stop() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        } else {
                            Label("Stopped", systemImage: "moon.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Monitor stopped")
                            // Through the gate: a quiet app never reads chat.
                            Button("Start") { door.monitor.start() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!monitor.anySourceEnabled || !door.plan.runs)
                        }
                    }
                }
                if let error = monitorService.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Monitor error: \(error)")
                }
            } header: {
                Text("Background Monitoring")
            } footer: {
                Text("Off by default. When on, new messages are read aloud on the default speaker. " + configManager.config.chatMessagesSentTo)
            }

            Section("Slack") {
                Toggle("Announce Slack messages", isOn: sourceBinding(\.slackEnabled))
                    .accessibilityHint("Announces new Slack messages aloud")
                if monitor.slackEnabled {
                    let hasSlackToken = !(SecretStore.shared.load().slackToken ?? "").isEmpty
                    if hasSlackToken && !viewModel.showReplaceSlackToken {
                        HStack {
                            Label("Slack token saved", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                            Button("Replace Token…") { viewModel.showReplaceSlackToken = true }
                                .controlSize(.small)
                            if let user = monitorService.slackUser {
                                Text("Signed in as \(user)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        SecureField("User token (xoxp-…)", text: $viewModel.slackToken)
                            .onSubmit {
                                saveSlackToken()
                                viewModel.showReplaceSlackToken = false
                            }
                        HStack {
                            Button("Save Token") {
                                saveSlackToken()
                                viewModel.showReplaceSlackToken = false
                            }
                            .controlSize(.small)
                            if hasSlackToken {
                                Button("Cancel") { viewModel.showReplaceSlackToken = false }
                                    .controlSize(.small)
                            }
                            if let user = monitorService.slackUser {
                                Text("Signed in as \(user)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("Create a Slack app with the `search:read` user scope and paste its user token. The token is stored only on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Announce Google Chat messages", isOn: sourceBinding(\.googleChatEnabled))
                    .accessibilityHint("Announces new Google Chat messages aloud")
                if monitor.googleChatEnabled {
                    Picker("Read Google Chat via", selection: monitorBinding(\.googleChatSource)) {
                        Text("Automatic").tag(ChatMonitorConfig.GoogleChatSource.auto)
                        Text("Google API (this app's login)").tag(ChatMonitorConfig.GoogleChatSource.api)
                        Text("gws command-line tool").tag(ChatMonitorConfig.GoogleChatSource.gws)
                    }
                    if monitor.googleChatSource != .gws {
                        HStack {
                            if hasChatScopes {
                                Label("Chat access granted", systemImage: "checkmark.circle.fill")
                                    .font(.caption).foregroundStyle(.green)
                                Button("Disconnect") { Task { await signOutOfChat() } }
                                    .controlSize(.small)
                            } else {
                                Text("Google grants Chat access separately from Home — a second sign-in.")
                                    .font(.caption).foregroundStyle(.orange)
                                Button("Grant…") { signIn(purpose: .chat) }
                                    .controlSize(.small)
                                    .disabled(viewModel.isBusy)
                            }
                        }
                    }
                    if monitor.googleChatSource != .api {
                        if let path = GwsChatClient.locate() {
                            Label("gws found at \(path)", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                            TextField("gws account (optional, e.g. you@gmail.com)", text: monitorBinding(\.gwsAccount))
                        } else {
                            Text("gws is not installed. Install the Google Workspace CLI and run `gws auth login` to use it.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let via = monitorService.googleChatVia, monitorService.isRunning {
                        Text("Currently reading via \(via == "api" ? "the Google API" : "gws").")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Google Chat")
            } footer: {
                if monitor.googleChatEnabled {
                    Text("Automatic uses the API when its permission is granted, otherwise gws if installed. “Skip messages I sent” needs your Google user id, which only an API sign-in provides.")
                }
            }

            Section {
                Toggle("Announce Beeper messages", isOn: sourceBinding(\.beeperEnabled))
                    .accessibilityHint("Announces new messages from Beeper Desktop aloud")
                if monitor.beeperEnabled {
                    Picker("Announce", selection: monitorBinding(\.beeperAnnounce)) {
                        ForEach(ChatMonitorConfig.BeeperAnnounce.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    beeperNetworkSwitches
                    let hasBeeperToken = !(SecretStore.shared.load().beeperToken ?? "").isEmpty
                    if hasBeeperToken && !viewModel.showReplaceBeeperToken {
                        HStack {
                            Label("Beeper token saved", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                            Button("Replace Token…") { viewModel.showReplaceBeeperToken = true }
                                .controlSize(.small)
                            if monitorService.isRunning, let line = ChatMonitorService.beeperReadingLine(
                                networks: monitorService.beeperNetworks, skipped: monitorService.beeperSkippedNetworks) {
                                Text(line).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        SecureField("Access token", text: $viewModel.beeperToken)
                            .onSubmit {
                                saveBeeperToken()
                                viewModel.showReplaceBeeperToken = false
                            }
                        HStack {
                            Button("Save Token") {
                                saveBeeperToken()
                                viewModel.showReplaceBeeperToken = false
                            }
                            .controlSize(.small)
                            if hasBeeperToken {
                                Button("Cancel") { viewModel.showReplaceBeeperToken = false }
                                    .controlSize(.small)
                            }
                            if monitorService.isRunning, let line = ChatMonitorService.beeperReadingLine(
                                networks: monitorService.beeperNetworks, skipped: monitorService.beeperSkippedNetworks) {
                                Text(line).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Beeper")
            } footer: {
                if monitor.beeperEnabled {
                    Text("In Beeper Desktop: Settings › Integrations, turn on the Desktop API, then + next to Approved connections. Beeper Desktop must be running; HomeSpeaker only talks to it on this Mac. Slack and Google Chat chats in Beeper are skipped while their own switches above are on.")
                }
            }

            Section("Options") {
                Toggle("Skip messages I sent", isOn: monitorBinding(\.muteOwnMessages))
                Stepper(
                    value: monitorBinding(\.pollIntervalSeconds),
                    in: ChatMonitorConfig.minPollInterval...ChatMonitorConfig.maxPollInterval,
                    step: 5
                ) {
                    LabeledContent("Poll Interval", value: "\(monitor.clampedPollInterval) s")
                }
                .accessibilityLabel("Poll interval")
                .accessibilityValue("\(monitor.clampedPollInterval) seconds")
            }

            statusSection
        }
        .formStyle(.grouped)
    }

    /// A switch for each Beeper network, under a "Networks" caption: on
    /// reads it, off mutes it. A network HomeSpeaker reads itself is shown
    /// off and greyed. Before the monitor has read Beeper, the saved mutes
    /// and where the others will show.
    @ViewBuilder
    private var beeperNetworkSwitches: some View {
        let list = beeperNetworkList
        if list.shows(beeperEnabled: configManager.config.effectiveChatMonitor.beeperEnabled) {
            Text("Networks").font(.caption).foregroundStyle(.secondary)
            ForEach(list.rows, id: \.key) { row in
                if row.state == .skipped {
                    Toggle("\(row.name) · Read directly", isOn: .constant(false))
                        .disabled(true)
                        .accessibilityHint("Read by HomeSpeaker's own reader while its switch is on")
                } else {
                    Toggle(row.name, isOn: beeperNetworkBinding(row.key))
                        .accessibilityHint("Off mutes this Beeper network")
                }
            }
            if !list.isListed {
                Text(BeeperNetworkList.othersLater).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var hasChatScopes: Bool { SecretStore.shared.load().hasChatAccess }

    // MARK: - AI Agents Tab

    private var agentsTab: some View {
        Form {
            // Each agent's own switch, under Enable Voice Broadcasting: the
            // menu bar and the extension have the same pair.
            Section {
                ForEach(CodingAgent.allCases, id: \.self) { agent in
                    Toggle("Announce \(agent.displayName) replies", isOn: Binding(
                        get: { configManager.config.announces(agent) },
                        set: { configManager.setAnnounces(agent, $0) }
                    ))
                }
            } header: {
                Text("Announcements")
            } footer: {
                Text("Off, the hook or instruction stays as it is and nothing is spoken.")
            }

            ForEach(viewModel.agents, id: \.agent) { st in
                Section {
                    switch st.section {
                    case .notInstalled:
                        LabeledContent {
                            Text("Not installed on this Mac").foregroundStyle(.secondary)
                        } label: {
                            Text("\(st.agent.displayName) \(st.agent.hookKind)")
                            Text("Nothing to do here.")
                        }
                    case .instructionDriven:
                        LabeledContent {
                            if st.configuredByInstruction {
                                Label("Configured", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button("Add Instruction") { addInstruction(st.agent) }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                            }
                        } label: {
                            Text("\(st.agent.displayName) announcements")
                            Text(st.configuredByInstruction
                                 ? "\(st.agent.instructionFileName) tells \(st.agent.displayName) to speak each reply through the app's speaker settings."
                                 : "Adds one line to \(st.agent.instructionFileName) asking \(st.agent.displayName) to speak each reply.")
                        }
                    case .hook:
                        // Claude Code is the agent with a rival hook file
                        // (the 1.x skill's hooks.json); the warning shows
                        // only where there is one.
                        if let warning = st.speaksTwiceWarning {
                            HStack(alignment: .firstTextBaseline) {
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Turn it off") { disableRival(st.agent) }
                                    .controlSize(.small)
                            }
                        }
                        let quiet = door.plan.role.isQuiet
                        LabeledContent {
                            switch st.hook {
                            case .installed:
                                HStack(spacing: 8) {
                                    Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                                    Button("Remove") { removeHook(st.agent) }.controlSize(.small)
                                }
                            case .stale where quiet:
                                Label("Installed on the HomeSpeaker extension", systemImage: "checkmark.circle")
                                    .foregroundStyle(.secondary)
                            case .stale:
                                HStack(spacing: 8) {
                                    Label("Needs update", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                                    Button("Update Hook") { installHook(st.agent) }.buttonStyle(.borderedProminent).controlSize(.small)
                                }
                            case .notInstalled where quiet:
                                Label("Not installed", systemImage: "circle").foregroundStyle(.secondary)
                            case .notInstalled:
                                Button("Install Hook") { installHook(st.agent) }.buttonStyle(.borderedProminent).controlSize(.small)
                            }
                        } label: {
                            Text("\(st.agent.displayName) \(st.agent.hookKind)")
                            Text("Speaks a one-sentence summary of each reply when a turn finishes.")
                        }
                        Text(AgentIntegration.shared.hookCommand(for: st.agent))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if st.configuredByInstruction {
                            Label(st.hook == .installed
                                  ? "Your \(st.agent.instructionFileName) also tells \(st.agent.displayName) to broadcast on its own. With the hook installed, remove that instruction to avoid hearing replies twice."
                                  : "Already announcing: your \(st.agent.instructionFileName) tells \(st.agent.displayName) to broadcast on its own. The hook is optional — it makes that deterministic and needs no model cooperation.",
                                  systemImage: st.hook == .installed ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(st.hook == .installed ? .orange : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } header: {
                    Text(st.agent.displayName)
                } footer: {
                    Text(st.agent.hookFootnote)
                }
            }

            if viewModel.legacyLaunchAgentInstalled {
                Section("Cleanup") {
                    LabeledContent {
                        Button("Remove") {
                            do {
                                try AgentIntegration.shared.removeLegacyLaunchAgent()
                                viewModel.legacyLaunchAgentInstalled = false
                                status("Legacy launch agent removed.")
                            } catch { status(error.localizedDescription, isError: true) }
                        }
                        .controlSize(.small)
                    } label: {
                        Text("Legacy chat-monitor launch agent")
                        Text("Installed by HomeSpeaker 1.x. Chat monitoring now runs inside the app.")
                    }
                }
            }

            statusSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Google Cloud Tab

    /// Bring-your-own Google Cloud project. This is the normal path: Google
    /// requires every app that touches a home to identify itself, and most
    /// users would rather point the app at their own project than trust a
    /// shared one. A bundled client, when a release ships one, is the
    /// exception and is only mentioned when present.
    private var googleCloudTab: some View {
        Form {
            Section {
                step(1, "Create or pick a project", "console.cloud.google.com — use the Google account that owns your home.")
                step(2, "Enable the Home API", "APIs & Services › Library › “Home API”. Also enable the Google Chat API if you want chat announcements.")
                step(3, "Configure the consent screen, then Publish", "Google Auth Platform › Audience › External. Leave it on Testing and Google expires your login every 7 days.")
                step(4, "Create an OAuth client", "Desktop app: nothing else to enter. Web application: add every callback below to Authorised redirect URIs.")
                Text(GoogleAuth.allRedirectURIs.joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Open Google Cloud Console") {
                    NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!)
                }
                .controlSize(.small)
            } header: {
                Text("Your Google Cloud project")
            } footer: {
                Text(viewModel.hasBundledOAuthClient
                     ? "This build also ships with a shared OAuth client. Fill in your own below to use your project instead; yours always wins."
                     : "One-time setup. Your client ID and secret never leave this Mac.")
            }

            Section {
                TextField("Client ID", text: $viewModel.oauthClientId)
                SecureField("Client secret", text: $viewModel.oauthClientSecret)
                Button("Save") { saveOAuthClient() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.oauthClientId.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Step 5 · Paste the client here")
            }

            Section("Files") {
                LabeledContent("Settings", value: ConfigManager.defaultConfigURL().path)
                LabeledContent("Secrets", value: SecretStore.defaultURL().path)
                LabeledContent("Version", value: HomeSpeakerVersion.current)
            }
            .font(.caption)

            statusSection
        }
        .formStyle(.grouped)
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)")
                .font(.caption.weight(.semibold))
                .frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var statusSection: some View {
        Group {
            if let msg = viewModel.statusMessage {
                Section {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.hasPrefix("Error") ? Color.orange : Color.secondary)
                        .accessibilityLabel(msg)
                }
            }
        }
    }

    // MARK: - Actions

    private func signIn(purpose: GoogleAuth.Purpose = .home) {
        viewModel.isBusy = true
        status("Finish signing in in your browser…")
        Task {
            do {
                let creds = try await GoogleAuth.shared.signIn(purpose: purpose, openBrowser: { url in
                    Task { @MainActor in NSWorkspace.shared.open(url) }
                })
                configManager.checkConnection()
                status(purpose == .chat
                       ? "Google Chat access granted\(creds.email.map { " for \($0)" } ?? "")."
                       : "Signed in\(configManager.googleEmail.map { " as \($0)" } ?? "").")
                monitorService.restartIfRunning()
                if purpose == .home, !configManager.config.hasSpeakers { discover() }
            } catch {
                status(error.localizedDescription, isError: true)
            }
            viewModel.isBusy = false
        }
    }

    /// Through the one sign-out rule (`HomeSpeakerEngine.signOut`): a login
    /// the extension shares is removed here only, never revoked at Google,
    /// so signing out of a quiet app never signs the extension out.
    private func signOut() {
        Task {
            let out = await door.signOut(engine: .app, chatOnly: false)
            configManager.checkConnection()
            monitorService.stop()
            if out.exitCode == 0 { status("Signed out.") } else { status(out.stderr.joined(separator: " "), isError: true) }
        }
    }

    private func signOutOfChat() async {
        let out = await door.signOut(engine: .app, chatOnly: true)
        if out.exitCode != 0 { status(out.stderr.joined(separator: " "), isError: true) }
        monitorService.restartIfRunning()
        viewModel.objectWillChange.send()
    }

    private func importAntigravity() {
        do {
            if try SecretStore.shared.importFromAntigravity() {
                configManager.checkConnection()
                status("Imported the Antigravity Google Home login.")
                if !configManager.config.hasSpeakers { discover() }
            } else {
                status("No Google Home login found in the Antigravity token file.", isError: true)
            }
        } catch { status(error.localizedDescription, isError: true) }
    }

    private func discover() {
        viewModel.isBusy = true
        Task {
            do {
                let homes = try await GoogleHomeClient.shared.listHomes()
                viewModel.homes = homes
                let wanted = viewModel.selectedHomeId.isEmpty ? configManager.config.structureId : viewModel.selectedHomeId
                guard let home = homes.first(where: { $0.id == wanted }) ?? homes.first else {
                    throw BroadcastError.mcp("No home found on this Google account.")
                }
                viewModel.selectedHomeId = home.id
                let targets = try await GoogleHomeClient.shared.discoverBroadcastTargets(structureId: home.id)
                configManager.applyDiscovery(structure: home, targets: targets)
                status(targets.isEmpty ? "No speakers or displays found in \(home.name)." : "Found \(targets.count) target(s) in \(home.name).", isError: targets.isEmpty)
            } catch {
                status(error.localizedDescription, isError: true)
            }
            viewModel.isBusy = false
        }
    }

    private func saveSlackToken() {
        do {
            let token = viewModel.slackToken.trimmingCharacters(in: .whitespacesAndNewlines)
            try SecretStore.shared.update { $0.slackToken = token.isEmpty ? nil : token }
            status(token.isEmpty ? "Slack token cleared." : "Slack token saved.")
            monitorService.restartIfRunning()
        } catch { status(error.localizedDescription, isError: true) }
    }

    private func saveBeeperToken() {
        do {
            let token = viewModel.beeperToken.trimmingCharacters(in: .whitespacesAndNewlines)
            try SecretStore.shared.update { $0.beeperToken = token.isEmpty ? nil : token }
            status(token.isEmpty ? "Beeper token cleared." : "Beeper token saved.")
            monitorService.restartIfRunning()
        } catch { status(error.localizedDescription, isError: true) }
    }

    private func saveOAuthClient() {
        do {
            let id = viewModel.oauthClientId.trimmingCharacters(in: .whitespacesAndNewlines)
            let secret = viewModel.oauthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            try SecretStore.shared.update {
                $0.oauthClientIdOverride = id.isEmpty ? nil : id
                $0.oauthClientSecretOverride = secret.isEmpty ? nil : secret
            }
            status(id.isEmpty ? "OAuth client cleared." : "OAuth client saved. Sign in from General to use it.")
        } catch { status(error.localizedDescription, isError: true) }
    }

    private func installHook(_ agent: CodingAgent) {
        if case .quiet(let other) = door.plan.role {
            status("The HomeSpeaker \(other.rawValue) is in use, so its hooks are the ones that run.", isError: true)
            return
        }
        do {
            try AgentIntegration.shared.installHook(for: agent)
            viewModel.refresh()
            status("\(agent.displayName) \(agent.hookKind) installed.")
        } catch { status(error.localizedDescription, isError: true) }
    }

    private func disableRival(_ agent: CodingAgent) {
        do {
            try AgentIntegration.shared.disableRivalHook(for: agent)
            viewModel.refresh()
            status("Disabled the duplicate hook; replies are announced once now.")
        } catch { status(error.localizedDescription, isError: true) }
    }

    private func addInstruction(_ agent: CodingAgent) {
        do {
            try AgentIntegration.shared.addBroadcastInstruction(for: agent)
            viewModel.refresh()
            status("Instruction added to \(agent.instructionFileName).")
        } catch { status(error.localizedDescription, isError: true) }
    }

    private func removeHook(_ agent: CodingAgent) {
        do {
            try AgentIntegration.shared.removeHook(for: agent)
            viewModel.refresh()
            status("\(agent.displayName) \(agent.hookKind) removed.")
        } catch { status(error.localizedDescription, isError: true) }
    }
}
