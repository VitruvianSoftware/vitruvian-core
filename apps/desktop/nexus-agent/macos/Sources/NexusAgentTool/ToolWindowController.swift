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

import AppKit
import Carbon.HIToolbox
import Combine
import NexusAgentCore
import NexusAgentToolCore
import NexusAgentUI
import SwiftUI

/// Borderless panels refuse key status by default; the prompt needs it so
/// typing and Esc work without activating anything.
private final class QuickPromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// What the floating chat is drawn on: the Vitruvian app's HUD backdrop
/// (apps/desktop/vitruvian/Sources/Vitruvian/Design/HUDBackdrop.swift) in its
/// classic form, a behind-window material with continuous corners and a
/// hairline of white at 12% inside the edge. The radius is the layout's,
/// which the Vitruvian app passes its backdrop too and the chat clips to,
/// so the edge and the content agree.
private struct ChatBackdrop: View {
    static let cornerRadius = NexusAgentQuickPromptLayout.cornerRadius

    var body: some View {
        ChatBackdropMaterial(cornerRadius: Self.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

/// The material itself. The corner radius rounds the effect view's own
/// layer: SwiftUI's clip does not clip a behind-window blur, which would
/// otherwise keep its rectangular bounds and show as a faint outline.
private struct ChatBackdropMaterial: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
    }
}

/// The Quick Prompt's floating window: the shared chat view on the tool's
/// engine, in a panel of the tool's own process. Esc and ⌘W close it, ⌘N
/// starts a chat, a click outside closes it unless it is pinned. The
/// standalone app's window, without its hotkey: the app gives the tool's
/// command a shortcut.
///
/// It can also sit in a slot the app gives it, the notch: docked, the chat
/// is drawn embedded, above the menu bar, without shadow, and stays put
/// when the person clicks elsewhere; undocked, it floats again.
@MainActor
final class ToolWindowController: NSObject, NSWindowDelegate, QuickPromptWindow {
    private typealias Layout = NexusAgentQuickPromptLayout

    private let engine: ToolEngine
    private var language: () -> String
    private var panel: NSPanel?
    private var hosting: NSHostingView<NexusAgentChatView>?
    private var modeObserver: AnyCancellable?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var isPinned = false {
        didSet { if panel != nil { hosting?.rootView = chatView() } }
    }
    /// The frame of the slot the chat sits in; nil while it floats.
    private var slotFrame: CGRect?
    /// Asked of the app when the person presses the dock button; while nil
    /// the button is not drawn, since nothing could answer it.
    var onDockToNotch: (() -> Void)? {
        didSet { hosting?.rootView = chatView() }
    }

    /// The level a docked chat sits at: above the menu bar and the app's
    /// notch, which is at the status bar's level and one above.
    static let slotLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)

    init(engine: ToolEngine, language: @escaping () -> String) {
        self.engine = engine
        self.language = language
        super.init()
    }

    var isVisible: Bool { panel?.isVisible == true }

    var isDockedInSlot: Bool { slotFrame != nil }

    /// The app's language changed: the chat's words follow.
    func languageChanged() {
        hosting?.rootView = chatView()
    }

    func toggle() {
        if isVisible, panel?.isKeyWindow == true { hide() } else { show() }
    }

