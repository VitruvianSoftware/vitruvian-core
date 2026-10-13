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

private struct ChatBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = NexusAgentQuickPromptLayout.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// The Quick Prompt's floating window: the shared chat view on the tool's
/// engine, in a panel of the tool's own process. Esc and ⌘W close it, ⌘N
/// starts a chat, a click outside closes it unless it is pinned. The
/// standalone app's window, without its hotkey: the app gives the tool's
/// command a shortcut.
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
        didSet { if let panel { panel.level = .floating; hosting?.rootView = chatView() } }
    }

    init(engine: ToolEngine, language: @escaping () -> String) {
        self.engine = engine
        self.language = language
        super.init()
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// The app's language changed: the chat's words follow.
    func languageChanged() {
        hosting?.rootView = chatView()
    }

    func toggle() {
        if isVisible, panel?.isKeyWindow == true { hide() } else { show() }
    }

    func show() {
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

    private var screenFrame: NSRect {
        NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func chatView() -> NexusAgentChatView {
        let tag = language()
        var strings = NexusAgentChatStrings()
        for (keyPath, key) in Self.chatWords { strings[keyPath: keyPath] = Words.text(key, tag) }
        strings.noMatchingSessions = Words.text("noSessions", tag)
        return NexusAgentChatView(
            engine: engine, strings: strings,
            chrome: NexusAgentChatChrome(
                backdrop: AnyView(ChatBackdrop()),
                isPinned: Binding(get: { [weak self] in self?.isPinned ?? false }, set: { [weak self] in self?.isPinned = $0 }),
                showWindow: { [weak self] in self?.show() },
                errorScheme: "nexus-agent-error",
                offersClearAll: false))
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
        panel.setFrame(frame, display: true, animate: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        panel.invalidateShadow()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard Layout.isResizable(engine.session.mode) else { return sender.frame.size }
        return NSSize(width: min(max(Layout.chatMinimumSize.width, frameSize.width), Layout.chatMaximumSize.width),
                      height: min(max(Layout.chatMinimumSize.height, frameSize.height), Layout.chatMaximumSize.height))
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCmdW = flags == .command && event.charactersIgnoringModifiers == "w"
            let isCmdN = flags == .command && event.charactersIgnoringModifiers == "n"
            if isCmdN {
                engine.session.newChat()
                return nil
            }
            guard event.keyCode == UInt16(kVK_Escape) || isCmdW else { return event }
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            if !isCmdW, engine.session.pressEscape(stoppingReply: false) != .dismiss { return nil }
            hide()
            return nil
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, !isPinned else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) { hide() }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, !isPinned else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel) { hide() }
        }
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func removeMonitors() {
        for monitor in [keyMonitor, localClickMonitor, outsideClickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        localClickMonitor = nil
        outsideClickMonitor = nil
    }
}
