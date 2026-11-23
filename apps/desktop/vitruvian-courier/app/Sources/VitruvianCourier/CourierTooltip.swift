// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore

/// Content rendered inside a fast styled Courier tooltip.
struct CourierTooltipContent: Equatable {
    let title: String
    let shortcut: String?
    let detail: String?
    let edge: CourierTooltipEdge

    init(title: String, shortcut: String? = nil, detail: String? = nil, edge: CourierTooltipEdge = .top) {
        self.title = title
        self.shortcut = shortcut
        self.detail = detail
        self.edge = edge
    }
}

/// Non-activating, click-through floating panel that hosts `CourierTooltipView`.
final class CourierTooltipPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Rounded dark/light adaptive tooltip surface with separate rounded shortcut key caps and optional detail line.
struct CourierTooltipView: View {
    static let shadowInset: CGFloat = 12

    let content: CourierTooltipContent
    @Environment(\.colorScheme) private var colorScheme

    private var keyCaps: [String] {
        guard let shortcut = content.shortcut else { return [] }
        return CourierShortcutKeyCaps.tokens(from: shortcut)
    }

    private var surfaceFill: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.15, blue: 0.17).opacity(0.96)
            : Color(red: 0.99, green: 0.99, blue: 1.0).opacity(0.98)
    }

    private var borderStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.42 : 0.16)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(content.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !keyCaps.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(Array(keyCaps.enumerated()), id: \.offset) { _, token in
                            Text(verbatim: token)
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1.5)
                                .frame(minWidth: 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.primary.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5)
                                )
                        }
                    }
                }
            }
            if let detail = content.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: 260, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background(shape.fill(surfaceFill))
        .overlay(shape.strokeBorder(borderStroke, lineWidth: 0.5))
        .shadow(color: shadowColor, radius: 5, x: 0, y: 2)
        .padding(Self.shadowInset)
        .allowsHitTesting(false)
    }
}

/// Shared tooltip coordinator implementing the 0.25 s hover delay, 0.5 s neighbour warmup, 0.1 s fade, and
/// window-edge clamping without stealing clicks or keyboard focus.
@MainActor
final class CourierTooltipController {
    static let shared = CourierTooltipController()

    private var state = CourierTooltipSchedulerState()
    private var pendingTask: Task<Void, Never>?
    private var panel: CourierTooltipPanel?
    private weak var hostWindow: NSWindow?
    private weak var currentAnchor: NSView?
    private var currentContent: CourierTooltipContent?
    private var localEventMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var presentationGeneration: UInt64 = 0

    internal var activePanelForTesting: CourierTooltipPanel? { panel }
    internal var isVisibleForTesting: Bool { state.isVisible && panel?.isVisible == true }

    private init() {}

    func hoverEntered(
        id: String,
        content: CourierTooltipContent,
        anchorView: NSView,
        reduceMotion: Bool = false
    ) {
        guard !content.title.isEmpty else {
            hoverExited(id: id, reduceMotion: reduceMotion)
            return
        }
        pendingTask?.cancel()
        pendingTask = nil

        let now = ProcessInfo.processInfo.systemUptime
        let delay = state.hoverEntered(id: id, at: now)
        currentAnchor = anchorView
        currentContent = content
        installEventMonitorIfNeeded()

        if delay <= 0 {
            presentPanel(content: content, anchorView: anchorView, animateFade: false, reduceMotion: reduceMotion)
            return
        }

        pendingTask = Task { @MainActor [weak self, weak anchorView] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled,
                  let self,
                  let anchorView,
                  anchorView.window != nil,
                  self.state.delayElapsed(for: id),
                  let activeContent = self.currentContent
            else { return }
            self.presentPanel(content: activeContent, anchorView: anchorView, animateFade: true, reduceMotion: reduceMotion)
        }
    }

    func updateContentIfActive(
        id: String,
        content: CourierTooltipContent,
        anchorView: NSView,
        reduceMotion: Bool = false
    ) {
        guard state.activeID == id, currentContent != content else { return }
        guard !content.title.isEmpty else {
            hoverExited(id: id, reduceMotion: reduceMotion)
            return
        }
        currentContent = content
        currentAnchor = anchorView
        if state.isVisible {
            presentPanel(content: content, anchorView: anchorView, animateFade: false, reduceMotion: reduceMotion)
        }
    }