    /// Puts the chat into the slot at `frame`: embedded, above the menu
    /// bar, without shadow, not movable, and not closed by a click outside.
    func dockIntoSlot(frame: CGRect) {
        slotFrame = frame
        let panel = ensurePanel()
        removeClickMonitors()
        installKeyMonitor(for: panel)
        panel.level = Self.slotLevel
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.styleMask.remove(.resizable)
        panel.minSize = frame.size
        panel.maxSize = frame.size
        hosting?.rootView = chatView()
        panel.setFrame(frame, display: true, animate: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        engine.session.focusSerial += 1
    }

    /// Takes the chat out of the slot and floats it again; with `popOut`
    /// it is shown, springing to the floating chat's frame, else hidden.
    func undockFromSlot(popOut: Bool) {
        guard slotFrame != nil else {
            if popOut { show() }
            return
        }
        slotFrame = nil
        guard let panel else { return }
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        hosting?.rootView = chatView()
        guard popOut else {
            hide()
            return
        }
        installMonitors(for: panel)
        let mode = engine.session.mode
        apply(mode, to: panel, frame: Layout.initialFrame(for: mode, screen: screenFrame), animated: panel.isVisible)
        panel.orderFrontRegardless()
        panel.makeKey()
        engine.session.focusSerial += 1
    }

    func show() {
        if let slotFrame {
            dockIntoSlot(frame: slotFrame)
            return
        }
        let panel = ensurePanel()
        installMonitors(for: panel)
        if !panel.isVisible || !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            apply(engine.session.mode, to: panel, frame: Layout.initialFrame(for: engine.session.mode, screen: screenFrame),
                  animated: false)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        engine.session.focusSerial += 1
        if engine.session.conversationID != nil, engine.session.mode == .chat {
            engine.session.startTranscriptFollower(provider: engine.configuration.activeProvider)
        }
    }

    func hide() {
        engine.session.stopTranscriptFollower()
        guard let panel else { return }
        removeMonitors()
        panel.orderOut(nil)
    }

    /// The visible frame of the screen the pointer is on, where the person
    /// is looking; the main screen when no screen holds it.
    private var screenFrame: NSRect {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func chatView() -> NexusAgentChatView {
        let tag = language()
        var strings = NexusAgentChatStrings()
        for (keyPath, key) in Self.chatWords where Words.keys.contains(key) {
            strings[keyPath: keyPath] = Words.text(key, tag)
        }
        strings.noMatchingSessions = Words.text("noSessions", tag)
        let chrome: NexusAgentChatChrome
        if isDockedInSlot {
            chrome = NexusAgentChatChrome(
                backdrop: AnyView(ChatBackdrop()),
                isEmbedded: true,
                isPinned: nil,
                showWindow: { [weak self] in self?.show() },
                dockToNotch: nil,
                errorScheme: "nexus-agent-error",
                offersClearAll: false)
        } else {
            chrome = NexusAgentChatChrome(
                backdrop: AnyView(ChatBackdrop()),
                isPinned: Binding(get: { [weak self] in self?.isPinned ?? false }, set: { [weak self] in self?.isPinned = $0 }),
                showWindow: { [weak self] in self?.show() },
                dockToNotch: onDockToNotch == nil ? nil : { [weak self] in self?.onDockToNotch?() },
                dockToNotchHelp: Words.text("dockToNotchHelp", tag),
                errorScheme: "nexus-agent-error",
                offersClearAll: false)
        }
        return NexusAgentChatView(engine: engine, strings: strings, chrome: chrome)
    }

    /// The chat's words the tool has in fifteen languages, by the field
    /// each fills; the rest keep the shared view's English.
    private static let chatWords: [(WritableKeyPath<NexusAgentChatStrings, String>, String)] = [
        (\.quickPromptTitle, "quickPromptTitle"), (\.workingFolder, "workingFolder"), (\.send, "send"),
        (\.stopReply, "stopReply"), (\.newChat, "newChat"), (\.thinking, "thinking"), (\.working, "working"),
        (\.agentFailed, "agentFailed"), (\.sessionsToggle, "sessionsToggle"), (\.planModeOn, "planModeOn"),
        (\.planModeOff, "planModeOff"), (\.sessionsFilter, "sessionsFilter"), (\.noSessions, "noSessions"),
        (\.untitledSession, "untitledSession"), (\.retry, "retry"), (\.worktreeModeOn, "worktreeModeOn"),
        (\.worktreeModeOff, "worktreeModeOff"), (\.worktreeContext, "worktreeContext"), (\.planContext, "planContext"),
        (\.pinWindow, "pinWindow"), (\.unpinWindow, "unpinWindow"), (\.scrollToBottom, "scrollToBottom"),
        (\.newMessages, "newMessages"), (\.environmentHint, "emptyHint"), (\.newChatShortcut, "newChatShortcut"),
    ]

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let mode = engine.session.mode
        let size = Layout.size(for: mode)
        let panel = QuickPromptPanel(contentRect: NSRect(origin: .zero, size: size),
                                     styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                     backing: .buffered, defer: false)
        panel.title = "Nexus Agent"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = CGColor.clear
        container.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: chatView())
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = CGColor.clear
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = container.bounds
        container.addSubview(hosting)
        panel.contentView = container
        self.panel = panel
        self.hosting = hosting
        apply(mode, to: panel, frame: Layout.initialFrame(for: mode, screen: screenFrame), animated: false)
        modeObserver = engine.session.$mode.removeDuplicates().dropFirst().sink { [weak self, weak panel] mode in
            guard let self, let panel else { return }
            // In the slot the app's frame holds, whatever the mode.
            if isDockedInSlot { return }
            let screen = panel.screen?.visibleFrame ?? screenFrame
            apply(mode, to: panel, frame: Layout.frame(for: mode, from: panel.frame, screen: screen), animated: panel.isVisible)
            if mode == .chat, engine.session.conversationID != nil {
                engine.session.startTranscriptFollower(provider: engine.configuration.activeProvider)
            } else if mode != .chat {
                engine.session.stopTranscriptFollower()
            }
        }
        return panel
    }

