import SwiftUI

/// Settings window for configuring the bot's .env file.
struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var botManager: BotManager
    @State private var showSaveConfirmation = false

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 520)
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
