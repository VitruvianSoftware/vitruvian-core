import SwiftUI
import AppKit
import Carbon.HIToolbox

// Global C callback for the Carbon hotkey event handler
private func carbonHotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        QuickPromptWindowController.shared.toggle()
    }
    return noErr
}

// MARK: - Custom Panel
/// An NSPanel subclass that overrides `canBecomeKey` to allow text input without a title bar.
class QuickPromptPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

/// A Spotlight-style floating panel for quickly sending prompts to Gemini CLI.
class QuickPromptWindowController {
    static let shared = QuickPromptWindowController()
    
    var window: NSPanel?
    private var hostingView: NSHostingView<QuickPromptView>?
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    
    // Configurable hotkey (defaults to ⌘+Shift+G)
    private var expectedKey: String = "g"
    private var expectedModifiers: NSEvent.ModifierFlags = [.command, .shift]
    
    private init() {
        let savedKey = UserDefaults.standard.string(forKey: "hotkeyKey") ?? "g"
        let savedMods = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        expectedKey = savedKey
        if savedMods != 0 {
            expectedModifiers = NSEvent.ModifierFlags(rawValue: UInt(savedMods))
        }
    }
    
    /// Register the global hotkey using both Carbon API and NSEvent monitors.
    func registerHotkey() {
        registerCarbonHotkey()
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSEvent(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSEvent(event)
            return event
        }
        requestAccessibilityIfNeeded()
    }
    
    /// Update the hotkey binding at runtime (called from Settings).
    func updateHotkey(key: String, modifiers: NSEvent.ModifierFlags) {
        expectedKey = key.lowercased()
        expectedModifiers = modifiers
        unregisterCarbonHotkey()
        registerCarbonHotkey()
    }
    
