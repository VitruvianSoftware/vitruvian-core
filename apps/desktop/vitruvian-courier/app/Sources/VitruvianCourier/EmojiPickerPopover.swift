// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore

/// The emoji button's picker, open over the button: a search box (focused when clicked/pinned, unfocused when opened
/// on hover until interacted with), "Frequently used", one tab per category, the emoji in a grid, and a skin tone for
/// hands and people. A click adds the emoji where the caret is and closes the picker; Shift-click adds it and keeps
/// the picker open. Escape closes it. "Emoji & Symbols…" at the bottom opens the macOS Character Viewer, as ⌃⌘Space
/// does everywhere.
struct EmojiPickerPopover: View {
    @ObservedObject var composer: ComposerModel
    var autoFocusSearch: Bool = true
    var onInteract: (() -> Void)? = nil

    @State private var query = ""
    @State private var frequent: [String] = []
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static let columns: [GridItem] = Array(repeating: GridItem(.flexible(minimum: 30), spacing: 2), count: 8)

    private var sections: [EmojiPickerSection] {
        EmojiPickerContent.sections(query: query, tone: composer.emojiSkinTone, frequent: frequent)
    }

    var body: some View {
        let shown = sections
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        categoryTabs(shown, proxy: proxy)
                    }
                    Divider()
                    grid(shown)
                }
            }
            Divider()
            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
        }
        .frame(width: 330, height: 380)
        .onAppear {
            frequent = composer.emojiUsage.frequent()
            if autoFocusSearch {
                DispatchQueue.main.async { searchFocused = true }
            }
        }
        .onChange(of: autoFocusSearch) { _, wantsFocus in
            if wantsFocus {
                DispatchQueue.main.async { searchFocused = true }
            }
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { onInteract?() }
        }
        .onChange(of: query) { _, _ in
            onInteract?()
        }
        .onExitCommand { composer.isEmojiPickerPresented = false }
        .accessibilityIdentifier("composer.emojiPicker")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search emoji"), text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($searchFocused)
                .accessibilityIdentifier("composer.emojiPicker.search")
                .onSubmit {
                    // Return chooses the first match, as in any search-and-pick list.
                    if let first = sections.first?.items.first { choose(first.glyph, keepOpen: false) }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    onInteract?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }

    private func categoryTabs(_ shown: [EmojiPickerSection], proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 2) {
            ForEach(shown) { section in
                Button {
                    onInteract?()
                    // Reduce Motion: jump to the category instead of scrolling to it.
                    if reduceMotionEnabled {
                        proxy.scrollTo(section.id, anchor: .top)
                    } else {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(section.id, anchor: .top) }
                    }
                } label: {
                    Image(systemName: section.category?.symbolName ?? "clock")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.title)
                .accessibilityLabel(section.title)
            }
        }
        .padding(.horizontal, 8)
    }

    private func grid(_ shown: [EmojiPickerSection]) -> some View {
        Group {
            if shown.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "face.dashed")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "No matching emoji"))
                        .font(.callout.weight(.medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6, pinnedViews: []) {
                        ForEach(shown) { section in
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 6)
                                .id(section.id)
                            LazyVGrid(columns: Self.columns, spacing: 2) {
                                ForEach(section.items) { item in
                                    EmojiCell(item: item) {
                                        let keepOpen = NSEvent.modifierFlags.contains(.shift)
                                        if keepOpen { onInteract?() }
                                        choose(item.glyph, keepOpen: keepOpen)
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(EmojiSkinTone.allCases) { tone in
                    Button {
                        onInteract?()
                        composer.emojiSkinTone = tone
                    } label: {
                        Text(verbatim: "\(tone.swatch)  \(tone.title)")
                    }
                }
            } label: {
                Text(verbatim: composer.emojiSkinTone.swatch)
                    .font(.system(size: 16))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "Skin tone for hands and people"))
            .accessibilityLabel(String(localized: "Skin tone"))
            .accessibilityValue(composer.emojiSkinTone.title)

            Spacer(minLength: 8)

            Button {
                composer.isEmojiPickerPresented = false
                NSApp.orderFrontCharacterPalette(nil)
            } label: {
                Text(String(localized: "Emoji & Symbols…"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Open the macOS Character Viewer (⌃⌘Space)"))
        }
    }

    private func choose(_ glyph: String, keepOpen: Bool) {
        composer.insertEmoji(glyph, keepOpen: keepOpen)
        frequent = composer.emojiUsage.frequent()
    }
}

private struct EmojiCell: View {
    let item: EmojiPickerItem
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        Button(action: action) {
            Text(verbatim: item.glyph)
                .font(.system(size: 22))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Color.primary.opacity(0.1) : .clear)
                        .animation(
                            reduceMotionEnabled ? nil : .easeInOut(duration: HoverFillMotion.duration),
                            value: isHovering
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.name.isEmpty ? item.glyph : item.name.replacingOccurrences(of: "_", with: " "))
        .accessibilityLabel(item.name.isEmpty ? item.glyph : item.name.replacingOccurrences(of: "_", with: " "))
    }
}

// MARK: - Hover-open floating emoji panel (non-focus-stealing until interacted with)

/// Non-activating panel hosting `EmojiPickerPopover`. Opening on hover keeps keyboard focus in the composer text box;
/// clicking the search box inside makes the panel key only when needed.
final class EmojiPickerPanel: NSPanel {
    var onBecomeKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        onBecomeKey?()
    }

    override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Zero-hit-test hover probe inside the emoji panel so pointer enter/exit works even when the panel is non-key.
private struct EmojiPickerHoverTracker: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context _: Context) -> TrackerNSView {
        let view = TrackerNSView()
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ view: TrackerNSView, context _: Context) {
        view.onHoverChanged = onHoverChanged
    }

    final class TrackerNSView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        private var isPointerInside = false

        override func hitTest(_: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            guard !bounds.isEmpty else { return }
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                    owner: self,
                    userInfo: nil
                )
            )
        }

        override func mouseEntered(with _: NSEvent) {
            isPointerInside = true
            onHoverChanged?(true)
        }

        override func mouseExited(with _: NSEvent) {
            isPointerInside = false
            onHoverChanged?(false)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, isPointerInside {
                isPointerInside = false
                onHoverChanged?(false)
            }
            super.viewWillMove(toWindow: newWindow)
        }
    }
}

