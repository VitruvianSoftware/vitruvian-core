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
    private(set) var expectedKey: String = "g"
    private(set) var expectedModifiers: NSEvent.ModifierFlags = [.command, .shift]

    /// Human-readable shortcut string for display (e.g. "⌘⇧G")
    var hotkeyDisplayString: String {
        var parts = ""
        if expectedModifiers.contains(.control) { parts += "⌃" }
        if expectedModifiers.contains(.option)  { parts += "⌥" }
        if expectedModifiers.contains(.shift)   { parts += "⇧" }
        if expectedModifiers.contains(.command)  { parts += "⌘" }
        parts += expectedKey.uppercased()
        return parts
    }

    // Pin state — when pinned, clicks outside don't dismiss the window
    var isPinned: Bool = false {
        didSet {
            if isPinned {
                removeClickOutsideMonitor()
            } else {
                addClickOutsideMonitor()
            }
        }
    }

    // Spring-animated panel resize state
    private var resizeTimer: Timer?
    private var resizeVelocity: CGFloat = 0
    
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
    
    /// Spring-physics panel resize — grows/shrinks downward from the top edge.
    /// Uses a 120 Hz Euler integrator so the height follows true Hooke's law
    /// with overshoot, giving the same elastic feel as the open/close animation.
    func animateResize(expanded: Bool) {
        resizeTimer?.invalidate()
        resizeTimer = nil
        guard let window = window else { return }

        let compactHeight: CGFloat  = 72
        let expandedHeight: CGFloat = 340
        let targetHeight = expanded ? expandedHeight : compactHeight

        // Spring constants — snappy with a subtle overshoot
        let stiffness: CGFloat = 440
        let damping:   CGFloat = 26
        let dt:        CGFloat = 1.0 / 120.0

        var currentHeight = window.frame.height
        resizeVelocity = 0

        resizeTimer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self, weak window] t in
            guard let self, let window else { t.invalidate(); return }

            // Hooke's law: F = -k·x  minus  damping: F -= c·v
            let displacement = targetHeight - currentHeight
            let springForce  = stiffness * displacement
            let dampForce    = damping   * self.resizeVelocity
            self.resizeVelocity += (springForce - dampForce) * dt
            currentHeight       += self.resizeVelocity * dt

            // Anchor the TOP edge — grow/shrink downward only
            let f = window.frame
            let newY = f.origin.y + f.height - currentHeight
            window.setFrame(
                NSRect(x: f.origin.x, y: newY, width: f.width, height: currentHeight),
                display: true, animate: false
            )

            // Settle: snap to target when close enough
            if abs(displacement) < 0.4 && abs(self.resizeVelocity) < 0.4 {
                let ff = window.frame
                let finalY = ff.origin.y + ff.height - targetHeight
                window.setFrame(NSRect(x: ff.origin.x, y: finalY, width: ff.width, height: targetHeight), display: true)
                t.invalidate()
                self.resizeTimer = nil
            }
        }
    }

    /// Toggle the quick prompt window.
    func toggle() {
        if let window = window, window.isVisible {
            dismiss()
        } else {
            show()
        }
    }
    
    func show(startExpanded: Bool = false) {
        window?.orderOut(nil)
        window = nil
        createWindow(startExpanded: startExpanded)
        
        guard let window = window else { return }
        
        // Position: centered horizontally, upper-third of screen (like Spotlight)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 680
            let windowHeight: CGFloat = startExpanded ? 340 : 72   // compact: input bar only
            let x = screenFrame.midX - windowWidth / 2
            let y = screenFrame.maxY - windowHeight - (screenFrame.height * 0.18)
            window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: false)
        }

        // Start invisible; animateIn() will fade + spring it in
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        animateIn()
        
        // Force focus on the text field after spring settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let window = self?.window else { return }
            window.makeKey()
            if let textField = self?.findTextField(in: window.contentView) {
                window.makeFirstResponder(textField)
            }
        }
        
        // Click-outside-to-dismiss (Spotlight behavior) — only when not pinned
        if !isPinned {
            addClickOutsideMonitor()
        }
    }

    /// Spotlight Tahoe-style spring entrance: fade in + elastic scale bounce.
    private func animateIn() {
        guard let window = window, let layer = window.contentView?.layer else { return }

        // Pin anchor to center so the scale radiates from the middle of the panel.
        // Re-applying the frame after changing anchorPoint keeps the view in place.
        let savedFrame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = savedFrame

        // 1. Fade the window in quickly
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }

        // 2. Spring scale: 0.90 → slight overshoot → 1.0  (center outward)
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.90
        spring.toValue   = 1.0
        spring.stiffness = 500
        spring.damping   = 24
        spring.mass      = 1.0
        spring.initialVelocity = 0
        spring.duration  = spring.settlingDuration  // ~0.36s
        spring.isRemovedOnCompletion = true
        layer.add(spring, forKey: "spotlightBounce")
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
        guard let window = window else { return }
        removeClickOutsideMonitor()

        // Quick scale-down + fade-out, then hide
        guard let layer = window.contentView?.layer else {
            window.orderOut(nil)
            return
        }

        // Ensure collapse scales inward from center
        let savedFrame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = savedFrame

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue   = 0.0
        fadeOut.duration  = 0.16
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false

        let scaleOut = CABasicAnimation(keyPath: "transform.scale")
        scaleOut.fromValue = 1.0
        scaleOut.toValue   = 0.94
        scaleOut.duration  = 0.16
        scaleOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        scaleOut.fillMode = .forwards
        scaleOut.isRemovedOnCompletion = false

        layer.add(fadeOut,  forKey: "dismissFade")
        layer.add(scaleOut, forKey: "dismissScale")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }
    
    private func createWindow(startExpanded: Bool = false) {
        let promptView = QuickPromptView(startExpanded: startExpanded, onSubmit: { [weak self] prompt in
            self?.runPrompt(prompt)
        }, onResume: { [weak self] sessionIndex, sessionUUID in
            self?.resumeSession(sessionIndex, uuid: sessionUUID)
        }, onDismiss: { [weak self] in
            self?.dismiss()
        })
        
        // Spotlight-style panel: no title bar, no chrome
        let panel = QuickPromptPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: startExpanded ? 340 : 72),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
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

        // Use a plain transparent container as contentView. macOS draws its
        // NSThemeFrame border around whatever is set as contentView directly;
        // by making it a clear passthrough NSView, we avoid any rectangular
        // ghost outline being painted around the panel edges.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 72))
        container.wantsLayer = true
        container.layer?.backgroundColor = CGColor.clear
        container.autoresizingMask = [.width, .height]

        // Spotlight-style vibrancy material — rounded, clipped
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.frame = container.bounds
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 22
        visualEffect.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: promptView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = CGColor.clear
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = visualEffect.bounds

        visualEffect.addSubview(hosting)
        container.addSubview(visualEffect)
        panel.contentView = container

        // Invalidate shadow so it redraws shaped to the rounded content
        // rather than the rectangular window frame.
        panel.invalidateShadow()

        self.window = panel
        self.hostingView = hosting

        // #10: ⌘W dismisses the window (standard macOS convention)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, event.charactersIgnoringModifiers == "w" {
                self?.dismiss()
                return nil
            }
            return event
        }
    }
    
    private func runPrompt(_ prompt: String) {
        expandAndShowChat(QuickPromptChatView(initialPrompt: prompt, resumeIndex: nil, resumeUUID: nil))
    }
    
    private func resumeSession(_ index: Int, uuid: String) {
        expandAndShowChat(QuickPromptChatView(initialPrompt: nil, resumeIndex: index, resumeUUID: uuid))
    }
    
    private func expandAndShowChat(_ chatView: QuickPromptChatView) {
        guard let window = window else { return }
        
        // #11: Allow resizing in chat mode
        window.minSize = NSSize(width: 480, height: 300)
        window.maxSize = NSSize(width: 900, height: 800)
        window.styleMask.insert(.resizable)
        
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

        // Same transparent container pattern as createWindow to avoid
        // ghost rectangle borders from macOS NSThemeFrame rendering.
        let container = NSView(frame: NSRect(origin: .zero, size: targetSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = CGColor.clear
        container.autoresizingMask = [.width, .height]

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.frame = container.bounds
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 22
        visualEffect.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: chatView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = CGColor.clear
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = visualEffect.bounds
        visualEffect.addSubview(hosting)
        container.addSubview(visualEffect)

        window.contentView = container
        window.invalidateShadow()
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
    init(startExpanded: Bool = false, onSubmit: @escaping (String) -> Void, onResume: @escaping (Int, String) -> Void, onDismiss: @escaping () -> Void) {
        self.onSubmit = onSubmit
        self.onResume = onResume
        self.onDismiss = onDismiss
        self._showSessions = State(initialValue: startExpanded)
    }

    let onSubmit: (String) -> Void
    let onResume: (Int, String) -> Void
    let onDismiss: () -> Void
    @State private var prompt: String = ""
    @State private var sessions: [SessionInfo] = []
    @State private var loadingSessions = false
    @State private var showSessions = false
    @State private var hoveredSessionId: Int? = nil
    @State private var selectedSessionIndex: Int? = nil
    @State private var sparklePulse = false
    @FocusState private var isFocused: Bool
    
    @State private var isHoveringInput = false
    @State private var showingCommandHints = false
    @State private var commandKeyMonitor: Any?
    
    private var showActionButtons: Bool {
        return isHoveringInput || showSessions
    }
    
    private var contextualPlaceholder: String {
        if showSessions {
            return "Filter sessions…"
        }
        if let config = ConfigManager.shared {
            let providerName = config.activeProvider.name.components(separatedBy: " ").first ?? "NexusAgent"
            return "Ask \(providerName) anything…"
        }
        return "Ask NexusAgent anything…"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Quick Prompt Input Row ──
            HStack(spacing: 8) {
                // ── Text Input Bar (clean, pure text zone) ──
                HStack(spacing: 12) {
                    // #2: Gentle pulse on sparkle icon when idle
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.linearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .opacity(prompt.isEmpty && sparklePulse ? 0.5 : 1.0)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: sparklePulse)
                        .onAppear { sparklePulse = true }
                    
                    TextField(contextualPlaceholder, text: $prompt)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .regular))
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
                        .overlay(alignment: .trailing) {
                            if showingCommandHints {
                                Text(QuickPromptWindowController.shared.hotkeyDisplayString)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.secondary.opacity(0.12))
                                    )
                                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }
                        }
                        .animation(.easeInOut(duration: 0.15), value: showingCommandHints)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                
                // ── Modular Action Buttons (Animate in/out) ──
                if showActionButtons {
                    HStack(spacing: 8) {
                        modularActionButton(
                            icon: showSessions ? "clock.fill" : "clock",
                            isActive: showSessions,
                            help: "Recent sessions"
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showSessions.toggle()
                            }
                            selectedSessionIndex = nil
                            // Clear filter text when closing sessions panel
                            if !showSessions {
                                prompt = ""
                            }
                            QuickPromptWindowController.shared.animateResize(expanded: showSessions)
                            if showSessions && sessions.isEmpty {
                                loadingSessions = true
                                loadSessions()
                            }
                        }
                        
                        if let config = ConfigManager.shared {
                             modularProviderButton(config: config)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                        removal: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.8))
                    ))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .clipped()
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showActionButtons)
            .onHover { hovering in
                isHoveringInput = hovering
            }
            
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
                } else if displayedSessions.isEmpty {
                    // Filter produced no results
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(.quaternary)
                        Text("No matching sessions")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(filterActive ? "\(displayedSessions.count) result\(displayedSessions.count == 1 ? "" : "s")" : "Recent")
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
            setupCommandKeyMonitor()
            if showSessions && sessions.isEmpty {
                loadingSessions = true
                loadSessions()
            }
        }
        .onDisappear {
            removeKeyboardMonitor()
            removeCommandKeyMonitor()
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
        let base = Array(sessions.prefix(10))
        // Filter sessions by prompt text when the sessions panel is open
        if showSessions && !prompt.trimmingCharacters(in: .whitespaces).isEmpty {
            let query = prompt.lowercased()
            return base.filter { $0.title.lowercased().contains(query) }
        }
        return base
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
    
    // MARK: - Command Key Monitor & Helpers
    
    private func setupCommandKeyMonitor() {
        commandKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            let isCommand = event.modifierFlags.contains(.command)
            if showingCommandHints != isCommand {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showingCommandHints = isCommand
                }
            }
            return event
        }
    }

    private func removeCommandKeyMonitor() {
        if let monitor = commandKeyMonitor {
            NSEvent.removeMonitor(monitor)
            commandKeyMonitor = nil
        }
    }
    
    // MARK: - Modular Action Buttons

    private func modularActionButton(
        icon: String,
        isActive: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        ModularButtonView(icon: icon, isActive: isActive, help: help, action: action)
    }

    private func modularProviderButton(config: ConfigManager) -> some View {
        ModularProviderButtonView(config: config)
    }

    private var filterActive: Bool {
        showSessions && !prompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Animate the underlying NSPanel between compact (input-only) and expanded (sessions) heights.
    // Resize is now handled by QuickPromptWindowController.animateResize(expanded:)

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
    
    /// Finds the active NVM node version directory (e.g. "v22.14.0") by reading ~/.nvm/alias/default.
    static func findNVMNodeVersion() -> String {
        let nvmAlias = "\(NSHomeDirectory())/.nvm/alias/default"
        if let version = try? String(contentsOfFile: nvmAlias, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) {
            // Resolve the alias recursively (e.g. "lts/iron" → actual version)
            let versionsDir = "\(NSHomeDirectory())/.nvm/versions/node"
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: versionsDir) {
                // Find a version matching the alias prefix
                let match = versions.first { $0.hasPrefix(version) || version.hasPrefix($0) }
                return match ?? version
            }
            return version
        }
        return ""
    }
}