    private func handleNSEvent(_ event: NSEvent) {
        let requiredMods = expectedModifiers.intersection([.command, .shift, .option, .control])
        let eventMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard eventMods == requiredMods,
              event.charactersIgnoringModifiers?.lowercased() == expectedKey else { return }
        DispatchQueue.main.async { [weak self] in
            self?.toggle()
        }
    }
    
    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted {
            print("✅ Accessibility permissions granted — global hotkey active")
        } else {
            print("⚠️ Accessibility permissions needed for global hotkey")
        }
    }
    
    private func registerCarbonHotkey() {
        var carbonMods: UInt32 = 0
        if expectedModifiers.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if expectedModifiers.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if expectedModifiers.contains(.option) { carbonMods |= UInt32(optionKey) }
        if expectedModifiers.contains(.control) { carbonMods |= UInt32(controlKey) }
        
        guard let keyCode = carbonKeyCode(for: expectedKey) else {
            print("⚠️ Could not find key code for '\(expectedKey)'")
            return
        }
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyHandler,
            1, &eventType, nil, &eventHandler
        )
        
        let hotkeyID = EventHotKeyID(signature: OSType(0x47454D42), id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, carbonMods, hotkeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        
        if status == noErr {
            hotkeyRef = ref
            print("✅ Global hotkey registered")
        } else {
            print("⚠️ Failed to register hotkey: \(status)")
        }
    }
    
    private func unregisterCarbonHotkey() {
        if let ref = hotkeyRef { UnregisterEventHotKey(ref); hotkeyRef = nil }
        if let handler = eventHandler { RemoveEventHandler(handler); eventHandler = nil }
    }
    
    private func carbonKeyCode(for key: String) -> UInt32? {
        let map: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            " ": kVK_Space, "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal,
            "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
            ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote,
            ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
            "/": kVK_ANSI_Slash, "`": kVK_ANSI_Grave,
        ]
        guard let code = map[key.lowercased()] else { return nil }
        return UInt32(code)
    }
    
    /// Toggle the quick prompt window.
    func toggle() {
        if let window = window, window.isVisible {
            dismiss()
        } else {
            show()
        }
    }
    
    func show() {
        window?.orderOut(nil)
        window = nil
        createWindow()
        
        guard let window = window else { return }
        
        // Position: centered horizontally, upper-third of screen (like Spotlight)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 680
            let windowHeight: CGFloat = 72   // compact: input bar only
            let x = screenFrame.midX - windowWidth / 2
            let y = screenFrame.maxY - windowHeight - (screenFrame.height * 0.18)
            window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Force focus on the text field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let window = self?.window else { return }
            window.makeKey()
            if let textField = self?.findTextField(in: window.contentView) {
                window.makeFirstResponder(textField)
            }
        }
        
        // Click-outside-to-dismiss (Spotlight behavior)
        addClickOutsideMonitor()
    }
    
    private var clickOutsideMonitor: Any?
    
    private func addClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let window = self?.window, window.isVisible else { return }
            DispatchQueue.main.async {
                self?.dismiss()
            }
        }
    }
    
    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
    
    /// Recursively find the first NSTextField in a view hierarchy.
    private func findTextField(in view: NSView?) -> NSTextField? {
        guard let view = view else { return nil }
        if let tf = view as? NSTextField, tf.isEditable { return tf }
        for subview in view.subviews {
            if let found = findTextField(in: subview) { return found }
        }
        return nil
    }
    
    func dismiss() {
        window?.orderOut(nil)
        removeClickOutsideMonitor()
    }
    
    private func createWindow() {
        let promptView = QuickPromptView(onSubmit: { [weak self] prompt in
            self?.runPrompt(prompt)
        }, onResume: { [weak self] sessionIndex, sessionUUID in
            self?.resumeSession(sessionIndex, uuid: sessionUUID)
        }, onDismiss: { [weak self] in
            self?.dismiss()
        })
        
        let hosting = NSHostingView(rootView: promptView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        
        // Spotlight-style panel: no title bar, no chrome
        let panel = QuickPromptPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 72),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        
        // Spotlight-style vibrancy material  
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 22
        visualEffect.layer?.masksToBounds = true
        
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = visualEffect.bounds
        
        visualEffect.addSubview(hosting)
        panel.contentView = visualEffect
        
        self.window = panel
        self.hostingView = hosting
    }
    
    private func runPrompt(_ prompt: String) {
        expandAndShowChat(QuickPromptChatView(initialPrompt: prompt, resumeIndex: nil, resumeUUID: nil))
    }
    
    private func resumeSession(_ index: Int, uuid: String) {
        expandAndShowChat(QuickPromptChatView(initialPrompt: nil, resumeIndex: index, resumeUUID: uuid))
    }
    
    private func expandAndShowChat(_ chatView: QuickPromptChatView) {
        guard let window = window else { return }
        
        window.minSize = NSSize(width: 680, height: 400)
        
        let targetSize = NSSize(width: 680, height: 500)
        let currentFrame = window.frame
        let newOriginY = currentFrame.origin.y + currentFrame.height - targetSize.height
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: newOriginY,
            width: targetSize.width,
            height: targetSize.height
        )
        window.setFrame(newFrame, display: false)
        
        let hosting = NSHostingView(rootView: chatView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 22
        visualEffect.layer?.masksToBounds = true
        
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = visualEffect.bounds
        visualEffect.addSubview(hosting)
        
        window.contentView = visualEffect
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Session Info Model

struct SessionInfo: Identifiable {
    let id: Int  // session index (1-based)
    let title: String
    let timeAgo: String
    let uuid: String
}

// MARK: - Quick Prompt Input View

struct QuickPromptView: View {
    let onSubmit: (String) -> Void
    let onResume: (Int, String) -> Void
    let onDismiss: () -> Void
    @State private var prompt: String = ""
    @State private var sessions: [SessionInfo] = []
    @State private var loadingSessions = false
    @State private var showSessions = false
    @State private var hoveredSessionId: Int? = nil
    @State private var selectedSessionIndex: Int? = nil
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Original Quick Prompt Input Row ──
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                
                TextField("Ask Gemini anything…", text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    .onSubmit {
                        if let selIdx = selectedSessionIndex,
                           let session = displayedSessions[safe: selIdx] {
                            onResume(session.id, session.uuid)
                        } else {
                            guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            onSubmit(prompt)
                        }
                    }
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showSessions.toggle()
                    }
                    selectedSessionIndex = nil
                    resizePanel(expanded: showSessions)
                    if showSessions && sessions.isEmpty {
                        loadingSessions = true
                        loadSessions()
                    }
                }) {
                    Image(systemName: showSessions ? "clock.fill" : "clock")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(showSessions ? Color.blue : Color.primary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Recent sessions")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // ── Sessions Panel (animated, shown only when toggled) ──
            if showSessions {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .transition(.opacity)

                if loadingSessions {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else if sessions.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 28))
                            .foregroundStyle(.quaternary)
                        Text("No recent sessions")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Recent")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 20)
                                .padding(.top, 10)
                                .padding(.bottom, 4)

                            ForEach(Array(displayedSessions.enumerated()), id: \.element.id) { idx, session in
                                Button(action: {
                                    onResume(session.id, session.uuid)
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "text.bubble")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.blue)
                                            .frame(width: 28, height: 28)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.blue.opacity(0.1))
                                            )

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(session.title)
                                                .font(.system(size: 13))
                                                .lineLimit(1)
                                                .foregroundStyle(.primary)
                                            Text(session.timeAgo)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                selectedSessionIndex == idx
                                                    ? Color.blue.opacity(0.2)
                                                    : (hoveredSessionId == session.id
                                                       ? Color.primary.opacity(0.06)
                                                       : Color.clear)
                                            )
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { isHovering in
                                    hoveredSessionId = isHovering ? session.id : nil
                                    if isHovering { selectedSessionIndex = nil }
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .onAppear {
            isFocused = true
            setupKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onExitCommand { onDismiss() }
    }
    
    // Keyboard Event Monitor
    @State private var eventMonitor: Any?
    
    private func setupKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 125 = Down arrow, 126 = Up arrow, 36 = Return
            if event.keyCode == 125 {
                moveSelection(down: true)
                return nil // consume event
            } else if event.keyCode == 126 {
                moveSelection(down: false)
                return nil // consume event
            }
            return event
        }
    }
    
    private func removeKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func moveSelection(down: Bool) {
        let count = displayedSessions.count
        guard count > 0 else { return }
        
        if down {
            if let current = selectedSessionIndex {
                selectedSessionIndex = min(current + 1, count - 1)
            } else {
                selectedSessionIndex = 0
            }
        } else {
            if let current = selectedSessionIndex {
                selectedSessionIndex = max(current - 1, 0)
            } else {
                selectedSessionIndex = count - 1
            }
        }
    }
    
    private var displayedSessions: [SessionInfo] {
        Array(sessions.prefix(10))
    }
    
    private func loadSessions() {
        let workDir = Self.resolveWorkingDirectory()
        DispatchQueue.global(qos: .userInitiated).async {
            let parsed = SessionFileReader.listSessions(workingDirectory: workDir)
            DispatchQueue.main.async {
                sessions = parsed
                loadingSessions = false
            }
        }
    }

    /// Animate the underlying NSPanel between compact (input-only) and expanded (sessions) heights.
    private func resizePanel(expanded: Bool) {
        guard let window = QuickPromptWindowController.shared.window else { return }
        let compactHeight: CGFloat = 72
        let expandedHeight: CGFloat = 340
        let targetHeight = expanded ? expandedHeight : compactHeight
        let currentFrame = window.frame
        // Anchor resize to the top of the panel
        let newOriginY = currentFrame.origin.y + currentFrame.height - targetHeight
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: newOriginY,
            width: currentFrame.width,
            height: targetHeight
        )
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    /// Resolve the working directory — must be called from main thread.
    @MainActor static func resolveWorkingDirectory() -> URL {
        if let config = ConfigManager.shared {
            let configDir = config.workingDirectory
            if !configDir.isEmpty {
                return URL(fileURLWithPath: configDir)
            }
        }
        if let dir = ProcessInfo.processInfo.environment["GEMINI_WORKING_DIR"] {
            return URL(fileURLWithPath: dir)
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }
}

