// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

@MainActor
final class StreamBHoverAndTooltipViewTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        CourierTooltipController.shared.dismiss()
        for name in suites {
            ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name)
        }
        suites = []
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "courier.streamb.\(UUID().uuidString)"
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

    private func findNSView(in root: NSView, where predicate: (NSView) -> Bool) -> NSView? {
        if predicate(root) { return root }
        for subview in root.subviews {
            if let found = findNSView(in: subview, where: predicate) { return found }
        }
        return nil
    }

    // MARK: - Items 3 & 4: Tooltip stays inside window & never steals clicks or focus

    func testEmojiTooltipNearWindowEdgeStaysInsideWindowAndNeverStealsFocusOrClicks() throws {
        _ = NSApplication.shared

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
        let windowSize = NSSize(width: 900, height: 600)
        let root = VStack {
            Spacer()
            HStack {
                Spacer()
                Color.clear
                    .frame(width: 28, height: 34)
                    .background(ProbeAnchor(box: probe))
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 10)
        .frame(width: windowSize.width, height: windowSize.height)

        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: windowSize)
        window.orderFrontRegardless()
        defer {
            CourierTooltipController.shared.dismiss()
            window.orderOut(nil)
            window.contentView = nil
        }

        pump(host, for: 0.25) { probe.view != nil && probe.view?.window != nil }
        let anchor = try XCTUnwrap(probe.view)

        let placedCardFrame = try XCTUnwrap(
            CourierTooltipController.shared.presentNowForTesting(
                content: CourierTooltipContent(
                    title: "Emoji",
                    shortcut: "⌃⌘Space",
                    detail: "Opens Emoji & Symbols",
                    edge: .top
                ),
                anchorView: anchor
            )
        )

        let margin = CourierTooltipPlacement.windowMargin
        XCTAssertGreaterThanOrEqual(placedCardFrame.minX, margin - 0.5)
        XCTAssertLessThanOrEqual(placedCardFrame.maxX, windowSize.width - margin + 0.5)
        XCTAssertGreaterThanOrEqual(placedCardFrame.minY, margin - 0.5)
        XCTAssertLessThanOrEqual(placedCardFrame.maxY, windowSize.height - margin + 0.5)

        let panel = try XCTUnwrap(CourierTooltipController.shared.activePanelForTesting)
        XCTAssertTrue(panel.ignoresMouseEvents, "tooltip panel must never intercept clicks")
        XCTAssertFalse(panel.canBecomeKey, "tooltip panel must never steal key focus")
        XCTAssertFalse(panel.canBecomeMain, "tooltip panel must never become main")

        let cardInWindow = window.convertFromScreen(panel.frame)
            .insetBy(dx: CourierTooltipView.shadowInset, dy: CourierTooltipView.shadowInset)
        XCTAssertGreaterThanOrEqual(cardInWindow.minX, margin - 0.5)
        XCTAssertLessThanOrEqual(cardInWindow.maxX, windowSize.width - margin + 0.5)
        XCTAssertGreaterThanOrEqual(cardInWindow.minY, margin - 0.5)
        XCTAssertLessThanOrEqual(cardInWindow.maxY, windowSize.height - margin + 0.5)
    }

    // MARK: - Item 2: Clicking hover archive archives only that chat and does not open it

    func testHoverArchiveClickArchivesOnlyTargetChatWithoutOpeningIt() throws {
        _ = NSApplication.shared
        let defaults = try makeDefaults()
        let style = RowStyle(InboxPreferences(defaults: defaults))

        let rowA = Fixture.row("!chat-a", "Alice", ts: 1, preview: "Currently open chat", unread: 0)
        let rowB = Fixture.row("!chat-b", "Bob", ts: 2, preview: "Hover archive me", unread: 3)

        final class HarnessState: ObservableObject {
            @Published var selectedRoomID: String? = "!chat-a"
            @Published var archivedIDs: [String] = []
        }

        struct ListHarness: View {
            @ObservedObject var state: HarnessState
            let rows: [InboxRow]
            let style: RowStyle

            var body: some View {
                List(selection: Binding(
                    get: { state.selectedRoomID },
                    set: { next in
                        if let next { state.selectedRoomID = next }
                    }
                )) {
                    ForEach(rows) { row in
                        InboxRowView(
                            row: row,
                            networkName: "WhatsApp",
                            now: Fixture.now,
                            style: style,
                            isSelecting: false,
                            isSelected: state.selectedRoomID == row.id,
                            isHovered: row.id == "!chat-b",
                            hoverAct: { state.archivedIDs.append(row.id) },
                            accept: {},
                            decline: {}
                        ) { EmptyView() }
                        .tag(row.id)
                    }
                }
                .listStyle(.inset)
            }
        }

        let state = HarnessState()
        let host = NSHostingView(rootView: ListHarness(state: state, rows: [rowA, rowB], style: style))
        let windowSize = NSSize(width: 340, height: 220)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: windowSize)
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        pump(host, for: 0.4) {
            self.findNSView(in: host) { $0.accessibilityIdentifier() == "inbox.row.hoverAction.!chat-b" } != nil
        }

        let hoverCatcher = try XCTUnwrap(
            findNSView(in: host) { $0.accessibilityIdentifier() == "inbox.row.hoverAction.!chat-b" }
        )
        let centerInWindow = hoverCatcher.convert(
            NSPoint(x: hoverCatcher.bounds.midX, y: hoverCatcher.bounds.midY),
            to: nil
        )
        for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let clickEvent = try XCTUnwrap(NSEvent.mouseEvent(
                with: eventType,
                location: centerInWindow,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
            NSApp.sendEvent(clickEvent)
        }

        pump(host, for: 0.15) { state.archivedIDs == ["!chat-b"] }
        XCTAssertEqual(state.archivedIDs, ["!chat-b"], "clicking hover archive must archive only chat B")
        XCTAssertEqual(state.selectedRoomID, "!chat-a", "clicking hover archive must NOT open chat B")
    }

    // MARK: - Item 5: Hovering emoji opens picker without stealing focus from composer text box

    func testEmojiPickerHoverOpenDoesNotStealFocusFromComposerTextBox() throws {
        _ = NSApplication.shared
        let defaults = try makeDefaults()
        let preferences = ComposerPreferences(defaults: defaults)
        let composer = ComposerModel(
            sender: SnapshotMessageSender(),
            draftDelay: 0,
            sleep: { _ in },
            preferences: preferences
        )
        composer.open(Fixture.room)
        composer.features = Fixture.features
        composer.network = "whatsapp"

        let coordinator = EmojiPickerHoverCoordinator()
        defer { coordinator.dismiss() }

        final class AnchorHolder { weak var view: NSView? }
        struct AnchorProbe: NSViewRepresentable {
            let holder: AnchorHolder
            func makeNSView(context _: Context) -> NSView {
                let v = NSView()
                holder.view = v
                return v
            }
            func updateNSView(_ v: NSView, context _: Context) { holder.view = v }
        }
        let anchorHolder = AnchorHolder()

        let root = VStack {
            Spacer()
            HStack {
                ComposerView(
                    composer: composer,
                    preferences: preferences,
                    textHeight: .constant(ComposerTextView.minimumHeight)
                )
                Color.clear
                    .frame(width: 28, height: 28)
                    .background(AnchorProbe(holder: anchorHolder))
            }
        }
        .frame(width: 620, height: 220)

        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: NSSize(width: 620, height: 220)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: NSSize(width: 620, height: 220))
        window.makeKeyAndOrderFront(nil)
        defer {
            coordinator.dismiss()
            window.orderOut(nil)
            window.contentView = nil
        }

        pump(host, for: 0.25) {
            host.first(PlainTextView.self) != nil && anchorHolder.view != nil
        }
        let textView = try XCTUnwrap(host.first(PlainTextView.self))
        let anchor = try XCTUnwrap(anchorHolder.view)
        window.makeFirstResponder(textView)
        pump(host, for: 0.1) { window.firstResponder === textView }
        XCTAssertTrue(window.firstResponder === textView)

        XCTAssertTrue(coordinator.openFromHoverForTesting(composer: composer, anchor: anchor))
        pump(host, for: 0.1)

        XCTAssertTrue(composer.isEmojiPickerPresented)
        XCTAssertTrue(coordinator.isIconAccented)
        XCTAssertEqual(coordinator.state.mode, .hoverOpen)
        let panel = try XCTUnwrap(coordinator.panelForTesting)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow, "hover-opened emoji picker must not take key focus")
        XCTAssertTrue(window.firstResponder === textView, "composer text view must keep keyboard focus")
    }

    // MARK: - Items 2, 3, 10, 18: Snapshot smoke renders (light & dark)

    func testStreamBViewsRenderLightAndDarkSnapshots() throws {
        let defaults = try makeDefaults()
        let style = RowStyle(InboxPreferences(defaults: defaults))
        let preferences = ComposerPreferences(defaults: defaults)

        let hoveredRow = Fixture.row("!h1", "Hovered Chat", ts: 3, preview: "Hover button sits under time", unread: 4)
        let archivedRow = InboxRow(
            roomID: "!h2",
            network: "signal",
            name: "Archived Chat",
            avatarPath: "",
            isDirect: true,
            lastTS: Fixture.millis(12),
            preview: "Click to unarchive",
            previewKind: .text,
            previewMine: false,
            unread: 0,
            muted: false,
            archived: true
        )

        let rowSizes = try Snapshot.render("stream-b-inbox-rows", width: 340) {
            VStack(spacing: 0) {
                InboxRowView(
                    row: hoveredRow,
                    networkName: "WhatsApp",
                    now: Fixture.now,
                    style: style,
                    isSelecting: false,
                    isSelected: false,
                    isHovered: true,
                    hoverAct: {},
                    accept: {},
                    decline: {}
                ) { EmptyView() }
                .padding(.horizontal, 10)
                Divider()
                InboxRowView(
                    row: archivedRow,
                    networkName: "Signal",
                    now: Fixture.now,
                    style: style,
                    isSelecting: false,
                    isSelected: false,
                    isHovered: true,
                    hoverAct: {},
                    accept: {},
                    decline: {}
                ) { EmptyView() }
                .padding(.horizontal, 10)
                Divider()
                InboxRowView(
                    row: hoveredRow,
                    networkName: "WhatsApp",
                    now: Fixture.now,
                    style: style,
                    isSelecting: true,
                    isSelected: true,
                    isHovered: true,
                    hoverAct: {},
                    accept: {},
                    decline: {}
                ) { EmptyView() }
                .padding(.horizontal, 10)
            }
        }
        XCTAssertEqual(rowSizes.count, 2)

        let tooltipSizes = try Snapshot.render("stream-b-tooltip", width: 260) {
            CourierTooltipView(
                content: CourierTooltipContent(
                    title: "Emoji",
                    shortcut: "⌃⌘Space",
                    detail: "Opens Emoji & Symbols",
                    edge: .top
                )
            )
        }
        XCTAssertEqual(tooltipSizes.count, 2)

        let emptyComposer = ComposerModel(
            sender: SnapshotMessageSender(),
            draftDelay: 0,
            sleep: { _ in },
            preferences: preferences
        )
        emptyComposer.open(Fixture.room)
        emptyComposer.features = Fixture.features
        emptyComposer.network = "whatsapp"

        let readyComposer = ComposerModel(
            sender: SnapshotMessageSender(),
            draftDelay: 0,
            sleep: { _ in },
            preferences: preferences
        )
        readyComposer.open(Fixture.room)
        readyComposer.features = Fixture.features
        readyComposer.network = "whatsapp"
        readyComposer.text = "Ready to send"

        let composerSizes = try Snapshot.render("stream-b-composer-send-states", width: 580) {
            VStack(spacing: 12) {
                ComposerView(
                    composer: emptyComposer,
                    preferences: preferences,
                    textHeight: .constant(ComposerTextView.minimumHeight)
                )
                ComposerView(
                    composer: readyComposer,
                    preferences: preferences,
                    textHeight: .constant(ComposerTextView.minimumHeight)
                )
            }
        }
        XCTAssertEqual(composerSizes.count, 2)
    }
}