    private func apply(_ mode: NexusAgentQuickPromptMode, to panel: NSPanel, frame: CGRect, animated: Bool) {
        if Layout.isResizable(mode) {
            panel.styleMask.insert(.resizable)
            panel.minSize = Layout.chatMinimumSize
            panel.maxSize = Layout.chatMaximumSize
        } else {
            panel.styleMask.remove(.resizable)
            panel.minSize = frame.size
            panel.maxSize = frame.size
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(frame, display: true, animate: false)
            panel.invalidateShadow()
            return
        }
        // The Vitruvian app's spring: ease out with a small overshoot.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.springDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.25, 0.64, 1)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak panel] in
            MainActor.assumeIsolated { panel?.invalidateShadow() }
        })
    }

    /// How long the panel takes to reach a new frame.
    static let springDuration: TimeInterval = 0.32

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard Layout.isResizable(engine.session.mode) else { return sender.frame.size }
        return NSSize(width: min(max(Layout.chatMinimumSize.width, frameSize.width), Layout.chatMaximumSize.width),
                      height: min(max(Layout.chatMinimumSize.height, frameSize.height), Layout.chatMaximumSize.height))
    }

    private func installKeyMonitor(for panel: NSPanel) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCmdW = flags == .command && event.charactersIgnoringModifiers == "w"
            let isCmdN = flags == .command && event.charactersIgnoringModifiers == "n"
            let isCmdK = flags == .command && event.charactersIgnoringModifiers?.lowercased() == "k"
            if isCmdN {
                engine.session.newChat()
                return nil
            }
            if isCmdK {
                engine.session.toggleQuickJump(configuration: engine.configuration)
                return nil
            }
            guard event.keyCode == UInt16(kVK_Escape) || isCmdW else { return event }
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            if !isCmdW, engine.session.pressEscape(stoppingReply: isDockedInSlot) != .dismiss { return nil }
            if isDockedInSlot { return event }
            hide()
            return nil
        }
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        installKeyMonitor(for: panel)
        let localMouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: localMouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, !isPinned else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) { hide() }
            return event
        }
        // Wait for leftMouseUp on global clicks so dragging a file from Finder
        // into the unpinned panel does not hide the panel on mouse-down.
        let globalMouseEvents: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseDown, .otherMouseDown]
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: globalMouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, !isPinned else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel),
               // Keys on the Accessibility Keyboard are clicks outside the panel.
               !Self.assistiveKeyboardOwnsPointer() {
                hide()
            }
        }
    }

    /// Whether the pointer is on the Accessibility Keyboard, read off the
    /// windows on screen now.
    private static func assistiveKeyboardOwnsPointer() -> Bool {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let keyboard = NSRunningApplication.runningApplications(withBundleIdentifier: AssistiveKeyboard.bundleID)
            .first?.processIdentifier
        return AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation, primaryHeight: primary.frame.maxY,
                                                windows: windows, keyboardPID: keyboard)
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func removeClickMonitors() {
        for monitor in [localClickMonitor, outsideClickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        localClickMonitor = nil
        outsideClickMonitor = nil
    }

    private func removeMonitors() {
        for monitor in [keyMonitor, localClickMonitor, outsideClickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        localClickMonitor = nil
        outsideClickMonitor = nil
    }
}