// MARK: - Session File Reading

/// Utilities for reading Gemini CLI session files directly from disk.
enum SessionFileReader {
    /// Resolve the chats directory for the current working directory.
    /// Reads ~/.gemini/projects.json to map working dir → project slug,
    /// then returns ~/.gemini/tmp/{slug}/chats/
    static func resolveChatsDirectory(workingDirectory: URL) -> URL? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let registryPath = homeDir.appendingPathComponent(".gemini/projects.json")
        
        guard let data = try? Data(contentsOf: registryPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [String: String] else {
            return nil
        }
        
        let workDir = workingDirectory.path
        guard let slug = projects[workDir] else { return nil }
        
        return homeDir.appendingPathComponent(".gemini/tmp/\(slug)/chats")
    }
    
    /// List all sessions by reading JSON files from the chats directory.
    /// Returns SessionInfo array sorted newest-first.
    static func listSessions(workingDirectory: URL) -> [SessionInfo] {
        guard let chatsDir = resolveChatsDirectory(workingDirectory: workingDirectory) else {
            return []
        }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: chatsDir.path) else {
            return []
        }
        
        let sessionFiles = files.filter { $0.hasPrefix("session-") && $0.hasSuffix(".json") }.sorted()
        
        var sessions: [SessionInfo] = []
        for (index, fileName) in sessionFiles.enumerated() {
            let filePath = chatsDir.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: filePath),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionId = json["sessionId"] as? String,
                  let messages = json["messages"] as? [[String: Any]],
                  let lastUpdated = json["lastUpdated"] as? String else {
                continue
            }
            
