// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// The first review round on the hover and tooltip work: one tooltip per control, an honest send button, a picker
/// that is not rebuilt under the person's hands, and a row whose preview stays put. These drive the real
/// `ComposerView`, `FormattingBarView` and `InboxRowView`, not a stand-in.
@MainActor
final class StreamBRound1ViewTests: XCTestCase {
    private var suites: [String] = []
    private var previousEnhancedUserInterface: Any?
    private static let enhancedUserInterface = "AXEnhancedUserInterface"

    /// SwiftUI builds its accessibility tree (the real controls, by identifier) only when asked to.
    override func setUp() async throws {
        _ = NSApplication.shared
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        previousEnhancedUserInterface = NSApp.perform(getter, with: Self.enhancedUserInterface)?
            .takeUnretainedValue() as? NSNumber ?? false
        NSApp.perform(setter, with: true, with: Self.enhancedUserInterface)
    }

    override func tearDown() async throws {
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        NSApp.perform(setter, with: previousEnhancedUserInterface ?? false, with: Self.enhancedUserInterface)
        CourierTooltipController.shared.dismiss()
        AppLockGate.shared.resetForTesting()
        for name in suites {
            ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name)
        }
        suites = []
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> UserDefaults {
        let name = "courier.streamb.round1.\(UUID().uuidString)"
        suites.append(name)
        return try XCTUnwrap(ScratchDefaults.suite(named: name))
    }