    func hoverExited(id: String, reduceMotion: Bool = false) {
        let wasActive = state.activeID == id
        let now = ProcessInfo.processInfo.systemUptime
        let wasVisible = state.hoverExited(id: id, at: now)

        if wasActive {
            pendingTask?.cancel()
            pendingTask = nil
            currentAnchor = nil
            currentContent = nil
            removeEventMonitor()
        }

        if wasVisible {
            fadeOutPanel(reduceMotion: reduceMotion)
        }
    }

    func dismiss(preserveWarmup: Bool = false) {
        pendingTask?.cancel()
        pendingTask = nil
        currentAnchor = nil
        currentContent = nil
        state.dismiss(at: ProcessInfo.processInfo.systemUptime, preserveWarmup: preserveWarmup)
        removeEventMonitor()
        detachAndOrderOutPanel()
    }

    /// Deterministically renders and places a tooltip immediately for tests, returning the placed card frame
    /// in window coordinates (top-left origin).
    @discardableResult
    internal func presentNowForTesting(content: CourierTooltipContent, anchorView: NSView) -> CGRect? {
        pendingTask?.cancel()
        pendingTask = nil
        currentAnchor = anchorView
        currentContent = content
        _ = state.hoverEntered(id: "testing-\(UUID().uuidString)", at: ProcessInfo.processInfo.systemUptime)
        _ = state.delayElapsed(for: state.activeID ?? "")
        return presentPanel(content: content, anchorView: anchorView, animateFade: false, reduceMotion: true)
    }

    @discardableResult
    private func presentPanel(
        content: CourierTooltipContent,
        anchorView: NSView,
        animateFade: Bool,
        reduceMotion: Bool
    ) -> CGRect? {
        guard let window = anchorView.window else { return nil }
        let panel = ensurePanel()
        presentationGeneration &+= 1

        let isDark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let root = CourierTooltipView(content: content)
            .environment(\.colorScheme, isDark ? .dark : .light)
        let hosting = NSHostingView(rootView: root)
        let fitting = hosting.fittingSize
        let inset = CourierTooltipView.shadowInset
        let cardSize = CGSize(
            width: max(1, fitting.width - inset * 2),
            height: max(1, fitting.height - inset * 2)
        )

        let windowBounds = CGRect(origin: .zero, size: window.frame.size)
        let anchorAppKit = anchorView.convert(anchorView.bounds, to: nil)
        let anchorTopDown = CGRect(
            x: anchorAppKit.minX,
            y: windowBounds.height - anchorAppKit.maxY,
            width: anchorAppKit.width,
            height: anchorAppKit.height
        )

        let placement = CourierTooltipPlacement.place(
            tooltipSize: cardSize,
            anchor: anchorTopDown,
            in: windowBounds,
            preferredEdge: content.edge
        )

        let cardAppKit = CGRect(
            x: placement.frame.minX,
            y: windowBounds.height - placement.frame.maxY,
            width: placement.frame.width,
            height: placement.frame.height
        )
        let panelAppKit = cardAppKit.insetBy(dx: -inset, dy: -inset)
        let screenFrame = window.convertToScreen(panelAppKit)

        panel.appearance = window.effectiveAppearance
        panel.contentView = hosting
        panel.setFrame(screenFrame, display: true)

        attachPanel(panel, to: window)

        let shouldAnimate = animateFade && !reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if shouldAnimate {
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = CourierTooltipMotion.fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFront(nil)
        }

        return placement.frame
    }

    private func ensurePanel() -> CourierTooltipPanel {
        if let panel { return panel }
        let created = CourierTooltipPanel()
        panel = created
        return created
    }