            // Skip subagent sessions
            if let kind = json["kind"] as? String, kind == "subagent" { continue }
            
            // Skip sessions with no user or assistant messages
            let hasContent = messages.contains { msg in
                let type = msg["type"] as? String
                return type == "user" || type == "gemini"
            }
            guard hasContent else { continue }
            
            // Use summary if available, otherwise extract first user message
            let title: String
            if let summary = json["summary"] as? String, !summary.isEmpty {
                title = String(summary.prefix(100))
            } else {
                title = extractFirstUserMessage(from: messages)
            }
            
            let timeAgo = formatRelativeTime(lastUpdated)
            sessions.append(SessionInfo(id: index + 1, title: title, timeAgo: timeAgo, uuid: sessionId))
        }
        
        // Return newest first
        return sessions.reversed()
    }
    
    /// Load messages from a session file identified by UUID.
    /// Returns an array of ChatMessage if successful, nil otherwise.
    static func loadSessionMessages(uuid: String, chatsDirectory: URL) -> [ChatMessage]? {
        // Find the session file by UUID prefix match (filename contains first 8 chars of UUID)
        let uuidPrefix = String(uuid.prefix(8))
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: chatsDirectory.path) else {
            return nil
        }
        
        let sessionFile = files.first { $0.hasPrefix("session-") && $0.contains(uuidPrefix) && $0.hasSuffix(".json") }
        guard let fileName = sessionFile else { return nil }
        
        let filePath = chatsDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: filePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawMessages = json["messages"] as? [[String: Any]] else {
            return nil
        }
        
        var chatMessages: [ChatMessage] = []
        for msg in rawMessages {
            guard let type = msg["type"] as? String else { continue }
            // Only show user and gemini (assistant) messages
            guard type == "user" || type == "gemini" else { continue }
            
            let content = extractContent(from: msg)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            
            let role = type == "user" ? "user" : "assistant"
            chatMessages.append(ChatMessage(role: role, content: content))
        }
        
        return chatMessages.isEmpty ? nil : chatMessages
    }
    
    /// Extract text content from a message's "content" field.
    /// Content can be a plain string or an array of {"text": "..."} parts.
    private static func extractContent(from message: [String: Any]) -> String {
        // Try displayContent first (cleaned-up version), then fall back to content
        if let display = extractContentValue(message["displayContent"]) {
            return display
        }
        return extractContentValue(message["content"]) ?? ""
    }
    
    private static func extractContentValue(_ value: Any?) -> String? {
        guard let value = value else { return nil }
        
        // Plain string
        if let str = value as? String, !str.isEmpty {
            return str
        }
        
        // Array of parts: [{"text": "..."}]
        if let parts = value as? [[String: Any]] {
            let texts = parts.compactMap { $0["text"] as? String }
            let joined = texts.joined()
            return joined.isEmpty ? nil : joined
        }
        
        return nil
    }
    
    /// Extract the first user message text for display as a session title.
    private static func extractFirstUserMessage(from messages: [[String: Any]]) -> String {
        guard let firstUser = messages.first(where: { ($0["type"] as? String) == "user" }) else {
            return "Empty conversation"
        }
        let content = extractContent(from: firstUser)
        let cleaned = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(100))
    }
    
    /// Format an ISO timestamp as a relative time string (e.g., "2 hours ago").
    private static func formatRelativeTime(_ isoTimestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoTimestamp) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoTimestamp) else { return "" }
            return relativeString(from: date)
        }
        return relativeString(from: date)
    }
    
    private static func relativeString(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        
        if days > 0 { return "\(days) day\(days == 1 ? "" : "s") ago" }
        if hours > 0 { return "\(hours) hour\(hours == 1 ? "" : "s") ago" }
        if minutes > 0 { return "\(minutes) minute\(minutes == 1 ? "" : "s") ago" }
        return "Just now"
    }
}

// MARK: - Chat Conversation View

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
}