private struct EmojiPickerPanelContent: View {
    @ObservedObject var composer: ComposerModel
    let autoFocusSearch: Bool
    let onHoverChanged: (Bool) -> Void
    let onInteract: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        EmojiPickerPopover(
            composer: composer,
            autoFocusSearch: autoFocusSearch,
            onInteract: onInteract
        )
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Rectangle().fill(.regularMaterial)
            }
        )
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10),
                lineWidth: 0.5
            )
        )
        .background(EmojiPickerHoverTracker(onHoverChanged: onHoverChanged))
    }
}

/// Coordinates the composer emoji button's hover open (0.15 s), hover close (0.3 s after leaving both button and
/// picker), click-to-pin/toggle, and non-focus-stealing panel lifecycle.
@MainActor
final class EmojiPickerHoverCoordinator: ObservableObject {
    @Published private(set) var isIconAccented: Bool = false

    private(set) var state = EmojiPickerHoverState()
    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var panel: EmojiPickerPanel?
    private weak var anchorView: NSView?
    private weak var hostWindow: NSWindow?
    private weak var trackedComposer: ComposerModel?
    private var outsideClickMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var fadeGeneration: UInt64 = 0
    /// The panel is fading out: it still holds the closed picker's view, which a reopening must not inherit.
    private var isFadingOut = false
    /// Where the picker was when it was last dismissed (screen coordinates).
    private var formerPickerFrame: NSRect = .zero
    private var rearmTask: Task<Void, Never>?
    /// Where the pointer is (screen coordinates); tests give their own.
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }

    internal var isWatchingPointerForTesting: Bool { rearmTask != nil }
    internal var panelForTesting: EmojiPickerPanel? { panel }
    internal var hasPendingTimersForTesting: Bool { openTask != nil || closeTask != nil }

    var shouldRestoreTextFocusOnClose: Bool {
        state.mode == .pinned || panel?.isKeyWindow == true
    }

    deinit {
        openTask?.cancel()
        closeTask?.cancel()
        rearmTask?.cancel()
    }

    func buttonHoverChanged(_ inside: Bool, composer: ComposerModel, anchor: NSView?) {
        if let anchor { anchorView = anchor }
        trackedComposer = composer
        let canOpen = !composer.isLocked && composer.roomID != nil
        let effect = state.buttonHoverChanged(inside, canOpen: canOpen)
        apply(effect, composer: composer)
    }

    func pickerHoverChanged(_ inside: Bool, composer: ComposerModel) {
        trackedComposer = composer
        let effect = state.pickerHoverChanged(inside)
        apply(effect, composer: composer)
    }

    func buttonClicked(composer: ComposerModel, anchor: NSView?) {
        if let anchor { anchorView = anchor }
        trackedComposer = composer
        let canOpen = !composer.isLocked && composer.roomID != nil
        let effect = state.buttonClicked(canOpen: canOpen)
        apply(effect, composer: composer)

        if state.isPresented {
            if !composer.isEmojiPickerPresented {
                composer.toggleEmojiPicker()
            }
            presentPanel(composer: composer, pinned: true, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            installOutsideClickMonitor(composer: composer)
        } else {
            rememberPickerFrame()
            composer.isEmojiPickerPresented = false
            hidePanel(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            watchPointerAfterDismissal()
        }
        isIconAccented = state.isIconAccented
    }

    func syncPresented(_ presented: Bool, composer: ComposerModel, anchor: NSView? = nil) {
        if let anchor { anchorView = anchor }
        trackedComposer = composer
        if presented {
            let effect = state.externalOpen()
            apply(effect, composer: composer)
            presentPanel(
                composer: composer,
                pinned: state.shouldAutoFocusSearch,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
            installOutsideClickMonitor(composer: composer)
        } else {
            rememberPickerFrame()
            let effect = state.externalDismiss()
            apply(effect, composer: composer)
            hidePanel(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            watchPointerAfterDismissal()
        }
        isIconAccented = state.isIconAccented
    }

    func dismiss() {
        openTask?.cancel()
        openTask = nil
        closeTask?.cancel()
        closeTask = nil
        rememberPickerFrame()
        _ = state.externalDismiss()
        isIconAccented = false
        removeOutsideClickMonitor()
        detachAndOrderOutPanel()
        watchPointerAfterDismissal()
    }

    private func rememberPickerFrame() {
        if let panel, panel.isVisible { formerPickerFrame = panel.frame }
    }

    private func screenRectOfButton() -> NSRect? {
        guard let anchorView, let window = anchorView.window else { return nil }
        return window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
    }

    /// Outside the button and outside where the picker was. A button that is gone counts as outside.
    private func pointerIsOutsideButtonAndFormerPicker() -> Bool {
        let point = pointerLocation()
        if let button = screenRectOfButton(), NSMouseInRect(point, button, false) { return false }
        if !formerPickerFrame.isEmpty, NSMouseInRect(point, formerPickerFrame, false) { return false }
        return true
    }

    /// After a dismissal hover stays off until the pointer has been seen outside the button and the former picker
    /// frame (in a short window the picker can cover its own button, so the button coming uncovered under a still
    /// pointer must not open it again). Looks now, and then keeps looking until it has seen it.
    private func watchPointerAfterDismissal() {
        guard state.isDisarmed else { return }
        rearmTask?.cancel()
        rearmTask = nil
        if pointerIsOutsideButtonAndFormerPicker() {
            state.pointerSeenOutside()
            return
        }
        rearmTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                if self.pointerIsOutsideButtonAndFormerPicker() {
                    self.state.pointerSeenOutside()
                    self.rearmTask = nil
                    return
                }
            }
        }
    }

    @discardableResult
    internal func openFromHoverForTesting(composer: ComposerModel, anchor: NSView?) -> Bool {
        if let anchor { anchorView = anchor }
        trackedComposer = composer
        let canOpen = !composer.isLocked && composer.roomID != nil
        _ = state.buttonHoverChanged(true, canOpen: canOpen)
        guard state.openDelayFired(canOpen: canOpen) else { return false }
        isIconAccented = state.isIconAccented
        if !composer.isEmojiPickerPresented {
            composer.toggleEmojiPicker()
        }
        presentPanel(composer: composer, pinned: false, reduceMotion: true)
        installOutsideClickMonitor(composer: composer)
        return true
    }

    private func apply(_ effect: EmojiPickerHoverState.Effect, composer: ComposerModel) {
        switch effect {
        case .none:
            break
        case let .scheduleOpen(delay):
            openTask?.cancel()
            let scheduledRoom = composer.roomID
            openTask = Task { @MainActor [weak self, weak composer] in
                try? await Task.sleep(for: .seconds(delay))
                // A chat switch in the meantime cancels the open: it must not open over the next chat.
                guard !Task.isCancelled, let self, let composer, composer.roomID == scheduledRoom else { return }
                self.openTask = nil
                let canOpen = !composer.isLocked && composer.roomID != nil
                guard self.state.openDelayFired(canOpen: canOpen) else { return }
                self.isIconAccented = self.state.isIconAccented
                if !composer.isEmojiPickerPresented {
                    composer.toggleEmojiPicker()
                }
                self.presentPanel(
                    composer: composer,
                    pinned: false,
                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                )
                self.installOutsideClickMonitor(composer: composer)
            }
        case .cancelOpen:
            openTask?.cancel()
            openTask = nil
        case let .scheduleClose(delay):
            closeTask?.cancel()
            closeTask = Task { @MainActor [weak self, weak composer] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, let composer else { return }
                self.closeTask = nil
                guard self.state.closeDelayFired() else { return }
                self.isIconAccented = self.state.isIconAccented
                composer.isEmojiPickerPresented = false
                self.hidePanel(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
        case .cancelClose:
            closeTask?.cancel()
            closeTask = nil
        case .cancelAll:
            openTask?.cancel()
            openTask = nil
            closeTask?.cancel()
            closeTask = nil
        }
    }

    private func userInteracted(composer: ComposerModel) {
        let effect = state.userInteractedWithPicker()
        apply(effect, composer: composer)
        isIconAccented = state.isIconAccented
        if state.mode == .pinned, let panel {
            updatePanelContent(panel: panel, composer: composer, pinned: true)
        }
    }

    private func presentPanel(composer: ComposerModel, pinned: Bool, reduceMotion: Bool) {
        guard let anchorView, let window = anchorView.window else { return }
        CourierTooltipController.shared.dismiss(preserveWarmup: false)

        let panel = ensurePanel()
        fadeGeneration &+= 1
        if isFadingOut {
            // Reopened while the last one was still fading: it starts empty, not with the last search and scroll.
            panel.contentView = nil
            isFadingOut = false
        }
        panel.onBecomeKey = { [weak self, weak composer] in
            guard let self, let composer else { return }
            self.userInteracted(composer: composer)
        }

        updatePanelContent(panel: panel, composer: composer, pinned: pinned)

        let pickerSize = CGSize(width: 330, height: 380)
        let windowBounds = CGRect(origin: .zero, size: window.frame.size)
        let anchorAppKit = anchorView.convert(anchorView.bounds, to: nil)
        let anchorTopDown = CGRect(
            x: anchorAppKit.minX,
            y: windowBounds.height - anchorAppKit.maxY,
            width: anchorAppKit.width,
            height: anchorAppKit.height
        )
        let placement = CourierTooltipPlacement.place(
            tooltipSize: pickerSize,
            anchor: anchorTopDown,
            in: windowBounds,
            preferredEdge: .top
        )
        let appKitOrigin = NSPoint(
            x: placement.frame.minX,
            y: windowBounds.height - placement.frame.maxY
        )
        let screenRect = window.convertToScreen(CGRect(origin: appKitOrigin, size: pickerSize))
        panel.appearance = window.effectiveAppearance
        panel.setFrame(screenRect, display: true)

        attachPanel(panel, to: window)

        if reduceMotion {
            panel.alphaValue = 1
            panel.orderFront(nil)
        } else if !panel.isVisible {
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
    }

    private func updatePanelContent(panel: EmojiPickerPanel, composer: ComposerModel, pinned: Bool) {
        let windowAppearance = hostWindow?.effectiveAppearance ?? anchorView?.window?.effectiveAppearance ?? NSApp.effectiveAppearance
        let isDark = windowAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let root = EmojiPickerPanelContent(
            composer: composer,
            autoFocusSearch: pinned,
            onHoverChanged: { [weak self, weak composer] inside in
                guard let self, let composer else { return }
                self.pickerHoverChanged(inside, composer: composer)
            },
            onInteract: { [weak self, weak composer] in
                guard let self, let composer else { return }
                self.userInteracted(composer: composer)
            }
        )
        .environment(\.colorScheme, isDark ? .dark : .light)
        // The hosting view is made once per opening and only given a new root after that. Pinning a hover-opened
        // picker (a click, typing in the search box) must not rebuild it: the search text and the scroll position
        // are the person's, and a rebuilt view would lose both.
        if let hosting = panel.contentView as? NSHostingView<AnyView> {
            hosting.rootView = AnyView(root)
        } else {
            panel.contentView = NSHostingView(rootView: AnyView(root))
        }
    }

    private func hidePanel(reduceMotion: Bool) {
        removeOutsideClickMonitor()
        guard let panel, panel.isVisible else {
            detachAndOrderOutPanel()
            return
        }
        fadeGeneration &+= 1
        let gen = fadeGeneration
        if reduceMotion {
            detachAndOrderOutPanel()
            return
        }
        isFadingOut = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = CourierTooltipMotion.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.fadeGeneration == gen else { return }
                self.detachAndOrderOutPanel()
            }
        })
        // A window that is not drawing (hidden, or off screen) never runs the fade's completion: the panel must still go.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(CourierTooltipMotion.fadeDuration + 0.1))
            guard let self, self.fadeGeneration == gen else { return }
            self.detachAndOrderOutPanel()
        }
    }

    private func ensurePanel() -> EmojiPickerPanel {
        if let panel { return panel }
        let created = EmojiPickerPanel()
        panel = created
        return created
    }

    private func attachPanel(_ panel: EmojiPickerPanel, to window: NSWindow) {
        if hostWindow !== window {
            detachWindowObservers()
            if let oldHost = hostWindow, panel.parent === oldHost {
                oldHost.removeChildWindow(panel)
            }
            hostWindow = window
            windowObservers.append(
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.trackedComposer?.isEmojiPickerPresented = false
                        self?.dismiss()
                    }
                }
            )
            windowObservers.append(
                NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.trackedComposer?.isEmojiPickerPresented = false
                        self?.dismiss()
                    }
                }
            )
        }
        if panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
        }
    }

    private func detachAndOrderOutPanel() {
        fadeGeneration &+= 1
        isFadingOut = false
        if let panel {
            if let parent = panel.parent {
                parent.removeChildWindow(panel)
            }
            panel.orderOut(nil)
            panel.alphaValue = 1
            // The next opening starts fresh: empty search, top of the list.
            panel.contentView = nil
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

    private func installOutsideClickMonitor(composer: ComposerModel) {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self, weak composer] event in
            MainActor.assumeIsolated {
                guard let self, let composer, self.state.isPresented else { return }
                let screenPoint: NSPoint
                if let eventWindow = event.window {
                    screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
                } else {
                    screenPoint = NSEvent.mouseLocation
                }
                if let panel = self.panel, NSMouseInRect(screenPoint, panel.frame, false) {
                    return
                }
                if let anchor = self.anchorView, let anchorWindow = anchor.window {
                    let anchorScreenRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
                    if NSMouseInRect(screenPoint, anchorScreenRect, false) {
                        return
                    }
                }
                composer.isEmojiPickerPresented = false
            }
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}
