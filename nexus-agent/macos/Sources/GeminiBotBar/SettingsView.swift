import SwiftUI

/// Settings window for configuring the bot's .env file.
struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var botManager: BotManager
    @ObservedObject var updateChecker: UpdateChecker
    @State private var showSaveConfirmation = false
    @State private var showAddProviderForm = false
    @State private var newProviderName = ""
    @State private var newProviderTemplate = ""

        var body: some View {
        VStack(spacing: 0) {
            TabView {
                // Tab 1: General (App & Telegram)
                Form {
                    Section(header: Text("App")) {
                HStack {
                    Text("Bot Directory")
                        .frame(width: 120, alignment: .trailing)
                    TextField("/path/to/gemini-bot", text: $configManager.botDirectoryOverride)
                        .textFieldStyle(.roundedBorder)
                        .help("Path to the gemini-bot checkout containing src/bot.js and .env")
                    Button("Browse") {
                        selectBotDirectory()
                    }
                }

                HStack {
                    Text("")
                        .frame(width: 120, alignment: .trailing)
                    Toggle("Thinking mode (deep reasoning)", isOn: $configManager.thinking)
                }
                HStack {
                    Text("")
                        .frame(width: 120, alignment: .trailing)
                    Toggle("Auto-start bot when app launches", isOn: $configManager.autoStart)
                }

                HStack {
                    Text("Quick Prompt Hotkey")
                        .frame(width: 120, alignment: .trailing)
                    HotkeyRecorderView(
                        key: $configManager.hotkeyKey,
                        modifiers: $configManager.hotkeyModifiers
                    )
                }
            }
                    
                    Section(header: Text("Telegram")) {
                HStack {
                    Text("Bot Token")
                        .frame(width: 120, alignment: .trailing)
                    SecureField("From @BotFather", text: $configManager.botToken)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Allowed User IDs")
                        .frame(width: 120, alignment: .trailing)
                    TextField("Comma-separated IDs", text: $configManager.allowedUserIds)
                        .textFieldStyle(.roundedBorder)
                }
            }
                }
                .formStyle(.grouped)
                .tabItem { Label("General", systemImage: "gearshape") }
                
                // Tab 2: Gemini CLI
                Form {
                    Section(header: Text("Gemini CLI")) {
                HStack {
                    Text("Working Directory")
                        .frame(width: 120, alignment: .trailing)
                    TextField("/path/to/project", text: $configManager.workingDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") {
                        selectDirectory()
                    }
                }

                HStack {
                    Text("Approval Mode")
                        .frame(width: 120, alignment: .trailing)
                    Picker("", selection: $configManager.approvalMode) {
                        Text("YOLO (auto-approve all)").tag("yolo")
                        Text("Auto Edit (auto-approve edits)").tag("auto_edit")
                        Text("Default (prompt for each)").tag("default")
                    }
                    .labelsHidden()
                }

                HStack {
                    Text("Model")
                        .frame(width: 120, alignment: .trailing)
                    TextField("Leave empty for default", text: $configManager.model)
                        .textFieldStyle(.roundedBorder)
                }
            }
                }
                .formStyle(.grouped)
                .tabItem { Label("Gemini CLI", systemImage: "terminal") }

                // Tab 3: Providers (AI Backend)
                Form {
                    // ── AI Backend ──
            Section(header: Text("AI Backend")) {
                HStack {
                    Text("Active Provider")
                        .frame(width: 120, alignment: .trailing)
                    Picker("", selection: $configManager.activeProviderId) {
                        ForEach(configManager.providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                }

                // Provider list
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($configManager.providers) { $provider in
                        ProviderRow(
                            provider: $provider,
                            isActive: configManager.activeProviderId == provider.id,
                            onDelete: provider.isBuiltIn ? nil : {
                                configManager.providers.removeAll { $0.id == provider.id }
                                if configManager.activeProviderId == provider.id {
                                    configManager.activeProviderId = CLIProvider.gemini.id
                                }
                            }
                        )
                    }
                }

                // Add custom provider
                if showAddProviderForm {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Name")
                                .frame(width: 80, alignment: .trailing)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("e.g. Aider", text: $newProviderName)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                        }
                        HStack(alignment: .top) {
                            Text("Command")
                                .frame(width: 80, alignment: .trailing)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("/usr/local/bin/aider --message \"{prompt}\"", text: $newProviderTemplate)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                        }
                        Text("Use {prompt} for the user's message, {model} for the active model.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 84)
                        HStack {
                            Spacer()
                            Button("Cancel") {
                                showAddProviderForm = false
                                newProviderName = ""
                                newProviderTemplate = ""
                            }
                            .controlSize(.small)
                            Button("Add") {
                                guard !newProviderName.isEmpty, !newProviderTemplate.isEmpty else { return }
                                let p = CLIProvider(id: UUID(), name: newProviderName,
                                                   commandTemplate: newProviderTemplate, isBuiltIn: false)
                                configManager.providers.append(p)
                                showAddProviderForm = false
                                newProviderName = ""
                                newProviderTemplate = ""
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                            .disabled(newProviderName.isEmpty || newProviderTemplate.isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button("+ Add Custom Provider") {
                        showAddProviderForm = true
                    }
                    .controlSize(.small)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
                }
                .formStyle(.grouped)
                .tabItem { Label("Providers", systemImage: "network") }

                // Tab 4: About
                AboutTabView(updateChecker: updateChecker, autoCheckUpdates: $configManager.autoCheckUpdates)
                    .tabItem { Label("About", systemImage: "info.circle") }
            }
            
            // ── Status ──
            HStack {
                Text(configManager.configStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if showSaveConfirmation {
                    Text("✅ Saved!")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }

                Button("Save") {
                    configManager.save()

                    withAnimation {
                        showSaveConfirmation = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showSaveConfirmation = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                if botManager.isRunning {
                    Button("Save & Restart") {
                        configManager.save()
                        botManager.restart()

                        withAnimation {
                            showSaveConfirmation = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showSaveConfirmation = false
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
        .padding()
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the working directory for Gemini CLI"

        if panel.runModal() == .OK, let url = panel.url {
            configManager.workingDirectory = url.path
        }
    }

    private func selectBotDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the gemini-bot checkout folder (containing src/bot.js)"

        if panel.runModal() == .OK, let url = panel.url {
            configManager.botDirectoryOverride = url.path
        }
    }
}

// MARK: - Provider Row

/// A single row in the provider list — shows name, truncated template, edit/delete controls.
struct ProviderRow: View {
    @Binding var provider: CLIProvider
    let isActive: Bool
    let onDelete: (() -> Void)?

    @State private var isEditing: Bool = false
    @State private var draftTemplate: String = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Active indicator dot
                Circle()
                    .fill(isActive ? Color.green : Color.clear)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))

                Text(provider.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)

                if provider.isBuiltIn {
                    Text("built-in")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12)))
                }

                Spacer()

                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        provider.commandTemplate = draftTemplate
                        isEditing = false
                    } else {
                        draftTemplate = provider.commandTemplate
                        isEditing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isFieldFocused = true
                        }
                    }
                }
                .controlSize(.mini)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            if isEditing {
                TextField("Command template", text: $draftTemplate)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.leading, 14)
                    .focused($isFieldFocused)
            } else {
                Text(provider.commandTemplate)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 14)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Hotkey Recorder

/// A keyboard shortcut recorder control. Click to start recording, then press the desired key combo.
struct HotkeyRecorderView: View {
    @Binding var key: String
    @Binding var modifiers: Int
    @State private var isRecording = false
    
    private var displayString: String {
        var parts: [String] = []
        let mods = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        parts.append(key.uppercased())
        return parts.joined()
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if isRecording {
                Text("Press shortcut…")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.orange, lineWidth: 1.5)
                    )
                    .background(KeyEventCatcher(onKeyDown: { event in
                        let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
                        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
                              !chars.isEmpty,
                              eventMods.rawValue != 0 else { return }
                        
                        key = chars
                        modifiers = Int(eventMods.rawValue)
                        isRecording = false
                    }))
                
                Button("Cancel") {
                    isRecording = false
                }
                .controlSize(.small)
            } else {
                Text(displayString)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.tertiary)
                    )
                
                Button("Record") {
                    isRecording = true
                }
                .controlSize(.small)
                
                Button("Reset") {
                    key = "g"
                    modifiers = Int(NSEvent.ModifierFlags([.command, .shift]).rawValue)
                }
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// NSView wrapper to capture key events for the hotkey recorder.
struct KeyEventCatcher: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void
    
    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

class KeyCatcherView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

// MARK: - About Tab

struct AboutTabView: View {
    @ObservedObject var updateChecker: UpdateChecker
    @Binding var autoCheckUpdates: Bool
    @State private var isCheckingForUpdate = false
    @State private var checkComplete = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // App Icon
            VStack(spacing: 16) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 96, height: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    )
                
                VStack(spacing: 4) {
                    Text("Gemini Bot Bar")
                        .font(.title2.weight(.semibold))
                    Text("Version \(appVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                
                Text("A native macOS menu bar companion for Gemini CLI and Telegram Bot with a Spotlight-style quick prompt interface.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .padding(.top, 4)
            }
            
            Spacer().frame(height: 24)
            
            // Links
            HStack(spacing: 20) {
                Link(destination: URL(string: "https://github.com/\(appRepoOwner)/\(appRepoName)")!) {
                    Label("GitHub", systemImage: "link")
                        .font(.callout)
                }
                
                Link(destination: URL(string: "https://github.com/\(appRepoOwner)/\(appRepoName)/releases")!) {
                    Label("Releases", systemImage: "arrow.down.circle")
                        .font(.callout)
                }
                
                Link(destination: URL(string: "https://github.com/\(appRepoOwner)/\(appRepoName)/issues")!) {
                    Label("Issues", systemImage: "exclamationmark.bubble")
                        .font(.callout)
                }
            }
            
            Spacer().frame(height: 28)
            
            // Update Section
            VStack(spacing: 12) {
                Divider().padding(.horizontal, 40)
                
                if updateChecker.updateAvailable {
                    // Update available state
                    VStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                            Text("v\(updateChecker.latestVersion) is available!")
                                .font(.callout.weight(.medium))
                        }
                        
                        if updateChecker.isDownloading {
                            VStack(spacing: 6) {
                                ProgressView(value: updateChecker.downloadProgress)
                                    .progressViewStyle(.linear)
                                    .frame(width: 220)
                                Text("Downloading… \(Int(updateChecker.downloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if updateChecker.isInstalling {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Installing update…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button(action: {
                                Task { await updateChecker.downloadAndInstall() }
                            }) {
                                Label("Update & Restart", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                    }
                } else if isCheckingForUpdate {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking for updates…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if checkComplete && !updateChecker.updateAvailable {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("You're up to date!")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(action: {
                        isCheckingForUpdate = true
                        checkComplete = false
                        Task {
                            await updateChecker.checkForUpdates()
                            isCheckingForUpdate = false
                            checkComplete = true
                            // Reset "up to date" message after a few seconds
                            if !updateChecker.updateAvailable {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                    checkComplete = false
                                }
                            }
                        }
                    }) {
                        Label("Check for Updates", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                
                if let errorMsg = updateChecker.errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                
                Toggle("Automatically check for updates on launch", isOn: $autoCheckUpdates)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
            
            Spacer()
            
            // Copyright
            Text("© 2026 Vitruvian Software. Open source under MIT License.")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
