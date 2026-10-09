// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware
//
// Adapted from the standalone Nexus Agent app (apps/desktop/nexus-agent,
// MIT, Copyright (c) 2026 VitruvianSoftware): its Quick Prompt window.

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import VitruvianCore
import VitruvianDesign

/// Nexus Agent as Vitruvian shows it: the engine (the bot, its `.env`, the
/// chat session) plus what only this app has, which is the Quick Prompt's
/// floating window, the global shortcut that summons it, and the notch it
/// can dock to. The engine asks `VitruvianNexusAgentHost` for this app's
/// settings and text.
@MainActor
package final class NexusAgentService: NexusAgentEngine, NSWindowDelegate {
    package static let shared = NexusAgentService(environment: .live)

    @Published package private(set) var shortcutRegistrationFailed = false
    @Published package var isPinned: Bool = false {
        didSet {
            if isPinned, let panel {
                panel.level = .floating
                panel.hidesOnDeactivate = false
            }
        }
    }

    /// The preferences this app's own half reads: whether the feature is
    /// installed, and the shortcut's switch.
    private let defaults: UserDefaults
    /// Its own id, clear of every other hotkey's: 25 was also the first
    /// capture tool's, so each could answer to the other's key
    /// (`hotkey_ids_are_unique` in bazel/source_lints.py).
    private let hotkey = QuickToolHotkey(id: 90)
    private var panel: NSPanel?
    private var modeObserver: AnyCancellable?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?

    package init(environment: Environment) {
        defaults = environment.defaults
        super.init(environment: environment, host: VitruvianNexusAgentHost(defaults: environment.defaults))
        hotkey.onPress = { [weak self] in self?.toggleQuickPrompt() }
    }

    override package var isChatVisible: Bool { panel?.isVisible == true }

    // MARK: - Preferences

    package func syncWithPreferences() {
        let available = AppFeature.nexusAgent.isAvailable(in: defaults)
        let enabled = available && defaults[Preferences.nexusAgentShortcutEnabled]
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.nexusAgentShortcut, fallback: .nexusAgentDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.nexusAgentShortcut)
        guard available else {
            // Uninstalled in the hub: nothing stays resident, the bot included.
            hideQuickPrompt()
            stopAfterUninstall()
            panel = nil
            return
        }
        startOncePerLaunch()
    }

    package func suspend() {
        hotkey.unregister()
        hideQuickPrompt()
    }

    package func prepareForQuit() {
        stopForQuit()
    }

    // MARK: - Quick Prompt

    package var isQuickPromptVisible: Bool { panel?.isVisible == true }

    package func toggleQuickPrompt() {
        if isQuickPromptVisible, panel?.isKeyWindow == true {
            hideQuickPrompt()
        } else {
            showQuickPrompt()
        }
    }

    package func showQuickPrompt() {
        guard AppFeature.nexusAgent.isAvailable(in: defaults) else { return }
        load()
        let panel = ensurePanel()
        installMonitors(for: panel)
        if !panel.isVisible || !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            apply(session.mode, to: panel, frame: NexusAgentQuickPromptLayout.initialFrame(
                for: session.mode, screen: NSScreen.pointerVisibleFrame), animated: false)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        session.focusSerial += 1
        if session.conversationID != nil && session.mode == .chat {
            session.startTranscriptFollower(provider: configuration.activeProvider)
        }
    }

    package func hideQuickPrompt() {
        session.stopTranscriptFollower()
        guard let panel else { return }
        removeMonitors()
        panel.orderOut(nil)
    }

    package func dockToNotch() {
        hideQuickPrompt()
        NotchService.shared.agentTab = .chat
        NotchService.shared.select(.agents)
    }

    /// Borderless panels refuse key status by default; the prompt needs it
    /// so typing and Esc work without activating the app.
    private final class KeyablePromptPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let size = NexusAgentQuickPromptLayout.size(for: session.mode)
        let panel = KeyablePromptPanel(contentRect: NSRect(origin: .zero, size: size),
                                       styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                       backing: .buffered,
                                       defer: false)
        panel.title = "Vitruvian"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        let host = NSHostingController(rootView: ServiceViews.factory.nexusAgentQuickPrompt())
        host.sizingOptions = []
        panel.contentViewController = host
        self.panel = panel
        apply(session.mode, to: panel, frame: NexusAgentQuickPromptLayout.initialFrame(
            for: session.mode, screen: NSScreen.pointerVisibleFrame), animated: false)
        // Pill, drawer and chat each have their own size; the panel follows.
        modeObserver = session.$mode.removeDuplicates().dropFirst().sink { [weak self, weak panel] mode in
            guard let self, let panel else { return }
            let screen = panel.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
            self.apply(mode, to: panel, frame: NexusAgentQuickPromptLayout.frame(
                for: mode, from: panel.frame, screen: screen), animated: panel.isVisible)
            if mode == .chat && self.session.conversationID != nil {
                self.session.startTranscriptFollower(provider: self.configuration.activeProvider)
            } else if mode != .chat {
                self.session.stopTranscriptFollower()
            }
        }
        return panel
    }

    /// Sizes the panel for `mode`; only the chat can be resized by hand.
    private func apply(_ mode: NexusAgentQuickPromptMode, to panel: NSPanel, frame: CGRect, animated: Bool) {
        typealias Layout = NexusAgentQuickPromptLayout
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
            return
        }
        let spring = CASpringAnimation()
        spring.stiffness = Layout.springStiffness
        spring.damping = Layout.springDamping
        NSAnimationContext.runAnimationGroup { context in
            context.duration = spring.settlingDuration
            // Ease out with a small overshoot, like the spring it times.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.25, 0.64, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    package func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        typealias Layout = NexusAgentQuickPromptLayout
        guard Layout.isResizable(session.mode) else { return sender.frame.size }
        return NSSize(width: min(max(Layout.chatMinimumSize.width, frameSize.width), Layout.chatMaximumSize.width),
                      height: min(max(Layout.chatMinimumSize.height, frameSize.height), Layout.chatMaximumSize.height))
    }

    /// Esc closes the prompt, and so does a click outside it. A reply in
    /// flight keeps streaming into the session while it is hidden.
    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCmdW = flags == .command && event.charactersIgnoringModifiers == "w"
            let isCmdN = flags == .command && event.charactersIgnoringModifiers == "n"
            if isCmdN {
                self.session.newChat()
                return nil
            }
            guard event.keyCode == UInt16(kVK_Escape) || isCmdW else { return event }
            // Mid-composition Esc belongs to the input method.
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            self.hideQuickPrompt()
            return nil
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            guard !self.isPinned else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) { self.hideQuickPrompt() }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return }
            guard !self.isPinned else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel),
               // Keys on the Accessibility Keyboard are clicks outside the panel.
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) {
                self.hideQuickPrompt()
            }
        }
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func removeMonitors() {
        for monitor in [keyMonitor, localClickMonitor, outsideClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        localClickMonitor = nil
        outsideClickMonitor = nil
    }

    // MARK: - Session Archiving

    /// Archiving as the rest of the app calls it by type: the hidden Claude
    /// sessions are this app's saved list.
    nonisolated package static func archiveSession(home: String, id: String, provider: NexusAgentCLIProvider) {
        archiveSession(home: home, id: id, provider: provider,
                       hiddenClaudeSessionIDs: { VitruvianNexusAgentHost.savedHiddenClaudeSessionIDs },
                       saveHiddenClaudeSessionIDs: { VitruvianNexusAgentHost.savedHiddenClaudeSessionIDs = $0 })
    }

    nonisolated package static func unarchiveSession(home: String, id: String, provider: NexusAgentCLIProvider) {
        unarchiveSession(home: home, id: id, provider: provider,
                         hiddenClaudeSessionIDs: { VitruvianNexusAgentHost.savedHiddenClaudeSessionIDs },
                         saveHiddenClaudeSessionIDs: { VitruvianNexusAgentHost.savedHiddenClaudeSessionIDs = $0 })
    }
}