    private func pump(_ view: NSView, for seconds: TimeInterval, until condition: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            view.layoutSubtreeIfNeeded()
            if condition?() == true { break }
        }
    }

    private func hosted<V: View>(_ view: V, size: NSSize) -> (NSWindow, NSHostingView<V>) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.makeKeyAndOrderFront(nil)
        return (window, host)
    }

    private func accessibilityNodes(in root: NSView) -> [AnyObject] {
        let attrSelector = NSSelectorFromString("accessibilityAttributeValue:")
        func children(of element: AnyObject) -> [AnyObject] {
            var list: [AnyObject] = (element.accessibilityChildren?() ?? []).map { $0 as AnyObject }
            if element.responds(to: attrSelector),
               let unmanaged = element.perform(attrSelector, with: NSAccessibility.Attribute.children.rawValue as NSString),
               let raw = unmanaged.takeUnretainedValue() as? [AnyObject] {
                for item in raw where !list.contains(where: { $0 === item }) {
                    list.append(item)
                }
            }
            return list
        }
        func walk(_ element: AnyObject) -> [AnyObject] {
            [element] + children(of: element).flatMap(walk)
        }
        return walk(root)
    }

    private func node(_ identifier: String, in root: NSView) -> AnyObject? {
        accessibilityNodes(in: root).first { $0.accessibilityIdentifier?() == identifier }
    }

    private func isEnabled(_ node: AnyObject) -> Bool? {
        node.isAccessibilityEnabled?()
    }

    private func role(of node: AnyObject) -> NSAccessibility.Role? {
        node.accessibilityRole?() ?? nil
    }

    /// Every help (native tooltip) string the accessibility tree offers under `root`.
    private func helpStrings(in root: NSView) -> [String] {
        accessibilityNodes(in: root).compactMap { node -> String? in
            let help: String? = node.accessibilityHelp?() ?? nil
            return (help?.isEmpty ?? true) ? nil : help
        }
    }

    /// A node's frame in window coordinates (top-left origin).
    private func windowFrame(of node: AnyObject, in window: NSWindow) -> CGRect {
        let screen = node.accessibilityFrame?() ?? .zero
        let appKit = window.convertFromScreen(screen)
        let height = window.contentView?.bounds.height ?? 0
        return CGRect(x: appKit.minX, y: height - appKit.maxY, width: appKit.width, height: appKit.height)
    }

    private func tooltipAnchors(in root: NSView) -> [NSView] {
        root.descendants { String(reflecting: type(of: $0)).contains("AnchorNSView") }
    }

    /// The tooltip anchor behind the control at `frame` (window coordinates, top-left origin).
    private func tooltipAnchor(at frame: CGRect, in host: NSView) throws -> NSView {
        let height = host.bounds.height
        let matches = tooltipAnchors(in: host).filter { anchor in
            let bounds = anchor.convert(anchor.bounds, to: nil)
            let top = CGRect(x: bounds.minX, y: height - bounds.maxY, width: bounds.width, height: bounds.height)
            return abs(top.midX - frame.midX) < 2 && abs(top.midY - frame.midY) < 2
        }
        return try XCTUnwrap(matches.first, "no tooltip anchor behind the control at \(frame)")
    }

    private func enterExit(_ type: NSEvent.EventType, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
    }

    private func makeComposer(
        defaults: UserDefaults,
        fileInfo: @escaping @Sendable (URL) -> ComposerFileInfo? = { _ in nil }
    ) -> (ComposerModel, ComposerPreferences) {
        let preferences = ComposerPreferences(defaults: defaults)
        let composer = ComposerModel(
            sender: SnapshotMessageSender(),
            fileInfo: fileInfo,
            draftDelay: 0,
            sleep: { _ in },
            preferences: preferences
        )
        composer.open(Fixture.room)
        composer.features = Fixture.features
        composer.network = "whatsapp"
        return (composer, preferences)
    }

    // MARK: - Defect 1: the reply-network chip shows one tooltip

    func testReplyNetworkChipShowsOnlyItsOwnTooltip() throws {
        // The badge on its own still carries the native tooltip, so the check below can see one.
        let (calibrationWindow, calibrationHost) = hosted(
            NetworkBadge(network: "whatsapp", name: "WhatsApp", size: 13).padding(10),
            size: NSSize(width: 80, height: 60)
        )
        defer { calibrationWindow.orderOut(nil); calibrationWindow.contentView = nil }
        pump(calibrationHost, for: 0.15)
        let baseline = helpStrings(in: calibrationHost).filter { $0 == "WhatsApp" }.count
        XCTAssertGreaterThanOrEqual(baseline, 1, "calibration: a badge on its own offers its name as a native tooltip")

        let defaults = try makeDefaults()
        let (composer, preferences) = makeComposer(defaults: defaults)
        let merged = Fixture.mergedAlice()
        let (window, host) = hosted(
            ComposerView(
                composer: composer,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight),
                mergedChat: merged,
                activeReplyRoomID: "!dm-alice-wa:courier.local",
                activeReplyNetwork: "whatsapp",
                activeReplyAccountName: "+1 555-010-0101",
                onCycleReplyNetwork: {}
            ),
            size: NSSize(width: 620, height: 220)
        )
        defer { window.orderOut(nil); window.contentView = nil }
        pump(host, for: 0.3)

        // The chip is a button with its own styled tooltip. The native "WhatsApp" tooltips left are the ones that have
        // no styled tooltip over them: the badge in the text box and the one in the row of networks at the end. The
        // chip's own badge must add none.
        let helps = helpStrings(in: host)
        XCTAssertEqual(
            helps.filter { $0 == "WhatsApp" }.count, baseline * 2,
            "the chip's badge showed a second tooltip over the chip's own; native tooltips: \(helps)"
        )
        XCTAssertFalse(helps.contains("Switch the network your reply is sent on"), "the chip's tooltip is the styled one")

        let chip = try XCTUnwrap(
            accessibilityNodes(in: host).first { node in
                let label = node.accessibilityLabel?() ?? ""
                return label.contains("WhatsApp") && role(of: node) == .button
            },
            "the chip is a button"
        )
        let anchor = try tooltipAnchor(at: windowFrame(of: chip, in: window), in: host)
        anchor.mouseEntered(with: try enterExit(.mouseEntered, in: window))
        XCTAssertEqual(
            CourierTooltipController.shared.currentContentForTesting?.title,
            "Switch the network your reply is sent on"
        )
        anchor.mouseExited(with: try enterExit(.mouseExited, in: window))
    }

    // MARK: - Defect 2: the formatting bar uses the styled tooltip with key caps

    func testFormattingBarButtonsShowStyledTooltipsWithKeyCapsAndNoNativeOnes() throws {
        // WhatsApp's features keep everything on the bar but spoilers.
        let items = FormattingBar.items(features: Fixture.features, network: "whatsapp")
        XCTAssertEqual(items.count, 10)
        let (window, host) = hosted(
            FormattingBarView(items: items) { _ in }.padding(20),
            size: NSSize(width: 400, height: 80)
        )
        defer { window.orderOut(nil); window.contentView = nil }
        pump(host, for: 0.25)

        XCTAssertEqual(helpStrings(in: host), [], "no native tooltip alongside the styled one")

        let anchors = tooltipAnchors(in: host).sorted {
            $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX
        }
        XCTAssertEqual(anchors.count, items.count, "one styled tooltip per button")

        for (item, anchor) in zip(items, anchors) {
            anchor.mouseEntered(with: try enterExit(.mouseEntered, in: window))
            let shown = try XCTUnwrap(CourierTooltipController.shared.currentContentForTesting, item.title)
            if item.isEnabled {
                XCTAssertEqual(shown.title, item.title)
                XCTAssertEqual(shown.shortcut, item.keys.isEmpty ? nil : item.keys, "\(item.title)'s keys")
            } else {
                XCTAssertEqual(shown.title, item.help, "an unavailable kind says why")
                XCTAssertTrue(shown.title.contains("Unavailable"))
                XCTAssertNil(shown.shortcut)
            }
            anchor.mouseExited(with: try enterExit(.mouseExited, in: window))
        }
        let bold = try XCTUnwrap(items.first { $0.kind == .bold })
        XCTAssertEqual(CourierShortcutKeyCaps.tokens(from: bold.keys), ["⌘", "B"])
    }

    // MARK: - Item 6: a wrapped detail is never clipped

    func testTooltipCardGrowsToHoldWrappedDetailAndStaysInsideWindow() throws {
        let inset = CourierTooltipView.shadowInset
        let oneLine = NSHostingView(rootView: CourierTooltipView(content: CourierTooltipContent(
            title: "Send", shortcut: "Return", detail: "One line.", edge: .top
        )))
        let longDetail = String(repeating: "Right-click for Send Later and Send and Archive. ", count: 4)
        let wrapped = NSHostingView(rootView: CourierTooltipView(content: CourierTooltipContent(
            title: "Send", shortcut: "Return", detail: longDetail, edge: .top
        )))
        let short = oneLine.fittingSize
        let tall = wrapped.fittingSize
        XCTAssertLessThanOrEqual(tall.width, CourierTooltipView.maxCardWidth + inset * 2 + 0.5, "wraps at the cap")
        XCTAssertGreaterThan(
            tall.width, CourierTooltipView.maxCardWidth - 40, "long text takes the width it is allowed"
        )
        // About 200 characters of 11 pt text in a 240 pt column is five lines; the card must hold all of them.
        XCTAssertGreaterThan(tall.height, short.height + 3 * 11, "the card grows with the wrapped detail")

        // At the window's edge the whole tall card is still inside the window.
        let windowSize = NSSize(width: 520, height: 300)
        final class ProbeBox { weak var view: NSView? }
        struct ProbeAnchor: NSViewRepresentable {
            let box: ProbeBox
            func makeNSView(context _: Context) -> NSView {
                let v = NSView()
                box.view = v
                return v
            }
            func updateNSView(_ v: NSView, context _: Context) { box.view = v }
        }
        let probe = ProbeBox()
        let (window, host) = hosted(
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Color.clear.frame(width: 28, height: 34).background(ProbeAnchor(box: probe))
                }
            }
            .padding(.trailing, 12)
            .padding(.bottom, 8)
            .frame(width: windowSize.width, height: windowSize.height),
            size: windowSize
        )
        defer {
            CourierTooltipController.shared.dismiss()
            window.orderOut(nil)
            window.contentView = nil
        }
        pump(host, for: 0.25) { probe.view?.window != nil }
        let anchor = try XCTUnwrap(probe.view)
        let card = try XCTUnwrap(CourierTooltipController.shared.presentNowForTesting(
            content: CourierTooltipContent(title: "Send", shortcut: "Return", detail: longDetail, edge: .top),
            anchorView: anchor
        ))
        XCTAssertEqual(card.height, tall.height - inset * 2, accuracy: 1.5, "placed at the height the text needs")
        let margin = CourierTooltipPlacement.windowMargin
        XCTAssertGreaterThanOrEqual(card.minX, margin - 0.5)
        XCTAssertLessThanOrEqual(card.maxX, windowSize.width - margin + 0.5)
        XCTAssertGreaterThanOrEqual(card.minY, margin - 0.5)
        XCTAssertLessThanOrEqual(card.maxY, windowSize.height - margin + 0.5)
    }

    // MARK: - Defect 3: the send button agrees with what pressing it would do

    func testRealSendButtonIsEnabledOnlyWhenPressingItWouldDoSomething() async throws {
        let defaults = try makeDefaults()
        // The real lock: `lockNow()` and `unlock()` post the same notifications the app does, and nothing in this test
        // tells the view to redraw, so the Send button must follow them by itself.
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: UnlockingBiometricService(),
            defaults: defaults
        )
        let (composer, preferences) = makeComposer(
            defaults: defaults,
            fileInfo: { _ in ComposerFileInfo(size: 10, isRegularFile: true) }
        )
        let (window, host) = hosted(
            ComposerView(
                composer: composer,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight)
            ),
            size: NSSize(width: 620, height: 220)
        )
        defer { window.orderOut(nil); window.contentView = nil }
        pump(host, for: 0.3) { self.node("composer.send", in: host) != nil }

        func check(_ ready: Bool, _ state: String, line: UInt = #line) {
            pump(host, for: 0.25)
            XCTAssertEqual(composer.canSend, ready, "canSend while \(state)", line: line)
            XCTAssertEqual(
                composer.sendButtonAppearance, ready ? .activeAccent : .disabledNeutral,
                "the colour while \(state)", line: line
            )
            let button = self.node("composer.send", in: host)
            XCTAssertNotNil(button, "the send button while \(state)", line: line)
            if let button {
                XCTAssertEqual(self.isEnabled(button), ready, "the real button's enabled state while \(state)", line: line)
            }
        }

        check(false, "empty")
        composer.text = "  \n "
        check(false, "only whitespace")
        composer.text = "hello"
        check(true, "there is text")
        lifecycle.lockNow()
        check(false, "locked")
        let unlocked = await lifecycle.unlock()
        XCTAssertTrue(unlocked)
        check(true, "unlocked again, with nothing else changed")
        lifecycle.lockNow()
        check(false, "locked a second time")
        _ = await lifecycle.unlock()
        composer.text = ""
        composer.attach([URL(fileURLWithPath: "/tmp/vitruvian-courier-send-state/a.bin")])
        check(true, "there is a file")
        composer.removeAttachment(composer.attachments[0].id)
        composer.pendingGIF = StickerItemWire(
            id: "gif:1", packID: "recent", name: "Wave", mediaURL: "courier://media/1",
            mimeType: "image/gif", usage: ["gif"]
        )
        check(true, "a GIF is staged")
        composer.pendingGIF = nil
        let mine = try XCTUnwrap(Fixture.messages([Fixture.text("$m", "old words", mine: true, ts: 5)]).first)
        composer.startEditing(mine)
        check(true, "editing with its words")
        composer.text = "   "
        check(false, "an edit with nothing left to send")
        composer.text = "new words"
        check(true, "an edit with new words")
    }

    /// Only the send button's colour eases. When it greys out in the same moment as the message box moves (a sent
    /// message clears the box and the "send later?" note goes), the button is drawn at its new place at once rather
    /// than sliding there from the old one. Compares the button's column, outside its final circle, a moment after
    /// the change with the settled picture.
    func testSendButtonColourEaseDoesNotSlideTheButton() throws {
        final class Shift: ObservableObject { @Published var moved = false }
        struct Moving: View {
            @ObservedObject var shift: Shift
            let composer: ComposerModel
            let preferences: ComposerPreferences
            var body: some View {
                VStack(spacing: 0) {
                    ComposerView(composer: composer, preferences: preferences,
                                 textHeight: .constant(ComposerTextView.minimumHeight))
                    Color.clear.frame(height: shift.moved ? 0 : 60)
                }
                .frame(width: 620, height: 260)
                .environment(\.courierReduceMotionOverride, false)
            }
        }
        let defaults = try makeDefaults()
        let (composer, preferences) = makeComposer(defaults: defaults)
        let shift = Shift()
        composer.text = "hello"
        let (window, host) = hosted(Moving(shift: shift, composer: composer, preferences: preferences),
                                    size: NSSize(width: 620, height: 260))
        defer { window.orderOut(nil); window.contentView = nil }
        pump(host, for: 0.4) { self.node("composer.send", in: host) != nil }

        shift.moved = true
        composer.text = ""
        pump(host, for: 0.03)
        let early = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: early)
        pump(host, for: 0.6)
        let settled = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: settled)

        // The button's settled place, in the picture's pixels (top-left origin).
        let button = try XCTUnwrap(node("composer.send", in: host))
        let onScreen = try XCTUnwrap(button.accessibilityFrame?())
        let inHost = host.convert(window.convertFromScreen(onScreen), from: nil)
        let scale = CGFloat(settled.pixelsWide) / host.bounds.width
        let top = host.isFlipped ? inHost.minY : host.bounds.height - inHost.maxY
        let xs = Int((inHost.minX - 4) * scale) ..< Int((inHost.maxX + 4) * scale)
        let circle = Int((top - 2) * scale) ..< Int((top + inHost.height + 2) * scale)
        var differing = 0
        for y in 0 ..< settled.pixelsHigh where !circle.contains(y) {
            for x in xs where early.colorAt(x: x, y: y) != settled.colorAt(x: x, y: y) { differing += 1 }
        }
        XCTAssertEqual(differing, 0, "the send button must not slide while its colour eases")
    }

    // MARK: - Item 5 / Defect 4: the hover-opened picker, on the real emoji button

    /// A real composer on screen. `composer` belongs to the view; `other` is a second one for a coordinator driven by
    /// hand over the real button's geometry, so the view's own coordinator is not woken by what the test does.
    private func realEmojiButtonSetup() throws -> (
        composer: ComposerModel, window: NSWindow, host: NSHostingView<ComposerView>, anchor: NSView,
        other: ComposerModel
    ) {
        let defaults = try makeDefaults()
        let (composer, preferences) = makeComposer(defaults: defaults)
        let (window, host) = hosted(
            ComposerView(
                composer: composer,
                preferences: preferences,
                textHeight: .constant(ComposerTextView.minimumHeight)
            ),
            size: NSSize(width: 620, height: 400)
        )
        pump(host, for: 0.4) { self.node("composer.toolbar.emoji", in: host) != nil }
        let button = try XCTUnwrap(node("composer.toolbar.emoji", in: host), "the real emoji button")
        // The real button's own tooltip anchor is a view exactly over it: the picker opens from there.
        let anchor = try tooltipAnchor(at: windowFrame(of: button, in: window), in: host)
        let (other, _) = makeComposer(defaults: defaults)
        return (composer, window, host, anchor, other)
    }

    private func screenRect(of view: NSView) -> NSRect {
        guard let window = view.window else { return .zero }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    private static let farAway = NSPoint(x: -50_000, y: -50_000)

    private func pickerPanels(of window: NSWindow) -> [EmojiPickerPanel] {
        (window.childWindows ?? []).compactMap { $0 as? EmojiPickerPanel }
    }

    func testClickingTheRealEmojiButtonPinsThePickerAndClickingAgainClosesIt() throws {
        let (composer, window, host, _, _) = try realEmojiButtonSetup()
        defer {
            composer.isEmojiPickerPresented = false
            window.orderOut(nil)
            window.contentView = nil
        }
        let button = try XCTUnwrap(node("composer.toolbar.emoji", in: host))
        XCTAssertTrue(button.accessibilityPerformPress?() ?? false, "the emoji button can be pressed")
        pump(host, for: 0.5) { !self.pickerPanels(of: window).isEmpty }
        XCTAssertTrue(composer.isEmojiPickerPresented, "a click opens the picker")
        XCTAssertEqual(pickerPanels(of: window).count, 1)
        XCTAssertTrue(pickerPanels(of: window).first?.isVisible == true)

        XCTAssertTrue(button.accessibilityPerformPress?() ?? false)
        pump(host, for: 0.6) { self.pickerPanels(of: window).isEmpty }
        XCTAssertFalse(composer.isEmojiPickerPresented, "a second click closes it")
        XCTAssertTrue(pickerPanels(of: window).isEmpty)
    }

    func testPinningAHoverOpenedPickerKeepsItsViewAndDismissingWaitsForThePointerToLeave() throws {
        let (_, window, host, anchor, composer) = try realEmojiButtonSetup()
        let coordinator = EmojiPickerHoverCoordinator()
        var pointer = Self.farAway
        coordinator.pointerLocation = { pointer }
        defer {
            coordinator.dismiss()
            window.orderOut(nil)
            window.contentView = nil
        }

        // Hover for 0.15 s: the real timer opens it, in hover mode.
        coordinator.buttonHoverChanged(true, composer: composer, anchor: anchor)
        XCTAssertTrue(coordinator.hasPendingTimersForTesting, "the open is waiting out its delay")
        pump(host, for: 1.0) { coordinator.state.mode == .hoverOpen }
        XCTAssertEqual(coordinator.state.mode, .hoverOpen)
        let panel = try XCTUnwrap(coordinator.panelForTesting)
        let openedView = try XCTUnwrap(panel.contentView)

        // A click pins it: the same view stays, so a typed search and the scroll position are not lost.
        coordinator.buttonClicked(composer: composer, anchor: anchor)
        XCTAssertEqual(coordinator.state.mode, .pinned)
        XCTAssertTrue(panel.contentView === openedView, "pinning by a click must not rebuild the picker")

        // Closed, it starts fresh next time.
        composer.isEmojiPickerPresented = false
        coordinator.syncPresented(false, composer: composer, anchor: anchor)
        pump(host, for: 0.5) { !panel.isVisible }
        XCTAssertNil(panel.contentView, "a closed picker starts fresh next time")

        // Interacting inside a hover-opened picker pins it, and does not rebuild it either.
        coordinator.buttonHoverChanged(false, composer: composer, anchor: anchor)
        coordinator.buttonHoverChanged(true, composer: composer, anchor: anchor)
        pump(host, for: 1.0) { coordinator.state.mode == .hoverOpen }
        XCTAssertEqual(coordinator.state.mode, .hoverOpen)
        let secondView = try XCTUnwrap(coordinator.panelForTesting?.contentView)
        try XCTUnwrap(coordinator.panelForTesting).onBecomeKey?() // the person clicked into the search box
        XCTAssertEqual(coordinator.state.mode, .pinned)
        XCTAssertTrue(coordinator.panelForTesting?.contentView === secondView, "interacting must not rebuild it")

        // Dismissed (Escape, an emoji chosen) while the pointer is still on the button: no reopening until it has been
        // seen away from it. (The finer cases, the picker covering its own button, are in the next test.)
        let button = screenRect(of: anchor)
        pointer = NSPoint(x: button.midX, y: button.midY)
        composer.isEmojiPickerPresented = false
        coordinator.syncPresented(false, composer: composer, anchor: anchor)
        coordinator.buttonHoverChanged(true, composer: composer, anchor: anchor) // AppKit's second "entered"
        XCTAssertFalse(coordinator.hasPendingTimersForTesting)
        pump(host, for: 0.5)
        XCTAssertEqual(coordinator.state.mode, .closed)
        XCTAssertFalse(composer.isEmojiPickerPresented, "no reopen loop while the pointer stays on the button")
        pointer = Self.farAway
        pump(host, for: 0.4) { !coordinator.isWatchingPointerForTesting }
        coordinator.buttonHoverChanged(false, composer: composer, anchor: anchor)
        coordinator.buttonHoverChanged(true, composer: composer, anchor: anchor)
        pump(host, for: 1.0) { coordinator.state.mode == .hoverOpen }
        XCTAssertEqual(coordinator.state.mode, .hoverOpen, "after the pointer left and came back it opens again")
    }

    /// A short window can put the picker over its own button. After Escape or a pick the button is uncovered under a
    /// pointer that has not moved: that must not open the picker again, and neither may leaving the button onto the
    /// picker's old place and coming back. Only a pointer seen outside both, then entering the button, does.
    func testShortWindowPickerOverItsButtonDoesNotReopenItself() throws {
        let (_, window, host, anchor, composer) = try realEmojiButtonSetup()
        let coordinator = EmojiPickerHoverCoordinator()
        var pointer = Self.farAway
        coordinator.pointerLocation = { pointer }
        defer {
            coordinator.dismiss()
            window.orderOut(nil)
            window.contentView = nil
        }
        coordinator.buttonHoverChanged(true, composer: composer, anchor: anchor)
        pump(host, for: 1.0) { coordinator.state.mode == .hoverOpen }
        XCTAssertEqual(coordinator.state.mode, .hoverOpen)
        let panel = try XCTUnwrap(coordinator.panelForTesting)
        let formerFrame = panel.frame
        let button = screenRect(of: anchor)
        // A point on the picker that is not on the button (the picker is 330 x 380 and the button 28 x 34).
        let onPickerOnly = [
            NSPoint(x: formerFrame.minX + 6, y: formerFrame.minY + 6),
            NSPoint(x: formerFrame.maxX - 6, y: formerFrame.maxY - 6),
            NSPoint(x: formerFrame.midX, y: formerFrame.midY),
        ].first { !NSMouseInRect($0, button, false) }
        let elsewhereOnPicker = try XCTUnwrap(onPickerOnly)

        // Escape, with the pointer where the button is (under the picker, or just uncovered by its closing).
        pointer = NSPoint(x: button.midX, y: button.midY)
        composer.isEmojiPickerPresented = false
        coordinator.syncPresented(false, composer: composer, anchor: anchor)
        pump(host, for: 0.4)
        coordinator.buttonHoverChanged(true, composer: composer, anchor: anchor) // the button is uncovered: "entered"
        pump(host, for: 0.5)
        XCTAssertEqual(coordinator.state.mode, .closed, "no reopening only because the button was uncovered")
        XCTAssertTrue(coordinator.state.isDisarmed)

        // Off the button but still on the picker's old place, and back onto the button: still not.
        pointer = elsewhereOnPicker
        coordinator.buttonHoverChanged(false, composer: composer, anchor: anchor)
        pump(host, for: 0.3)
        XCTAssertTrue(coordinator.state.isDisarmed, "the pointer is still on the former picker")
        pointer = NSPoint(x: button.midX, y: button.midY)
        coordinator.buttonHoverChanged(true, composer: composer, anchor: anchor)
        pump(host, for: 0.5)
        XCTAssertEqual(coordinator.state.mode, .closed)

        // Outside both, seen: armed. Entering the button opens it again.
        pointer = Self.farAway
        pump(host, for: 0.5) { !coordinator.state.isDisarmed }
        XCTAssertFalse(coordinator.state.isDisarmed)
        XCTAssertFalse(coordinator.isWatchingPointerForTesting, "it stops looking once it has seen it")
        coordinator.buttonHoverChanged(false, composer: composer, anchor: anchor)
        coordinator.buttonHoverChanged(true, composer: composer, anchor: anchor)
        pump(host, for: 1.0) { coordinator.state.mode == .hoverOpen }
        XCTAssertEqual(coordinator.state.mode, .hoverOpen)
    }

    /// A picker reopened while the last one is still fading out starts empty, not with the last search and scroll.
    func testPickerReopenedDuringItsFadeOutStartsFresh() throws {
        let (_, window, host, anchor, composer) = try realEmojiButtonSetup()
        let coordinator = EmojiPickerHoverCoordinator()
        coordinator.pointerLocation = { Self.farAway }
        defer {
            coordinator.dismiss()
            window.orderOut(nil)
            window.contentView = nil
        }
        coordinator.buttonClicked(composer: composer, anchor: anchor)
        let panel = try XCTUnwrap(coordinator.panelForTesting)
        let first = try XCTUnwrap(panel.contentView)
        composer.isEmojiPickerPresented = false
        coordinator.syncPresented(false, composer: composer, anchor: anchor) // starts the fade-out
        // Reopened at once, before the fade has finished.
        coordinator.buttonClicked(composer: composer, anchor: anchor)
        let second = try XCTUnwrap(panel.contentView)
        XCTAssertFalse(first === second, "the reopened picker is a new view, so its search box is empty")
        XCTAssertEqual(coordinator.state.mode, .pinned)
        pump(host, for: 0.4) // the old fade's late completion must not take the new picker down
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.contentView === second)
    }

    func testPendingHoverOpenDoesNotOpenOverTheNextChat() throws {
        let (_, window, host, anchor, composer) = try realEmojiButtonSetup()
        let coordinator = EmojiPickerHoverCoordinator()
        defer {
            coordinator.dismiss()
            window.orderOut(nil)
            window.contentView = nil
        }

        // The chat changes during the 0.15 s wait, and nothing tells the coordinator: the open still must not happen.
        coordinator.buttonHoverChanged(true, composer: composer, anchor: anchor)
        XCTAssertTrue(coordinator.hasPendingTimersForTesting)
        composer.open("!other:courier.local")
        pump(host, for: 0.6)
        XCTAssertEqual(coordinator.state.mode, .closed)
        XCTAssertFalse(composer.isEmojiPickerPresented)
        XCTAssertTrue(pickerPanels(of: window).isEmpty)

        // And a dismissal (what the view does when the chat changes or goes away) leaves no timer behind.
        composer.open(Fixture.room)
        coordinator.buttonHoverChanged(false, composer: composer, anchor: anchor)
        coordinator.buttonHoverChanged(true, composer: composer, anchor: anchor)
        XCTAssertTrue(coordinator.hasPendingTimersForTesting)
        coordinator.dismiss()
        XCTAssertFalse(coordinator.hasPendingTimersForTesting)
        pump(host, for: 0.5)
        XCTAssertEqual(coordinator.state.mode, .closed)
        XCTAssertTrue(pickerPanels(of: window).isEmpty)
    }

    // MARK: - Defect 5: hovering a row never moves or re-wraps its preview

    private func renderRow(_ row: InboxRow, width: CGFloat, hovered: Bool, style: RowStyle) throws
        -> (bitmap: NSBitmapImageRep, height: CGFloat)
    {
        let content = InboxRowView(
            row: row,
            networkName: "WhatsApp",
            now: Fixture.now,
            style: style,
            isSelecting: false,
            isSelected: false,
            isHovered: hovered,
            hoverAct: {},
            accept: {},
            decline: {}
        ) { EmptyView() }
        .padding(.horizontal, 12)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: content)
        host.appearance = NSAppearance(named: .aqua)
        let height = max(host.fittingSize.height, 1)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: width, height: height)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        defer { window.contentView = nil }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return (bitmap, height)
    }

    /// How many bytes differ between two renders in the columns left of `limitX` (in points).
    private func differingBytes(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, width: CGFloat, upTo limitX: CGFloat,
                                from startX: CGFloat = 0) -> Int {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
              let da = a.bitmapData, let db = b.bitmapData else { return Int.max }
        let scale = CGFloat(a.pixelsWide) / width
        let bytesPerPixel = a.bitsPerPixel / 8
        let from = Int(startX * scale)
        let to = min(Int(limitX * scale), a.pixelsWide)
        var count = 0
        for y in 0 ..< a.pixelsHigh {
            let rowA = da + y * a.bytesPerRow
            let rowB = db + y * b.bytesPerRow
            for x in from ..< to {
                for c in 0 ..< bytesPerPixel where rowA[x * bytesPerPixel + c] != rowB[x * bytesPerPixel + c] {
                    count += 1
                }
            }
        }
        return count
    }

    func testHoveringARowNeverMovesOrRewrapsItsPreviewAtAnyWidth() throws {
        let defaults = try makeDefaults()
        let style = RowStyle(InboxPreferences(defaults: defaults))
        XCTAssertEqual(style.hoverAction, .archive, "the default hover button is Archive")
        let preview = "Are we still meeting at the trailhead on Saturday morning, or should we move it to the café "
            + "near the lake so everyone can warm up first? Bring the spare map and a thermos if you have one."

        for unread in [0, 3] {
            let row = Fixture.row("!wrap", "Trail crew", ts: 5, preview: preview, unread: unread)
            var sawButton = false
            for width in stride(from: 250, through: 340, by: 1) {
                let w = CGFloat(width)
                let plain = try renderRow(row, width: w, hovered: false, style: style)
                let hovered = try renderRow(row, width: w, hovered: true, style: style)
                XCTAssertEqual(hovered.height, plain.height, "row height at width \(width), unread \(unread)")
                // Everything left of the right-hand 70 pt (the time, the marks and the button) is identical: the
                // preview neither re-wraps nor shifts.
                let moved = differingBytes(plain.bitmap, hovered.bitmap, width: w, upTo: w - 70)
                XCTAssertEqual(moved, 0, "the preview moved on hover at width \(width), unread \(unread)")
                if differingBytes(plain.bitmap, hovered.bitmap, width: w, upTo: w, from: w - 70) > 0 { sawButton = true }
                if moved != 0 { break }
            }
            XCTAssertTrue(sawButton, "hovering must draw something at the right (unread \(unread)): the check is live")
        }
    }
}

/// A device-owner check that always succeeds, so a test can lock and unlock the real lifecycle.
private struct UnlockingBiometricService: BiometricAuthService {
    func canEvaluateBiometricsOrWatch() -> Bool { true }
    func canEvaluateDeviceOwnerAuthentication() -> Bool { true }
    func authenticate(reason _: String) async throws -> Bool { true }
}
