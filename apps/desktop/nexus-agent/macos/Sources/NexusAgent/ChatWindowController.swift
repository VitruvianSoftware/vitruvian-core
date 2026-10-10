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
import AppKit
import Carbon.HIToolbox
import Combine

import NexusAgentCore
import NexusAgentUI

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

// MARK: - Backdrop

/// What is drawn behind the chat: the popover material this app's chat
/// window has always had, blurring whatever is under the panel. It is the
/// dark material whatever the system's appearance, because the panel is
/// always dark (see `ensureWindow`).
private struct ChatBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        // Rounded and clipped like the chat itself, so the material leaves
        // no square outline outside the panel's corners.
        view.wantsLayer = true
        view.layer?.cornerRadius = NexusAgentQuickPromptLayout.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Window Controller

/// The floating, Spotlight-style panel the chat lives in, and the global
/// hotkey that summons it. The chat itself is the shared `NexusAgentChatView`
/// on the app's one engine; this class only owns what is the window's: where
/// it is, how big it is for the chat's mode, the keys that close it, the pin,
/// and the click outside that dismisses it.
///
/// The panel and the chat view are built once and kept. Dismissing hides the
/// panel, so the conversation is still there the next time it is shown.
@MainActor
final class QuickPromptWindowController: NSObject, NSWindowDelegate {
    static let shared = QuickPromptWindowController()

    private typealias Layout = NexusAgentQuickPromptLayout

    private(set) var window: NSPanel?
    private var hostingView: NSHostingView<NexusAgentChatView>?
    /// The app's one engine, handed over at launch (`configure`). Until then
    /// there is no chat to show and `show()` does nothing.
    private var engine: StandaloneEngine?
    private var modeObserver: AnyCancellable?

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    /// True once `registerHotkey()` has been called. A change of key in
    /// Settings re-registers the hotkey only then, so nothing that merely
    /// saves settings can claim a system-wide key by itself.
    private var hotkeyIsLive = false

    // Configurable hotkey (defaults to ⌘+Shift+G)
    private var expectedKey: String = "g"
    private var expectedModifiers: NSEvent.ModifierFlags = [.command, .shift]

    // Pin state — when pinned, clicks outside don't dismiss the window
    var isPinned: Bool = false {
        didSet {
            if isPinned {
                removeClickOutsideMonitor()
            } else if isChatVisible {
                addClickOutsideMonitor()
            }
            // The chat reads the pin when it is drawn and is not told when
            // it changes, so it is handed its chrome again.
            if let engine { hostingView?.rootView = chatView(for: engine) }
        }
    }

    // Spring-animated panel resize state
    private var resizeTimer: Timer?
    private var resizeVelocity: CGFloat = 0
    private var resizeProgress: CGFloat = 0
    private var resizeStart: NSRect = .zero
    private var resizeTarget: NSRect = .zero

    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var clickOutsideMonitor: Any?

    /// True from `dismiss()` until its short fade is over and the panel is
    /// off screen. The chat counts as hidden from the start of it.
    private var isDismissing = false
    /// Counts dismissals and shows, so the end of a fade that a later
    /// `show()` overtook does not hide the panel again.
    private var presentation = 0

    private override init() {
        let savedKey = UserDefaults.standard.string(forKey: "hotkeyKey") ?? "g"
        let savedMods = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        expectedKey = savedKey
        if savedMods != 0 {
            expectedModifiers = NSEvent.ModifierFlags(rawValue: UInt(savedMods))
        }
        super.init()
    }

    /// Hands over the engine whose chat the panel shows. Called once at
    /// launch, when the engine exists. From then on the engine is told the
    /// truth about whether its chat is on screen, which decides whether a
    /// finished turn is announced with a notification.
    func configure(engine: StandaloneEngine) {
        self.engine = engine
        engine.chatIsVisible = { [weak self] in self?.isChatVisible ?? false }
    }

    /// Whether the user can see the chat right now.
    var isChatVisible: Bool {
        window?.isVisible == true && !isDismissing
    }

    // MARK: - Hotkey

    /// Register the global hotkey using Carbon API (with fallback only if registration fails).
    func registerHotkey() {
        hotkeyIsLive = true
        registerCarbonHotkey()
        // Only attach an OS-wide key monitor if native Carbon registration failed,
        // preventing continuous wakeups on every keystroke across macOS.
        if hotkeyRef == nil && globalKeyMonitor == nil {
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleNSEvent(event)
            }
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
        guard hotkeyIsLive else { return }
        unregisterCarbonHotkey()
        registerCarbonHotkey()
        if hotkeyRef == nil && globalKeyMonitor == nil {
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleNSEvent(event)
            }
        } else if hotkeyRef != nil, let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
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
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
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

    // MARK: - The panel and the chat in it

