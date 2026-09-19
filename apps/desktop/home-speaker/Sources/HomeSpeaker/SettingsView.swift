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
    @Published public var oauthClientId: String = ""
    @Published public var oauthClientSecret: String = ""
    @Published public var hasBundledOAuthClient: Bool = false
    /// Which Settings pane is showing. Lives here rather than in an @State so
    /// the General pane can jump to Google Cloud setup, and because the
    /// Command Line Tools toolchain has no SwiftUI macro plugin for @State.
    @Published public var selectedTab: Tab = .general

    public enum Tab: Hashable { case general, speakers, monitor, agents, googleCloud }

    public init() {}

    func refresh(secrets: SecretStore = .shared) {
        agents = CodingAgent.allCases.map { AgentIntegration.shared.status(of: $0) }
        legacyLaunchAgentInstalled = AgentIntegration.shared.isLegacyLaunchAgentInstalled()
        launchAtLogin = LoginItem.isEnabled
        let s = secrets.load()
        slackToken = s.slackToken ?? ""
        oauthClientId = s.oauthClientIdOverride ?? ""
        oauthClientSecret = s.oauthClientSecretOverride ?? ""
        hasBundledOAuthClient = OAuthClient.resolve(secrets: Secrets()) != nil
    }
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
                .tabItem { Label("Chat & Slack", systemImage: "bubble.left.and.bubble.right") }
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

    private func status(_ text: String, isError: Bool = false) {
        viewModel.statusMessage = (isError ? "Error: " : "") + text
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
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
                    if OAuthClient.resolve(secrets: SecretStore.shared.load()) == nil {
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
                                status("Approve HomeSpeaker under System Settings > General > Login Items.")
                            }
                        } catch {
                            status(error.localizedDescription, isError: true)
                        }
                    }
                ))
                .accessibilityHint("Starts the menu bar app when you log in")
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

                DatePicker("Start", selection: timeBinding(\.quietHoursStart, fallback: "22:00"), displayedComponents: .hourAndMinute)
                    .disabled(!(configManager.config.quietHoursEnabled ?? false))
                    .accessibilityLabel("Quiet hours start time")

                DatePicker("End", selection: timeBinding(\.quietHoursEnd, fallback: "07:00"), displayedComponents: .hourAndMinute)
                    .disabled(!(configManager.config.quietHoursEnabled ?? false))
                    .accessibilityLabel("Quiet hours end time")
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

            statusSection
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
                            Button("Start") { monitorService.start() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!monitor.anySourceEnabled)
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
                Text("Off by default. When on, new messages are read aloud on the default speaker. Nothing is sent anywhere except to Google Home.")
            }

            Section("Slack") {
                Toggle("Announce Slack messages", isOn: monitorBinding(\.slackEnabled))
                    .accessibilityHint("Announces new Slack messages aloud")
                SecureField("User token (xoxp-…)", text: $viewModel.slackToken)
                    .onSubmit { saveSlackToken() }
                HStack {
                    Button("Save Token") { saveSlackToken() }
                        .controlSize(.small)
                    if let user = monitorService.slackUser {
                        Text("Signed in as \(user)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Create a Slack app with the `search:read` user scope and paste its user token. The token is stored only on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Announce Google Chat messages", isOn: monitorBinding(\.googleChatEnabled))
                    .accessibilityHint("Announces new Google Chat messages aloud")
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
                            Button("Disconnect") { Task { await GoogleAuth.shared.signOut(purpose: .chat); monitorService.restartIfRunning(); viewModel.objectWillChange.send() } }
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
            } header: {
                Text("Google Chat")
            } footer: {
                Text("Automatic uses the API when its permission is granted, otherwise gws if installed. “Skip messages I sent” needs your Google user id, which only an API sign-in provides.")
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

    private var hasChatScopes: Bool { SecretStore.shared.load().hasChatAccess }

    // MARK: - AI Agents Tab

    private var agentsTab: some View {
        Form {
            ForEach(viewModel.agents, id: \.agent) { st in
                Section {
                    if !st.isInstalled {
                        LabeledContent {
                            Text("Not installed on this Mac").foregroundStyle(.secondary)
                        } label: {
                            Text("\(st.agent.displayName) hook")
                            Text("Nothing to do here.")
                        }
                    } else if !st.agent.supportsHook {
                        LabeledContent {
                            if st.speaksTwice, let rival = st.rivalHook {
                            HStack(alignment: .firstTextBaseline) {
                                Label(
                                    "Every reply is spoken twice: \(rival.lastPathComponent) in \(rival.deletingLastPathComponent().lastPathComponent) also announces it.",
                                    systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Turn it off") { disableRival(st.agent) }
                                    .controlSize(.small)
                            }
                        }
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
                                 : "Adds one line to \(st.agent.instructionFileName) asking \(st.agent.displayName) to speak each reply. Antigravity's CLI does not run end-of-turn hooks, so this is the only path.")
                        }
                    } else {
                        LabeledContent {
                            switch st.hook {
                            case .installed:
                                HStack(spacing: 8) {
                                    Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                                    Button("Remove") { removeHook(st.agent) }.controlSize(.small)
                                }
                            case .stale:
                                HStack(spacing: 8) {
                                    Label("Needs update", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                                    Button("Update Hook") { installHook(st.agent) }.buttonStyle(.borderedProminent).controlSize(.small)
                                }
                            case .notInstalled:
                                Button("Install Hook") { installHook(st.agent) }.buttonStyle(.borderedProminent).controlSize(.small)
                            }
                        } label: {
                            Text("\(st.agent.displayName) hook")
                            Text("Speaks a one-sentence summary of each reply when a turn finishes.")
                        }
                        Text(AgentIntegration.shared.hookCommand(for: st.agent))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if st.configuredByInstruction {
                            Label(st.hook == .installed
                                  ? "Your \(st.agent == .antigravity ? "AGENTS.md" : "CLAUDE.md") also tells \(st.agent.displayName) to broadcast on its own. With the hook installed, remove that instruction to avoid hearing replies twice."
                                  : "Already announcing: your \(st.agent == .antigravity ? "AGENTS.md" : "CLAUDE.md") tells \(st.agent.displayName) to broadcast on its own. The hook is optional — it makes that deterministic and needs no model cooperation.",
                                  systemImage: st.hook == .installed ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(st.hook == .installed ? .orange : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } header: {
                    Text(st.agent.displayName)
                } footer: {
                    Text(st.agent == .claudeCode
                         ? "Adds one entry to the Stop hooks in ~/.claude/settings.json. Other hooks you have are left untouched."
                         : "Reads the broadcast settings and speaker from the same files as this app, so switching speakers here changes where Antigravity speaks.")
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

    private func signOut() {
        Task {
            await GoogleAuth.shared.signOut()
            configManager.checkConnection()
            monitorService.stop()
            status("Signed out.")
        }
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
        do {
            try AgentIntegration.shared.installHook(for: agent)
            viewModel.refresh()
            status("\(agent.displayName) hook installed.")
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
            status("\(agent.displayName) hook removed.")
        } catch { status(error.localizedDescription, isError: true) }
    }
}
