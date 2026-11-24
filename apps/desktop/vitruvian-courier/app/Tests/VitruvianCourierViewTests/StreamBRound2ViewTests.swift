// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import ObjectiveC
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// Second review round: the inbox row with Reduce Motion on, and the hover archive button in the real chat list.
@MainActor
final class StreamBRound2ViewTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        for name in suites {
            ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name)
        }
        suites = []
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "courier.streamb.round2.\(UUID().uuidString)"
        suites.append(name)
        return try XCTUnwrap(ScratchDefaults.suite(named: name))
    }

    private func pump(_ view: NSView, for seconds: TimeInterval, until condition: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
            view.layoutSubtreeIfNeeded()
            if condition?() == true { break }
        }
    }

    /// Reduce Motion on for the life of the returned closure's owner: `NSWorkspace`'s answer is swapped for "yes".
    private func withReduceMotion(_ on: Bool, _ body: () throws -> Void) throws {
        guard on else { return try body() }
        let original = try XCTUnwrap(class_getInstanceMethod(
            NSWorkspace.self, #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceMotion)
        ))
        let stub = try XCTUnwrap(class_getInstanceMethod(
            NSWorkspace.self, #selector(getter: NSWorkspace.courierRound2_reduceMotionTrue)
        ))
        method_exchangeImplementations(original, stub)
        defer { method_exchangeImplementations(original, stub) }
        XCTAssertTrue(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        try body()
    }

    // MARK: - Row slot width under Reduce Motion

    private final class SelectingBox: ObservableObject {
        @Published var selecting = false
    }

    private struct SelectingRow: View {
        @ObservedObject var box: SelectingBox
        let row: InboxRow
        let style: RowStyle
        let width: CGFloat
        /// False forces motion on, whatever the machine says (CI's Macs run with Reduce Motion on); nil follows it.
        var reduceMotionOverride: Bool?

        var body: some View {
            InboxRowView(
                row: row,
                networkName: "WhatsApp",
                now: Fixture.now,
                style: style,
                isSelecting: box.selecting,
                isSelected: false,
                isHovered: false,
                hoverAct: {},
                accept: {},
                decline: {}
            ) { EmptyView() }
            .padding(.horizontal, 12)
            .frame(width: width, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.courierReduceMotionOverride, reduceMotionOverride)
        }
    }

    private func snapshot(_ host: NSView) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    /// How many bytes differ between two snapshots in the columns from `fromX` to `toX` (points).
    private func differingBytes(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, width: CGFloat, from fromX: CGFloat,
                                to toX: CGFloat) -> Int {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
              let da = a.bitmapData, let db = b.bitmapData else { return Int.max }
        let scale = CGFloat(a.pixelsWide) / width
        let bytesPerPixel = a.bitsPerPixel / 8
        var count = 0
        for y in 0 ..< a.pixelsHigh {
            let rowA = da + y * a.bytesPerRow
            let rowB = db + y * b.bytesPerRow
            for x in Int(fromX * scale) ..< min(Int(toX * scale), a.pixelsWide) {
                for c in 0 ..< bytesPerPixel where rowA[x * bytesPerPixel + c] != rowB[x * bytesPerPixel + c] {
                    count += 1
                }
            }
        }
        return count
    }

    /// Toggles multi-select on and off at each width and compares the row a moment after the change with the same row
    /// once it has settled, left of the right-hand 70 pt (where the marks fade) and right of the checkbox column. Text
    /// that re-wraps as the slot's width moves shows as a difference. Returns the widths where it moved.
    private func widthsWhereTheRowWasStillMoving(reduceMotion: Bool) throws -> [String] {
        let defaults = try makeDefaults()
        let style = RowStyle(InboxPreferences(defaults: defaults))
        let preview = "Are we still meeting at the trailhead on Saturday morning, or should we move it to the café "
            + "near the lake so everyone can warm up first? Bring the spare map and a thermos if you have one."
        let row = Fixture.row("!wrap", "Trail crew", ts: 5, preview: preview, unread: 3)
        var moving: [String] = []
        try withReduceMotion(reduceMotion) {
            for width in stride(from: 280, through: 336, by: 4) {
                let w = CGFloat(width)
                let box = SelectingBox()
                let host = NSHostingView(rootView: SelectingRow(box: box, row: row, style: style, width: w,
                                                                 reduceMotionOverride: reduceMotion ? nil : false))
                let window = NSWindow(
                    contentRect: NSRect(x: -10_000, y: -10_000, width: w, height: 140),
                    styleMask: [.borderless], backing: .buffered, defer: false
                )
                window.appearance = NSAppearance(named: .aqua)
                window.contentView = host
                host.frame = NSRect(x: 0, y: 0, width: w, height: 140)
                window.orderFrontRegardless()
                pump(host, for: 0.25)
                for entering in [true, false] {
                    box.selecting = entering
                    pump(host, for: 0.04)
                    let early = try snapshot(host)
                    pump(host, for: 0.6)
                    let settled = try snapshot(host)
                    let moved = differingBytes(early, settled, width: w, from: 48, to: w - 70)
                    if moved != 0 { moving.append("\(width) pt \(entering ? "entering" : "leaving") select") }
                }
                window.orderOut(nil)
                window.contentView = nil
            }
        }
        return moving
    }

    func testRowWidthIsInstantWithReduceMotionInBothDirectionsOfMultiSelect() throws {
        // Calibration: with motion on the same check does see the row moving, so it can see it.
        let animated = try widthsWhereTheRowWasStillMoving(reduceMotion: false)
        XCTAssertFalse(animated.isEmpty, "calibration: with motion on the row's width animates and the check sees it")

        let reduced = try widthsWhereTheRowWasStillMoving(reduceMotion: true)
        XCTAssertEqual(reduced, [], "with Reduce Motion on the row's width must change at once")
    }

    // MARK: - The real chat list

    private func offlineApp() -> AppModel {
        AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-round2"),
            environment: [:],
            launcher: FoundationProcessLauncher()
        ))
    }

    private func findNSView(in root: NSView, where predicate: (NSView) -> Bool) -> NSView? {
        root.descendants(where: predicate).first
    }

    private func click(at pointInWindow: NSPoint, in window: NSWindow) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: pointInWindow, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            NSApp.sendEvent(event)
        }
    }

    /// The row's hover button, in the app's own `InboxList` (its selection binding, its hover tracker and its row
    /// action), not a stand-in list: pressing it archives that chat and does not open it.
    func testRealInboxListHoverArchiveButtonArchivesWithoutOpeningTheChat() throws {
        _ = NSApplication.shared
        let defaults = try makeDefaults()
        let app = offlineApp()
        let preferences = InboxPreferences(defaults: defaults)
        let inbox = InboxModel(appModel: app, preferences: preferences)
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: defaults,
            bindToSharedGate: false
        )
        let spaces = SpacesModel(appModel: app, inbox: inbox, lifecycle: lifecycle)
        inbox.setSnapshotRowsForTesting([
            Fixture.row("!chat-a", "Alice", ts: 1, preview: "Currently open chat", unread: 0),
            Fixture.row("!chat-b", "Bob", ts: 2, preview: "Hover archive me", unread: 3),
        ])
        let size = NSSize(width: 340, height: 360)
        let host = NSHostingView(rootView: InboxList(
            inbox: inbox,
            spaces: spaces,
            preferences: preferences,
            composerPreferences: ComposerPreferences(defaults: defaults),
            ui: InboxUI(),
            hoveredRowIDForTesting: "!chat-b"
        ))
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }

        pump(host, for: 1.0) {
            self.findNSView(in: host) { $0.accessibilityIdentifier() == "inbox.row.hoverAction.!chat-b" } != nil
        }
        let catcher = try XCTUnwrap(
            findNSView(in: host) { $0.accessibilityIdentifier() == "inbox.row.hoverAction.!chat-b" },
            "the hover button of the real row"
        )
        XCTAssertNil(inbox.selectedRoomID)
        XCTAssertNil(inbox.toast)
        try click(
            at: catcher.convert(NSPoint(x: catcher.bounds.midX, y: catcher.bounds.midY), to: nil),
            in: window
        )
        // The archive is attempted (the engine is offline, so the inbox says it didn't work), on that chat only.
        pump(host, for: 1.0) { inbox.toast != nil }
        XCTAssertNotNil(inbox.toast, "pressing the hover button archives the chat")
        XCTAssertNil(inbox.selectedRoomID, "and does not open it")
    }
}

extension NSWorkspace {
    @objc fileprivate var courierRound2_reduceMotionTrue: Bool { true }
}