    /// The chat as this app shows it: the shared view on the app's engine,
    /// with its English text, this window's backdrop and pin, and Clear All
    /// in the sessions drawer. There is no notch here to dock into.
    private func chatView(for engine: StandaloneEngine) -> NexusAgentChatView {
        NexusAgentChatView(
            engine: engine,
            strings: NexusAgentChatStrings(),
            chrome: NexusAgentChatChrome(
                backdrop: AnyView(ChatBackdrop()),
                isPinned: Binding(get: { [weak self] in self?.isPinned ?? false },
                                  set: { [weak self] in self?.isPinned = $0 }),
                // The folder picker counts as a click outside the panel,
                // which hides it; this brings it back.
                showWindow: { [weak self] in self?.show() },
                offersClearAll: true))
    }

    /// The screen a fresh panel opens on: the one with the keyboard focus,
    /// as it has always been.
    private var screenFrame: NSRect {
        NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Builds the panel and the chat view the first time, and returns the
    /// same ones ever after. Nothing is put on screen.
    private func ensureWindow() -> NSPanel? {
        if let window { return window }
        guard let engine else { return nil }
        let mode = engine.session.mode
        let size = Layout.size(for: mode)

        // Spotlight-style panel: no title bar, no chrome
        let panel = QuickPromptPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        // Always dark, also when the Mac is in the light appearance. The
        // shared chat draws its cards, borders and secondary text for a dark
        // surface (Vitruvian's is dark in both appearances); on the light
        // material the timestamps and the stats line were close to
        // unreadable. A menu opened from the panel is dark too.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self

        // Use a plain transparent container as contentView. macOS draws its
        // NSThemeFrame border around whatever is set as contentView directly;
        // by making it a clear passthrough NSView, we avoid any rectangular
        // ghost outline being painted around the panel edges.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = CGColor.clear
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: chatView(for: engine))
        // The panel's size is set here, for the chat's mode; the view is not
        // to push its own onto the window.
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = CGColor.clear
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = container.bounds
        container.addSubview(hosting)
        panel.contentView = container

        self.window = panel
        self.hostingView = hosting
        apply(mode, to: panel, frame: Layout.initialFrame(for: mode, screen: screenFrame), animated: false)

        // Pill, drawer and chat each have their own size; the panel follows.
        // The publisher fires just before the session takes the new mode,
        // and hands it over.
        modeObserver = engine.session.$mode.removeDuplicates().dropFirst().sink { [weak self] mode in
            self?.modeChanged(to: mode)
        }
        return panel
    }

    private func modeChanged(to mode: NexusAgentQuickPromptMode) {
        guard let window else { return }
        let screen = window.screen?.visibleFrame ?? screenFrame
        // Measured from where the panel is going, if it is still on its way.
        let current = resizeTimer == nil ? window.frame : resizeTarget
        apply(mode, to: window, frame: Layout.frame(for: mode, from: current, screen: screen),
              animated: isChatVisible)
        // Only a conversation on show is followed in its transcript. The
        // session still holds the old mode at this moment, so this waits
        // one turn of the main queue.
        DispatchQueue.main.async { [weak self] in self?.followTranscriptIfOnShow() }
    }

    /// Follows the open conversation's transcript while the chat shows it,
    /// and stops when it does not: behind the drawer, or with the panel away.
    private func followTranscriptIfOnShow() {
        guard let engine else { return }
        let session = engine.session
        if isChatVisible, session.mode == .chat, session.conversationID != nil {
            if !session.isFollowerActive {
                session.startTranscriptFollower(provider: engine.configuration.activeProvider)
            }
        } else if session.mode != .chat {
            session.stopTranscriptFollower()
        }
    }