// MARK: - Modular Button Views (with hover feedback)

/// A circular action button with hover highlight, used outside the input bar.
struct ModularButtonView: View {
    let icon: String
    let isActive: Bool
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? Color.blue : Color.primary.opacity(isHovered ? 0.7 : 0.45))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .background(
                    Circle()
                        .strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.1), lineWidth: 0.5)
                )
                .scaleEffect(isHovered ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .help(help)
        .contentShape(Circle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// A circular provider-picker button with hover highlight.
struct ModularProviderButtonView: View {
    @ObservedObject var config: ConfigManager
    @State private var isHovered = false

    var body: some View {
        Menu {
            ForEach(config.providers) { provider in
                Button(action: {
                    config.activeProviderId = provider.id
                    config.saveProviders()
                }) {
                    HStack {
                        Text(provider.name)
                        if config.activeProviderId == provider.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "cpu")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(isHovered ? 0.7 : 0.45))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .background(
                    Circle()
                        .strokeBorder(Color.primary.opacity(isHovered ? 0.18 : 0.1), lineWidth: 0.5)
                )
                .scaleEffect(isHovered ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch provider: \(config.activeProvider.name)")
        .contentShape(Circle())
        .onHover { hovering in
            isHovered = hovering
        }
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

// MARK: - Stream File Watcher

// TODO_GEMINI_HOOKS: The following StreamFileWatcher and GEMINI_STREAM_FILE integration relies on
// Gemini CLI hooks (AfterModel, BeforeTool, AfterTool, AfterAgent) which are NOT available in
// any published release as of gemini v0.35.1. Hooks exist only in the upstream main branch.
// When a new gemini release includes hooks support, verify:
//   1. GEMINI_STREAM_FILE env var is passed through to hook scripts
//   2. ~/.gemini/settings.json hooks config is loaded (see TODO.md in project root)
//   3. AfterModel fires per-chunk with llm_response.candidates[].content.parts[]
//   4. AfterAgent fires with prompt_response string
// See also: hooks/stream-hook.py and TODO.md

/// Watches a JSONL file for new events written by the Gemini CLI hook.
/// Uses DispatchSource to detect file writes and reads new lines incrementally.
class StreamFileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileHandle: FileHandle?
    private var offset: UInt64 = 0
    private let filePath: String
    private let onEvent: (StreamEvent) -> Void
    
    enum StreamEvent {
        case chunk(String)          // Model text token
        case thinking(String)       // Model thinking/reasoning
        case toolStart(String, String)  // Tool name, summary
        case toolDone(String)       // Tool name
        case done(String)           // Final full response
    }
    
    init(filePath: String, onEvent: @escaping (StreamEvent) -> Void) {
        self.filePath = filePath
        self.onEvent = onEvent
    }
    
    func start() {
        // Create the file if it doesn't exist
        FileManager.default.createFile(atPath: filePath, contents: nil)
        
        guard let fh = FileHandle(forReadingAtPath: filePath) else { return }
        self.fileHandle = fh
        self.offset = 0
        
        let fd = fh.fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        
        source.setEventHandler { [weak self] in
            self?.readNewLines()
        }
        
        source.setCancelHandler { [weak self] in
            self?.fileHandle?.closeFile()
            self?.fileHandle = nil
        }
        
        self.source = source
        source.resume()
    }
    
    func stop() {
        source?.cancel()
        source = nil
        // Clean up the stream file
        try? FileManager.default.removeItem(atPath: filePath)
    }
    
    private func readNewLines() {
        guard let fh = fileHandle else { return }
        
        fh.seek(toFileOffset: offset)
        let data = fh.readDataToEndOfFile()
        guard !data.isEmpty else { return }
        offset = fh.offsetInFile
        
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }
            
            switch type {
            case "chunk":
                if let text = json["text"] as? String {
                    onEvent(.chunk(text))
                }
            case "thinking":
                if let text = json["text"] as? String {
                    onEvent(.thinking(text))
                }
            case "tool_start":
                let tool = json["tool"] as? String ?? "unknown"
                let summary = json["summary"] as? String ?? ""
                onEvent(.toolStart(tool, summary))
            case "tool_done":
                let tool = json["tool"] as? String ?? "unknown"
                onEvent(.toolDone(tool))
            case "done":
                let response = json["response"] as? String ?? ""
                onEvent(.done(response))
            default:
                break
            }
        }
    }
    
    deinit {
        stop()
    }
}

// MARK: - Chat Conversation View

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String
    var content: String
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
    @State private var promptHistory: [String] = UserDefaults.standard.stringArray(forKey: "promptHistory") ?? []
    @State private var historyIndex: Int = -1
    @State private var streamingStatus: String = "Thinking…"
    @State private var streamWatcher: StreamFileWatcher?
    @State private var isPinned: Bool = false
    @State private var isNearBottom: Bool = true
    @State private var typingDotPhase: Int = 0
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                // #8: Sparkles icon matches the prompt bar branding
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Text("Chat")
                    .font(.system(size: 16, weight: .medium))

                // Subtle active provider badge
                if let config = ConfigManager.shared {
                    let providerName = config.activeProvider.name
                    Text(providerName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.1))
                        )
                }

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
                    QuickPromptWindowController.shared.show(startExpanded: true)
                }) {
                    Image(systemName: "clock") // or "list.bullet"
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Recent sessions")
                
                Button(action: {
                    isPinned.toggle()
                    QuickPromptWindowController.shared.isPinned = isPinned
                }) {
                    Image(systemName: isPinned
                          ? "pin.circle.fill" : "pin.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isPinned ? Color.blue : Color.secondary.opacity(0.5))
                        .rotationEffect(.degrees(isPinned ? 0 : 45))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPinned)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin window" : "Pin window")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 12)
            
            // Messages
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            // #4: Empty state when no messages yet and loading
                            if messages.isEmpty && isLoading {
                                VStack(spacing: 12) {
                                    ForEach(0..<3, id: \.self) { i in
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.primary.opacity(0.05))
                                            .frame(height: i == 1 ? 40 : 20)
                                            .frame(maxWidth: i == 2 ? 200 : .infinity)
                                            .shimmer()
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                            }

                            ForEach(messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                            
                            // #7: Typing indicator dots
                            if isLoading {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(Color.blue.opacity(0.15)))

                                    HStack(spacing: 4) {
                                        ForEach(0..<3, id: \.self) { i in
                                            Circle()
                                                .fill(Color.blue.opacity(0.6))
                                                .frame(width: 6, height: 6)
                                                .scaleEffect(typingDotPhase == i ? 1.3 : 0.7)
                                                .animation(
                                                    .easeInOut(duration: 0.4)
                                                        .repeatForever(autoreverses: true)
                                                        .delay(Double(i) * 0.15),
                                                    value: typingDotPhase
                                                )
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color.secondary.opacity(0.1))
                                    )

                                    Text(streamingStatus)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
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
                                .onAppear { typingDotPhase = 1 }
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

                            // Invisible anchor for scroll-to-bottom
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.vertical, 12)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geo.frame(in: .named("chatScroll")).maxY
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "chatScroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                        isNearBottom = maxY < 600
                    }
                    .onChange(of: messages) { _ in
                        if isNearBottom {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isLoading) { loading in
                        if loading && isNearBottom {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }

                    // #15: Scroll-to-bottom floating button
                    if !isNearBottom {
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.caption2.weight(.bold))
                                Text("New messages")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // #3: Follow-up input (consistent styling)
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.message")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                
                TextField("Follow up…", text: $followUp)
                    .textFieldStyle(.plain)
                    .font(.callout)
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        // #9: Esc dismisses the chat view
        .onExitCommand { QuickPromptWindowController.shared.dismiss() }
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
        // #13: Persist prompt history (capped at 20 entries)
        let capped = Array(promptHistory.suffix(20))
        UserDefaults.standard.set(capped, forKey: "promptHistory")
        historyIndex = -1
        followUp = ""
        Task { await sendToCLI(text) }
    }
    
    private func stopGeneration() {
        currentProcess?.terminate()
        currentProcess = nil
        streamWatcher?.stop()
        streamWatcher = nil
        isLoading = false
        streamingStatus = "Thinking…"
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
        streamingStatus = "Thinking…"

        // Determine which provider is active
        let provider = ConfigManager.shared?.activeProvider ?? CLIProvider.gemini
        let isGemini = provider.id == CLIProvider.gemini.id

        if isGemini {
            await runGeminiProvider(prompt: prompt)
        } else {
            await runCustomProvider(prompt: prompt, provider: provider)
        }
    }

    /// Existing Gemini CLI path — unchanged, keeps JSON parsing + stream hooks + session resume.
    private func runGeminiProvider(prompt: String) async {
        // Create a unique stream file for this request
        let streamId = UUID().uuidString.prefix(8)
        let streamFilePath = "/tmp/gemini-stream-\(streamId).jsonl"
        FileManager.default.createFile(atPath: streamFilePath, contents: nil)
        
        // Track whether we received any streaming events
        var receivedStreamEvents = false
        // Index of the assistant message we're streaming into
        var streamingMessageIndex: Int? = nil
        
        // Start watching the stream file
        let watcher = StreamFileWatcher(filePath: streamFilePath) { [self] event in
            DispatchQueue.main.async {
                receivedStreamEvents = true
                switch event {
                case .chunk(let text):
                    if let idx = streamingMessageIndex {
                        // Append to existing streaming message
                        messages[idx].content += text
                    } else {
                        // Create new assistant message
                        messages.append(ChatMessage(role: "assistant", content: text))
                        streamingMessageIndex = messages.count - 1
                    }
                    streamingStatus = "Generating…"
                    
                case .thinking(let text):
                    _ = text  // Could display in UI later
                    streamingStatus = "Reasoning…"
                    
                case .toolStart(let tool, let summary):
                    let displayName = tool
                        .replacingOccurrences(of: "_", with: " ")
                        .prefix(1).uppercased() + tool
                        .replacingOccurrences(of: "_", with: " ")
                        .dropFirst()
                    if summary.isEmpty {
                        streamingStatus = "Running \(displayName)…"
                    } else {
                        streamingStatus = "\(displayName): \(summary.prefix(60))"
                    }
                    
                case .toolDone(_):
                    streamingStatus = "Thinking…"
                    
                case .done(_):
                    // Agent completed — streaming is done
                    streamingStatus = "Done"
                }
            }
        }
        watcher.start()
        self.streamWatcher = watcher
        
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
        // Augment PATH — macOS apps launched from /Applications get a stripped PATH
        // that may not include Homebrew or NVM. Prepend common node/gemini locations.
        let nmvNodeBin: String = {
            let alias = (try? String(contentsOfFile: "\(NSHomeDirectory())/.nvm/alias/default", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let versionsDir = "\(NSHomeDirectory())/.nvm/versions/node"
            let versions = (try? FileManager.default.contentsOfDirectory(atPath: versionsDir)) ?? []
            let match = versions.first { $0.hasPrefix(alias) || alias.hasPrefix($0) } ?? alias
            return "\(versionsDir)/\(match)/bin"
        }()
        let extraPaths = [
            "/opt/homebrew/bin",          // Apple Silicon Homebrew
            "/usr/local/bin",             // Intel Homebrew
            nmvNodeBin,                   // NVM active node version
            "\(NSHomeDirectory())/.volta/bin",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        let currentPath = process.environment?["PATH"] ?? "/usr/bin:/bin"
        process.environment?["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        // TODO_GEMINI_HOOKS: GEMINI_STREAM_FILE is passed to the CLI so the stream-hook.py
        // can write events to it. This will only work once hooks are in a published gemini release.
        process.environment?["GEMINI_STREAM_FILE"] = streamFilePath
        let workDir = QuickPromptView.resolveWorkingDirectory()
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
            
            // Give the watcher a moment to process any remaining events
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            currentProcess = nil
            watcher.stop()
            self.streamWatcher = nil
            
            if status == 15 || status == 9 {
                error = "Generation stopped"
            } else if status != 0 && output.isEmpty {
                error = stderr.isEmpty
                    ? "CLI exited with code \(status)"
                    : String(stderr.prefix(300))
            } else if !receivedStreamEvents {
                // Fallback: hooks didn't fire, use the full JSON output
                if output.isEmpty {
                    error = "Empty response from Gemini"
                } else {
                    let parsed = parseGeminiJSON(output)
                    messages.append(ChatMessage(role: "assistant", content: parsed.text ?? output))
                }
            }
            // If we received stream events, the message is already built
            hasActiveSession = true
            isLoading = false
            streamingStatus = "Thinking…"
            // #16: Subtle sound on completion
            if error == nil { NSSound(named: "Tink")?.play() }
        } catch {
            currentProcess = nil
            watcher.stop()
            self.streamWatcher = nil
            self.error = error.localizedDescription
            isLoading = false
            streamingStatus = "Thinking…"
        }
    }

    // MARK: - Custom Provider Runner

    /// Run any non-Gemini provider by parsing its command template into an argv array
    /// and spawning directly via Process (never via shell). Streams stdout to the UI in real-time.
    private func runCustomProvider(prompt: String, provider: CLIProvider) async {
        let model = ConfigManager.shared?.model ?? ""
        guard let (executable, args) = parseProviderTemplate(provider.commandTemplate, prompt: prompt, model: model) else {
            error = "Invalid command template: \(provider.commandTemplate)"
            isLoading = false
            return
        }

        // Resolve the executable to a full path — Process requires an absolute path,
        // it does NOT search PATH automatically unlike a shell invocation.
        guard let resolvedExecutable = resolveExecutablePath(executable) else {
            error = "Could not find '\(executable)' in PATH. Is it installed?"
            isLoading = false
            return
        }

        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        let extraPaths = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let augmentedPath = (extraPaths + [currentPath]).joined(separator: ":")

        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = errPipe
        process.environment = ProcessInfo.processInfo.environment
        process.environment?["NO_COLOR"] = "1"
        process.environment?["PATH"] = augmentedPath

        let workDir = QuickPromptView.resolveWorkingDirectory()
        process.currentDirectoryURL = FileManager.default.fileExists(atPath: workDir.path)
            ? workDir : URL(fileURLWithPath: NSHomeDirectory())

        currentProcess = process

        // QuickPromptChatView is a SwiftUI struct — [weak self] is invalid in struct closures.
        // We accumulate stdout chunks via readabilityHandler and resolve the full text
        // via withCheckedContinuation, then update @State on the main actor after exit.
        do {
            try process.run()

            let (output, stderr, status) = await withCheckedContinuation { continuation in
                var chunks: [Data] = []
                var errChunks: [Data] = []
                let group = DispatchGroup()
                group.enter()

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        // EOF — stop handler before signalling done
                        handle.readabilityHandler = nil
                        group.leave()
                    } else {
                        chunks.append(data)
                        // Update streaming status on main
                        if let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty {
                            DispatchQueue.main.async {
                                // Post a notification so the view's .onReceive can pick it up
                                NotificationCenter.default.post(
                                    name: Notification.Name("ProviderChunk"),
                                    object: chunk
                                )
                            }
                        }
                    }
                }

                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty { errChunks.append(data) }
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    // Drain any remaining data
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                    if !remaining.isEmpty { chunks.append(remaining) }

                    let out = String(data: Data(chunks.joined()), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let err = String(data: Data(errChunks.joined()), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: (out, err, process.terminationStatus))
                }
            }

            currentProcess = nil

            if status == 15 || status == 9 {
                error = "Generation stopped"
            } else if status != 0 && output.isEmpty {
                error = stderr.isEmpty ? "Process exited with code \(status)" : String(stderr.prefix(300))
            } else if !output.isEmpty {
                messages.append(ChatMessage(role: "assistant", content: output))
            } else {
                error = "No output from provider"
            }

            isLoading = false
            streamingStatus = "Thinking…"
            // #16: Subtle sound on completion
            if error == nil { NSSound(named: "Tink")?.play() }
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            currentProcess = nil
            self.error = error.localizedDescription
            isLoading = false
            streamingStatus = "Thinking…"
        }
    }


    // MARK: - Template Parser

    /// Parse a provider command template into (executable, [args]) by tokenising
    /// the string and substituting {prompt} and {model} as verbatim literal values.
    /// Supports single and double quoted tokens. Returns nil if the template is empty.
    private func parseProviderTemplate(_ template: String, prompt: String, model: String) -> (String, [String])? {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        let chars = Array(template)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if c == "'" && !inDouble {
                inSingle.toggle()
            } else if c == "\"" && !inSingle {
                inDouble.toggle()
            } else if c == " " && !inSingle && !inDouble {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(c)
            }
            i += 1
        }
        if !current.isEmpty { tokens.append(current) }

        guard !tokens.isEmpty else { return nil }

        let activeModel = model.isEmpty ? "gemma4:31b-cloud" : model
        let resolved = tokens.map { token in
            token
                .replacingOccurrences(of: "{prompt}", with: prompt)
                .replacingOccurrences(of: "{model}", with: activeModel)
        }

        return (resolved[0], Array(resolved.dropFirst()))
    }

    // MARK: - Executable Resolution

    /// Resolve a bare command name (e.g. "ollama") to its full absolute path
    /// by searching the augmented PATH. Process requires an absolute path —
    /// it does NOT search PATH automatically unlike a shell invocation.
    private func resolveExecutablePath(_ name: String) -> String? {
        // Already absolute — verify it exists
        if name.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: name) ? name : nil
        }
        let extraDirs = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var seen = Set<String>()
        let searchDirs = (extraDirs + envPath.split(separator: ":").map(String.init))
            .filter { seen.insert($0).inserted }
        for dir in searchDirs {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
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
    @State private var hovering = false
    
    var isUser: Bool { message.role == "user" }
    
    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
    
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
                
                // #5: Enhanced visual hierarchy
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
                            .fill(Color.secondary.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.blue.opacity(0.12), lineWidth: 1)
                            )
                    )
                } else {
                    markdownText(message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: isUser ? 18 : 14)
                                .fill(
                                    isUser
                                        ? AnyShapeStyle(.linearGradient(
                                            colors: [Color.blue.opacity(0.22), Color.indigo.opacity(0.18)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Color.secondary.opacity(0.08))
                                )
                                .overlay(
                                    !isUser
                                        ? AnyView(RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color.blue.opacity(0.08), lineWidth: 0.5))
                                        : AnyView(EmptyView())
                                )
                        )
                }
                
                // #14: Copy button — visible on hover for assistant messages
                if !isUser {
                    Button(action: copyContent) {
                        Label(copied ? "Copied!" : "Copy",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(hovering || copied ? 1 : 0)
                }
            }
            // #14: Double-click to copy any message
            .onTapGesture(count: 2) { copyContent() }
            
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
        .onHover { hovering = $0 }
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
            
            // #12: Fixed-width monospaced text — wraps instead of horizontal scroll
            // to avoid text selection conflicts
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // #6: Adaptive background that works in both light and dark mode
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                )
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

// MARK: - Scroll Offset Preference Key (#15)

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Shimmer Effect (#4)

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.primary.opacity(0.06),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 400
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