struct QuickPromptChatView: View {
    let initialPrompt: String?
    let resumeIndex: Int?
    let resumeUUID: String?
    @State private var messages: [ChatMessage] = []
    @State private var followUp: String = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var hasActiveSession = false
    @State private var currentProcess: Process?
    @State private var promptHistory: [String] = []
    @State private var historyIndex: Int = -1
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Gemini Chat")
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                
                Button(action: {
                    messages.removeAll()
                    hasActiveSession = false
                    error = nil
                    followUp = ""
                    isInputFocused = true
                }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Chat")
                
                Button(action: {
                    QuickPromptWindowController.shared.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 12)
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                        
                        if isLoading {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking…")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Spacer()
                                Button(action: stopGeneration) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "stop.circle.fill")
                                        Text("Stop")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .id("loading")
                        }
                        
                        if let error = error {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Follow-up input (polished capsule)
            HStack(spacing: 10) {
                Image(systemName: "text.cursor")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                TextField("Follow up…", text: $followUp)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }
                    .disabled(isLoading)
                    .onKeyPress(.upArrow) {
                        if followUp.isEmpty && !promptHistory.isEmpty {
                            if historyIndex < 0 { historyIndex = promptHistory.count }
                            historyIndex = max(0, historyIndex - 1)
                            followUp = promptHistory[historyIndex]
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) {
                        if historyIndex >= 0 && historyIndex < promptHistory.count - 1 {
                            historyIndex += 1
                            followUp = promptHistory[historyIndex]
                            return .handled
                        } else if historyIndex >= 0 {
                            historyIndex = -1
                            followUp = ""
                            return .handled
                        }
                        return .ignored
                    }
                
                if isLoading {
                    Button(action: stopGeneration) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                followUp.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? .gray : .blue
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(followUp.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.3))
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .task {
            if let resumeIdx = resumeIndex {
                loadSessionFromDisk(resumeIdx)
            } else if let prompt = initialPrompt {
                await sendToCLI(prompt)
            }
            isInputFocused = true
        }
    }
    
    private func sendMessage() {
        let text = followUp.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isLoading else { return }
        promptHistory.append(text)
        historyIndex = -1
        followUp = ""
        Task { await sendToCLI(text) }
    }
    
    private func stopGeneration() {
        currentProcess?.terminate()
        currentProcess = nil
        isLoading = false
    }
    
    /// Load an existing session's conversation history from disk.
    private func loadSessionFromDisk(_ index: Int) {
        let workDir = QuickPromptView.resolveWorkingDirectory()
        
        // Try to load messages from the session JSON file
        if let uuid = resumeUUID,
           let chatsDir = SessionFileReader.resolveChatsDirectory(workingDirectory: workDir),
           let loaded = SessionFileReader.loadSessionMessages(uuid: uuid, chatsDirectory: chatsDir) {
            messages = loaded
            hasActiveSession = true
        } else {
            // Fallback: show a message indicating we couldn't load history
            messages = [ChatMessage(role: "assistant", content: "Session resumed. Send a message to continue.")]
            hasActiveSession = true
        }
    }
    
    private func sendToCLI(_ prompt: String) async {
        messages.append(ChatMessage(role: "user", content: prompt))
        isLoading = true
        error = nil
        
        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()
        
        let geminiBin = ProcessInfo.processInfo.environment["GEMINI_BIN"]
            ?? "/opt/homebrew/bin/gemini"
        
        process.executableURL = URL(fileURLWithPath: geminiBin)
        var args = ["-p", prompt, "--output-format", "json", "--approval-mode", "yolo"]
        if hasActiveSession { args += ["--resume", "latest"] }
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = errPipe
        process.environment = ProcessInfo.processInfo.environment
        process.environment?["NO_COLOR"] = "1"
        let workDir = QuickPromptView.resolveWorkingDirectory()
        // Validate the directory exists — if not, fall back to home to avoid a cryptic crash
        let resolvedWorkDir: URL
        if FileManager.default.fileExists(atPath: workDir.path) {
            resolvedWorkDir = workDir
        } else {
            resolvedWorkDir = URL(fileURLWithPath: NSHomeDirectory())
        }
        process.currentDirectoryURL = resolvedWorkDir
        currentProcess = process
        
        do {
            try process.run()
            
            // Run blocking I/O on a background thread to avoid beach ball
            let (output, stderr, status) = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    
                    let out = String(data: outputData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let err = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    continuation.resume(returning: (out, err, process.terminationStatus))
                }
            }
            
            currentProcess = nil
            if status == 15 || status == 9 {
                error = "Generation stopped"
            } else if status != 0 && output.isEmpty {
                error = stderr.isEmpty
                    ? "CLI exited with code \(status)"
                    : String(stderr.prefix(300))
            } else if output.isEmpty {
                error = "Empty response from Gemini"
            } else {
                let parsed = parseGeminiJSON(output)
                messages.append(ChatMessage(role: "assistant", content: parsed.text ?? output))
                    hasActiveSession = true
            }
            isLoading = false
        } catch {
            currentProcess = nil
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    // MARK: - JSON Parsing
    
    private struct ParsedResponse { var text: String?; var sessionId: String? }
    
    private func parseGeminiJSON(_ raw: String) -> ParsedResponse {
        guard let data = raw.data(using: .utf8) else { return ParsedResponse() }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ParsedResponse(
                text: extractText(json),
                sessionId: json["sessionId"] as? String ?? json["session_id"] as? String
            )
        }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let texts = arr.compactMap { extractText($0) }
            return ParsedResponse(
                text: texts.isEmpty ? nil : texts.joined(separator: "\n"),
                sessionId: arr.last?["sessionId"] as? String ?? arr.last?["session_id"] as? String
            )
        }
        var lastSid: String?
        let texts = raw.split(separator: "\n").compactMap { line -> String? in
            guard let d = String(line).data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
            if let s = j["sessionId"] as? String ?? j["session_id"] as? String { lastSid = s }
            return extractText(j)
        }
        return ParsedResponse(text: texts.isEmpty ? nil : texts.joined(separator: "\n"), sessionId: lastSid)
    }
    
    private func extractText(_ json: [String: Any]) -> String? {
        if let r = json["response"] as? String { return r }
        if let m = json["message"] as? String { return m }
        if let c = json["content"] as? String { return c }
        if let msgs = json["messages"] as? [[String: Any]] {
            let t = msgs
                .filter { ($0["role"] as? String) == "assistant" || ($0["role"] as? String) == "model" }
                .compactMap { m -> String? in
                    if let p = m["parts"] as? [[String: Any]] { return p.compactMap { $0["text"] as? String }.joined() }
                    return m["content"] as? String ?? m["text"] as? String
                }
            if !t.isEmpty { return t.joined(separator: "\n") }
        }
        return nil
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @State private var copied = false
    
    var isUser: Bool { message.role == "user" }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 40) }
            
