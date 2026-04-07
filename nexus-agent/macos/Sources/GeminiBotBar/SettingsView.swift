import SwiftUI

/// Settings window for configuring the bot's .env file.
struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var botManager: BotManager
    @State private var showSaveConfirmation = false
    @State private var showAddProviderForm = false
    @State private var newProviderName = ""
    @State private var newProviderTemplate = ""
    @State private var editingProviderId: UUID? = nil

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
                            isEditing: editingProviderId == provider.id,
                            onEdit: { editingProviderId = editingProviderId == provider.id ? nil : provider.id },
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
    let isEditing: Bool
    let onEdit: () -> Void
    let onDelete: (() -> Void)?

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
                    onEdit()
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
                TextField("Command template", text: $provider.commandTemplate)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.leading, 14)
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