    /// Sizes the panel for `mode`; only the conversation can be resized by hand.
    private func apply(_ mode: NexusAgentQuickPromptMode, to window: NSPanel, frame: NSRect, animated: Bool) {
        if Layout.isResizable(mode) {
            window.minSize = Layout.chatMinimumSize
            window.maxSize = Layout.chatMaximumSize
            window.styleMask.insert(.resizable)
        } else {
            window.styleMask.remove(.resizable)
        }
        resizeTimer?.invalidate()
        resizeTimer = nil
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.setFrame(frame, display: true, animate: false)
            window.invalidateShadow()
            return
        }
        animateResize(of: window, to: frame)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let mode = engine?.session.mode, Layout.isResizable(mode) else { return sender.frame.size }
        return NSSize(
            width: min(max(Layout.chatMinimumSize.width, frameSize.width), Layout.chatMaximumSize.width),
            height: min(max(Layout.chatMinimumSize.height, frameSize.height), Layout.chatMaximumSize.height))
    }

    /// Spring-physics panel resize, from the frame the panel has to `target`.
    /// Uses a 120 Hz Euler integrator so the frame follows true Hooke's law
    /// with overshoot, giving the same elastic feel as the open/close animation.
    /// The layout keeps the top edge where it is, so the panel grows and
    /// shrinks downward.
    private func animateResize(of window: NSPanel, to target: NSRect) {
        resizeStart = window.frame
        resizeTarget = target
        resizeProgress = 0
        resizeVelocity = 0
        resizeTimer = Timer.scheduledTimer(timeInterval: 1.0 / 120.0, target: self,
                                           selector: #selector(stepResize), userInfo: nil, repeats: true)
    }

    @objc private func stepResize() {
        guard let window else {
            resizeTimer?.invalidate()
            resizeTimer = nil
            return
        }
        // Spring constants — snappy with a subtle overshoot
        let stiffness: CGFloat = 440
        let damping:   CGFloat = 26
        let dt:        CGFloat = 1.0 / 120.0

        // Hooke's law: F = -k·x  minus  damping: F -= c·v, on the share of
        // the way covered (0 at the start, 1 at the target).
        let displacement = 1 - resizeProgress
        resizeVelocity += (stiffness * displacement - damping * resizeVelocity) * dt
        resizeProgress += resizeVelocity * dt

        // The furthest any edge has to travel, to judge "close enough" in points.
        let from = resizeStart, to = resizeTarget
        let reach = max(abs(to.minX - from.minX), abs(to.minY - from.minY),
                        abs(to.width - from.width), abs(to.height - from.height))

        // Settle: snap to target when close enough
        if abs(displacement) * reach < 0.4 && abs(resizeVelocity) * reach < 0.4 {
            resizeTimer?.invalidate()
            resizeTimer = nil
            window.setFrame(to, display: true)
            window.invalidateShadow()
            return
        }
        let p = resizeProgress
        window.setFrame(
            NSRect(x: from.minX + (to.minX - from.minX) * p,
                   y: from.minY + (to.minY - from.minY) * p,
                   width: max(1, from.width + (to.width - from.width) * p),
                   height: max(1, from.height + (to.height - from.height) * p)),
            display: true, animate: false)
        // Periodically refresh shadow during animation
        window.invalidateShadow()
    }

    // MARK: - Show, dismiss, toggle

    /// Toggle the quick prompt window.
    func toggle() {
        if isChatVisible {
            dismiss()
        } else {
            show()
        }
    }

    /// Everything `show()` does short of putting the panel on screen: the
    /// settings are read again, the panel and its chat exist, the panel is
    /// where and as big as it should be, and the caret is asked back into
    /// the prompt. `show()` is the only caller in the app.
    @discardableResult
    func prepareToShow(startExpanded: Bool = false) -> NSPanel? {
        guard let engine else { return nil }
        // A change made in Settings, or to `.env` by hand, is seen.
        engine.load()
        guard let window = ensureWindow() else { return nil }
        let session = engine.session
        // Asked to open on the recent sessions: only when there is nothing
        // else to show, so a conversation is never covered by the drawer.
        if startExpanded, session.mode == .compact {
            session.toggleSessions(configuration: engine.configuration)
        }
        // A fresh show opens where it always has: centred, in the upper
        // third of the screen (like Spotlight). A panel already on screen
        // stays where the user put it.
        if !isChatVisible || !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            apply(session.mode, to: window,
                  frame: Layout.initialFrame(for: session.mode, screen: screenFrame), animated: false)
        }
        session.focusSerial += 1
        return window
    }

    func show(startExpanded: Bool = false) {
        let wasVisible = isChatVisible
        guard let window = prepareToShow(startExpanded: startExpanded) else { return }
        // A fade-out still under way is overtaken.
        presentation += 1
        endDismissal(hiding: false)

        installKeyMonitor()
        // Start invisible; animateIn() will fade + spring it in
        if !wasVisible { window.alphaValue = 0 }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible { animateIn(window) }
        followTranscriptIfOnShow()

        // Click-outside-to-dismiss (Spotlight behavior) — only when not pinned
        if !isPinned {
            addClickOutsideMonitor()
        }
    }

    /// A scale about the middle of `layer`, whatever point the layer is
    /// anchored at, so the panel grows from and shrinks to its centre.
    private static func scale(_ factor: CGFloat, aboutCentreOf layer: CALayer) -> CATransform3D {
        let dx = (0.5 - layer.anchorPoint.x) * layer.bounds.width
        let dy = (0.5 - layer.anchorPoint.y) * layer.bounds.height
        var transform = CATransform3DMakeTranslation(dx, dy, 0)
        transform = CATransform3DScale(transform, factor, factor, 1)
        return CATransform3DTranslate(transform, -dx, -dy, 0)
    }

    /// Spotlight Tahoe-style spring entrance: fade in + elastic scale bounce.
    private func animateIn(_ window: NSPanel) {
        // 1. Fade the window in quickly
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
        guard let layer = window.contentView?.layer else { return }

        // 2. Spring scale: 0.90 → slight overshoot → 1.0  (center outward)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: Self.scale(0.90, aboutCentreOf: layer))
        spring.toValue   = NSValue(caTransform3D: CATransform3DIdentity)
        spring.stiffness = 500
        spring.damping   = 24
        spring.mass      = 1.0
        spring.initialVelocity = 0
        spring.duration  = spring.settlingDuration  // ~0.36s
        spring.isRemovedOnCompletion = true
        layer.add(spring, forKey: "spotlightBounce")
    }

    /// Hides the panel. The chat view, its conversation and a reply still
    /// arriving are all kept; the next `show()` brings them back.
    func dismiss() {
        guard let window, !isDismissing else { return }
        removeClickOutsideMonitor()
        removeKeyMonitor()
        engine?.session.stopTranscriptFollower()
        // A resize still springing lands at once.
        if resizeTimer != nil {
            resizeTimer?.invalidate()
            resizeTimer = nil
            window.setFrame(resizeTarget, display: false)
        }

        // Quick scale-down + fade-out, then hide
        guard window.isVisible, let layer = window.contentView?.layer else {
            window.orderOut(nil)
            return
        }
        isDismissing = true
        presentation += 1
        let dismissed = presentation

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue   = 0.0
        fadeOut.duration  = 0.16
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false

        let scaleOut = CABasicAnimation(keyPath: "transform")
        scaleOut.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        scaleOut.toValue   = NSValue(caTransform3D: Self.scale(0.94, aboutCentreOf: layer))
        scaleOut.duration  = 0.16
        scaleOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        scaleOut.fillMode = .forwards
        scaleOut.isRemovedOnCompletion = false

        layer.add(fadeOut,  forKey: "dismissFade")
        layer.add(scaleOut, forKey: "dismissScale")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, self.presentation == dismissed else { return }
            self.endDismissal(hiding: true)
        }
    }

    /// Ends the fade-out: the panel leaves the screen if it is to, and the
    /// faded, shrunk state is taken off the view, which is kept for next time.
    private func endDismissal(hiding: Bool) {
        if hiding { window?.orderOut(nil) }
        if let layer = window?.contentView?.layer {
            layer.removeAnimation(forKey: "dismissFade")
            layer.removeAnimation(forKey: "dismissScale")
        }
        isDismissing = false
    }

    /// Opens the conversation a notification was about (the notification
    /// carries its id). Usually that is the one the chat still holds, and
    /// showing the panel is all there is to do. Otherwise it is resumed from
    /// the active provider's list, if it is still there; if it is not, the
    /// panel is shown as it stands. A turn in flight in another conversation
    /// is never ended for this.
    func resumeSession(uuid: String) {
        show()
        guard let engine else { return }
        let session = engine.session
        if session.conversationID == uuid {
            // Back from behind the drawer, if that is where it was left.
            if session.mode == .sessions { session.toggleSessions(configuration: engine.configuration) }
            return
        }
        guard !session.isRunning else { return }
        session.refreshSessions(configuration: engine.configuration)
        guard let summary = session.sessions.first(where: { $0.id == uuid }) else { return }
        session.resume(summary, configuration: engine.configuration)
    }

    // MARK: - Keys and clicks

    /// The keys that are the window's and not the chat's, pressed while the
    /// panel has the keyboard: ⌘W hides it, ⌘N starts a new chat, and Esc
    /// closes the model name's editor if it is open, else stops the reply
    /// in flight when the conversation is on show, and hides the panel
    /// otherwise. Every other key is handed back for the chat (Return, the
    /// arrows, typing). Returns nil for a key it took.
    func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let window, let engine, event.window === window else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "n" {
            engine.session.newChat()
            return nil
        }
        let isEscape = event.keyCode == UInt16(kVK_Escape)
        let isCmdW = flags == .command && event.charactersIgnoringModifiers == "w"
        guard isEscape || isCmdW else { return event }
        if isEscape {
            // Mid-composition Esc belongs to the input method.
            if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            // The chat's part of the key comes first, and is the shared
            // session's to do. This monitor sees Esc before any field in
            // the chat does, so the editor could not close itself.
            if engine.session.pressEscape(stoppingReply: true) != .dismiss { return nil }
        }
        dismiss()
        return nil
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func addClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                self?.clickedOutside()
            }
        }
    }

    /// Whether a click outside the panel is being watched for. It is while
    /// the panel is shown unpinned, and at no other time.
    var watchesClicksOutside: Bool { clickOutsideMonitor != nil }

    /// A click landed outside the panel: the panel goes, as Spotlight's
    /// does, unless it is pinned or already away. This is all the monitor
    /// above does with a click.
    func clickedOutside() {
        guard !isPinned, window?.isVisible == true else { return }
        dismiss()
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