            // Assistant avatar
            if !isUser {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.blue.opacity(0.15)))
                    .padding(.top, 4)
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                let parts = splitCodeBlocks(message.content)
                let hasCode = !isUser && parts.contains(where: { $0.isCode })
                
                if hasCode {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            if part.isCode {
                                CodeBlockView(code: part.content, language: part.language)
                            } else if !part.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                markdownText(part.content)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.secondary.opacity(0.1))
                    )
                } else {
                    markdownText(message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isUser ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                        )
                }
                
                if !isUser {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }) {
                        Label(copied ? "Copied!" : "Copy",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // User avatar
            if isUser {
                Image(systemName: "person.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            
            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
    }
    
    @ViewBuilder
    private func markdownText(_ text: String) -> some View {
        if !isUser, let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
                .textSelection(.enabled)
                .font(.body)
        } else {
            Text(text)
                .textSelection(.enabled)
                .font(.body)
        }
    }
    
    // MARK: - Code Block Splitting
    
    struct ContentPart {
        let content: String
        let isCode: Bool
        let language: String
    }
    
    func splitCodeBlocks(_ text: String) -> [ContentPart] {
        var parts: [ContentPart] = []
        let pattern = "```(\\w*)\\n?([\\s\\S]*?)```"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [ContentPart(content: text, isCode: false, language: "")]
        }
        
        let nsText = text as NSString
        var lastEnd = 0
        
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            if match.range.location > lastEnd {
                let before = nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(ContentPart(content: before, isCode: false, language: ""))
                }
            }
            let lang = match.numberOfRanges > 1 ? nsText.substring(with: match.range(at: 1)) : ""
            let code = match.numberOfRanges > 2 ? nsText.substring(with: match.range(at: 2)) : ""
            parts.append(ContentPart(content: code, isCode: true, language: lang))
            lastEnd = match.range.location + match.range.length
        }
        
        if lastEnd < nsText.length {
            let rem = nsText.substring(from: lastEnd)
            if !rem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(ContentPart(content: rem, isCode: false, language: ""))
            }
        }
        if parts.isEmpty {
            parts.append(ContentPart(content: text, isCode: false, language: ""))
        }
        return parts
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String
    @State private var copied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !language.isEmpty {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }) {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.35))
        )
    }
}

// MARK: - Keyboard Navigation Helper

/// An invisible NSView that captures ↑↓ arrow key events for session list navigation.
// MARK: - Safe Collection Subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