    private func attachPanel(_ panel: CourierTooltipPanel, to window: NSWindow) {
        if hostWindow !== window {
            detachWindowObservers()
            if let oldHost = hostWindow, panel.parent === oldHost {
                oldHost.removeChildWindow(panel)
            }
            hostWindow = window
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                windowObservers.append(
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        Task { @MainActor in self?.dismiss(preserveWarmup: false) }
                    }
                )
            }
        }
        if panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
        }
    }

    private func fadeOutPanel(reduceMotion: Bool) {
        guard let panel, panel.isVisible else {
            detachAndOrderOutPanel()
            return
        }
        presentationGeneration &+= 1
        let gen = presentationGeneration
        let instant = reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if instant {
            detachAndOrderOutPanel()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = CourierTooltipMotion.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.presentationGeneration == gen else { return }
                self.detachAndOrderOutPanel()
            }
        })
    }

    private func detachAndOrderOutPanel() {
        presentationGeneration &+= 1
        if let panel {
            if let parent = panel.parent {
                parent.removeChildWindow(panel)
            }
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
        detachWindowObservers()
        hostWindow = nil
    }

    private func detachWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers = []
    }

    private func installEventMonitorIfNeeded() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.dismiss(preserveWarmup: false)
            }
            return event
        }
    }

    private func removeEventMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }
}

/// Zero-hit-test AppKit tracking anchor placed behind a SwiftUI control to drive `CourierTooltipController`.
private struct CourierTooltipAnchorView: NSViewRepresentable {
    let content: CourierTooltipContent
    let isEnabled: Bool
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnchorNSView {
        let view = AnchorNSView()
        view.tooltipID = context.coordinator.id
        return view
    }

    func updateNSView(_ view: AnchorNSView, context _: Context) {
        view.configure(content: content, isEnabled: isEnabled, reduceMotion: reduceMotion)
    }

    @MainActor
    final class Coordinator {
        let id = UUID().uuidString
    }

    final class AnchorNSView: NSView {
        var tooltipID = ""
        private var content = CourierTooltipContent(title: "")
        private var isEnabled = true
        private var reduceMotion = false
        private var isPointerInside = false

        override func hitTest(_: NSPoint) -> NSView? { nil }

        func configure(content: CourierTooltipContent, isEnabled: Bool, reduceMotion: Bool) {
            self.content = content
            self.reduceMotion = reduceMotion
            let wasEnabled = self.isEnabled
            self.isEnabled = isEnabled
            if !isEnabled {
                if wasEnabled || isPointerInside {
                    CourierTooltipController.shared.hoverExited(id: tooltipID, reduceMotion: reduceMotion)
                }
            } else if isPointerInside {
                if !wasEnabled {
                    CourierTooltipController.shared.hoverEntered(
                        id: tooltipID,
                        content: content,
                        anchorView: self,
                        reduceMotion: reduceMotion
                    )
                } else {
                    CourierTooltipController.shared.updateContentIfActive(
                        id: tooltipID,
                        content: content,
                        anchorView: self,
                        reduceMotion: reduceMotion
                    )
                }
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            guard !bounds.isEmpty else { return }
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                    owner: self,
                    userInfo: nil
                )
            )
        }

        override func mouseEntered(with _: NSEvent) {
            isPointerInside = true
            guard isEnabled else { return }
            CourierTooltipController.shared.hoverEntered(
                id: tooltipID,
                content: content,
                anchorView: self,
                reduceMotion: reduceMotion
            )
        }

        override func mouseExited(with _: NSEvent) {
            isPointerInside = false
            CourierTooltipController.shared.hoverExited(id: tooltipID, reduceMotion: reduceMotion)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, isPointerInside {
                isPointerInside = false
                CourierTooltipController.shared.hoverExited(id: tooltipID, reduceMotion: reduceMotion)
            }
            super.viewWillMove(toWindow: newWindow)
        }
    }
}

private struct CourierTooltipModifier: ViewModifier {
    let content: CourierTooltipContent
    let isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var reduceMotion: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func body(content base: Content) -> some View {
        base.background(
            CourierTooltipAnchorView(
                content: content,
                isEnabled: isEnabled && !content.title.isEmpty,
                reduceMotion: reduceMotion
            )
        )
    }
}

extension View {
    /// Attaches a fast styled tooltip (0.25 s cold delay, instant neighbour warmup, rounded shortcut key caps,
    /// window-edge clamping, zero click/focus interference). Keep accessibility labels separate.
    func courierTooltip(
        _ title: String,
        shortcut: String? = nil,
        detail: String? = nil,
        edge: CourierTooltipEdge = .top,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            CourierTooltipModifier(
                content: CourierTooltipContent(title: title, shortcut: shortcut, detail: detail, edge: edge),
                isEnabled: isEnabled
            )
        )
    }
}
