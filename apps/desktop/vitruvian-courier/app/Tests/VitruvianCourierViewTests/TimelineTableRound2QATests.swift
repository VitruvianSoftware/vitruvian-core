// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// QA Round 2 coverage for overhanging action bar click forwarding, row-above clickability inside the hosting view's
/// top extension, and code-block text selection / mouse drag handling on `TimelineTableView`.
@MainActor
final class TimelineTableRound2QATests: XCTestCase {
    private var suites: [String] = []
    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        for name in suites {
            ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name)
        }
        suites = []
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs = []
    }

    private func makeDefaults() -> UserDefaults {
        let name = "courier.tableround2qa.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-table-r2-qa-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirs.append(url)
        return url
    }

    private func pump(_ host: NSView, for interval: TimeInterval, until condition: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded()
            if condition?() == true { break }
        }
    }

    // MARK: 1. Overhanging action bar click forwarding, single-fire, row-above clickability & deselection cleanup

    func testOverhangingActionBarForwardsOnceLeavesRowAboveClickableAndClearsOnDeselect() throws {
        _ = NSApplication.shared
        final class InteractionState: ObservableObject {
            @Published var selected: String?
            var replies: [String] = []
            var reactions: [(String, String)] = []
            var frames: [String: CGRect] = [:]
        }

        let state = InteractionState()
        let store = makeDefaults()
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: try makeTempDir(), environment: [:], launcher: FoundationProcessLauncher()
        ))
        let prefs = ComposerPreferences(defaults: store)
        prefs.timelineEngine = .table
        let conversation = ConversationModel(appModel: app, preferences: prefs)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(
            conversation: conversation, appModel: app, preferences: prefs, pasteboard: NoPasteboard()
        )
        let ui = MessageUI()

        // $m1 has a reaction chip at the bottom of its row (inside $m2's upward topExtension band when $m2 is selected).
        // $m2 is a wide continuation bubble from the same sender so its action bar overhangs into $m1's row.
        let items = Fixture.items([
            Fixture.text("$m1", "Short message above.", mine: false, ts: 10, sender: "@ann:courier.local", name: "Ann Example"),
            Fixture.event("$r1", type: "m.reaction", mine: false, ts: 9, content: [
                "m.relates_to": .object([
                    "rel_type": .string("m.annotation"), "event_id": .string("$m1"), "key": .string("👍"),
                ]),
            ], sender: "@bo:courier.local", name: "Bo Example"),
            Fixture.text(
                "$m2",
                "Second message from Ann that spans across the width of the chat column so its action bar overhangs above the bubble.",
                mine: false, ts: 8, sender: "@ann:courier.local", name: "Ann Example"
            ),
        ], isDirect: false)
        conversation.setSnapshotStateForTesting(
            roomID: "!r2-overhang",
            items: items,
            row: Fixture.row("!r2-overhang", "Overhang R2", network: "slack", direct: false, ts: 8, preview: "hi"),
            features: Fixture.features
        )

        struct OverhangR2Harness: View {
            @ObservedObject var conversation: ConversationModel
            @ObservedObject var messageActions: MessageActionsModel
            let prefs: ComposerPreferences
            let ui: MessageUI
            let app: AppModel
            let state: InteractionState

            var body: some View {
                let actions = VitruvianCourier.MessageActions(
                    select: { id in
                        conversation.selectedMessageID = id
                        state.selected = id
                    },
                    deselect: {
                        conversation.deselectMessage()
                        state.selected = nil
                    },
                    reply: { id in
                        state.replies.append(id)
                    },
                    react: { id, key in
                        state.reactions.append((id, key))
                    },
                    now: { Fixture.now }
                )
                TimelineTableView(
                    conversation: conversation,
                    messageActions: messageActions,
                    preferences: prefs,
                    ui: ui,
                    appModel: app,
                    actions: actions,
                    effectiveHeaderInset: 0,
                    bottomSafeAreaInset: 0,
                    bottomBarSignature: [],
                    resolvedAppearance: nil,
                    redact: false,
                    themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
                    drawsLiquidGlass: false,
                    timelineCovered: false
                )
                .onReceive(conversation.$selectedMessageID) { id in
                    if state.selected != id { state.selected = id }
                }
                .environment(\.conversationLayoutProbe) { name, frame in
                    if name.hasPrefix("item/") {
                        state.frames[String(name.dropFirst(5))] = frame
                    }
                }
                .environment(\.clickTargetProbe) { name, frame in
                    state.frames[name] = frame
                }
                .frame(width: 600, height: 340)
            }
        }

        let size = NSSize(width: 600, height: 340)
        let host = NSHostingView(rootView: OverhangR2Harness(
            conversation: conversation, messageActions: messageActions, prefs: prefs, ui: ui, app: app, state: state
        ))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        pump(host, for: 0.4) {
            state.frames["$m1"] != nil && state.frames["$m2"] != nil && state.frames["chip/$m1/👍"] != nil
        }
        pump(host, for: 0.15)

        func sendClick(at topOriginPoint: CGPoint) throws {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: NSEvent.doubleClickInterval + 0.08))
            let ts = ProcessInfo.processInfo.systemUptime
            let winPoint = NSPoint(x: topOriginPoint.x, y: host.bounds.height - topOriginPoint.y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let ev = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: winPoint, modifierFlags: [], timestamp: ts,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                ))
                NSApp.sendEvent(ev)
            }
            pump(host, for: 0.15)
        }

        // 1. Select $m2 and verify overhanging Reply fires exactly once.
        let m2Frame = try XCTUnwrap(state.frames["$m2"])
        try sendClick(at: CGPoint(x: m2Frame.midX, y: m2Frame.midY))
        try XCTSkipIf(state.selected == nil, "the window got no clicks (no window server for it here)")
        XCTAssertEqual(state.selected, "$m2")

        let replyBarFrame = try XCTUnwrap(state.frames["bar/Reply"])
        XCTAssertLessThan(replyBarFrame.midY, m2Frame.minY, "Reply button overhangs into $m1's row")
        let savedOverhangPoint = CGPoint(x: replyBarFrame.midX, y: replyBarFrame.midY)

        try sendClick(at: savedOverhangPoint)
        XCTAssertEqual(state.replies, ["$m2"], "overhanging Reply click must fire exactly once")
        XCTAssertEqual(state.selected, "$m2")

        // 2. While $m2's hostingView extends upward (topExtension > 0), clicking $m1's reaction chip inside the
        //    overhang band invokes react on $m1 without changing selection (MessageRowView carries a 2-click
        //    TapGesture, so child Buttons fire once doubleClickInterval elapses).
        let chipFrame = try XCTUnwrap(state.frames["chip/$m1/👍"])
        try sendClick(at: CGPoint(x: chipFrame.midX, y: chipFrame.midY))
        pump(host, for: NSEvent.doubleClickInterval + 0.12) { !state.reactions.isEmpty }
        XCTAssertEqual(state.reactions.count, 1, "reaction chip on row above ($m1) must remain clickable while $m2 overhangs")
        XCTAssertEqual(state.reactions.first?.0, "$m1")
        XCTAssertEqual(state.reactions.first?.1, "👍")
        XCTAssertEqual(state.selected, "$m2")

        // 3. While $m2's hostingView still extends upward, clicking $m1 inside the overhang band (away from $m2's
        //    overhanging bar) reaches $m1 and selects $m1.
        try sendClick(at: CGPoint(x: 180, y: m2Frame.minY - 8))
        XCTAssertEqual(state.selected, "$m1", "clicking $m1 inside the topExtension band away from the bar must select $m1")

        // 4. Re-select $m2, click overhanging Reply again, then verify empty-space click below $m2 deselects cleanly
        //    (forwardedMouseTarget is not stuck).
        try sendClick(at: CGPoint(x: m2Frame.midX, y: m2Frame.midY))
        XCTAssertEqual(state.selected, "$m2")
        try sendClick(at: savedOverhangPoint)
        XCTAssertEqual(state.replies, ["$m2", "$m2"])

        let m1Frame = try XCTUnwrap(state.frames["$m1"])
        let emptyY = m1Frame.minY - 45
        XCTAssertGreaterThan(emptyY, 0)
        try sendClick(at: CGPoint(x: 300, y: emptyY))
        XCTAssertNil(state.selected, "empty-space click after overhang forwarding must deselect")

        // 5. Once $m2 is deselected, clicking where $m2's overhanging bar used to be hits $m1, not a ghost bar.
        try sendClick(at: savedOverhangPoint)
        XCTAssertEqual(state.replies, ["$m2", "$m2"], "deselected row must not intercept clicks at its former overhanging bar rect")
        XCTAssertEqual(state.selected, "$m1", "clicking former overhang spot inside $m1's row selects $m1")
    }

    // MARK: 2. Text selection (code block) and mouse drag across rows do not break hit testing or row clicks

    func testCodeBlockSelectableTextAndMouseDragDoNotBreakRowSelection() throws {
        _ = NSApplication.shared
        final class DragState: ObservableObject {
            @Published var selected: String?
            var frames: [String: CGRect] = [:]
        }

        let state = DragState()
        let store = makeDefaults()
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: try makeTempDir(), environment: [:], launcher: FoundationProcessLauncher()
        ))
        let prefs = ComposerPreferences(defaults: store)
        prefs.timelineEngine = .table
        let conversation = ConversationModel(appModel: app, preferences: prefs)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(
            conversation: conversation, appModel: app, preferences: prefs, pasteboard: NoPasteboard()
        )
        let ui = MessageUI()

        let items = Fixture.items([
            Fixture.text(
                "$code",
                "let token = \"selectable_value_123\"",
                mine: false, ts: 10,
                html: "<pre><code>let token = \"selectable_value_123\"</code></pre>",
                sender: "@ann:courier.local", name: "Ann Example"
            ),
            Fixture.text(
                "$wide",
                "Wide continuation message below the code block whose action bar overhangs when selected.",
                mine: false, ts: 8, sender: "@ann:courier.local", name: "Ann Example"
            ),
        ], isDirect: false)
        conversation.setSnapshotStateForTesting(
            roomID: "!r2-drag",
            items: items,
            row: Fixture.row("!r2-drag", "Drag R2", network: "slack", direct: false, ts: 8, preview: "code"),
            features: Fixture.features
        )

        struct DragHarness: View {
            @ObservedObject var conversation: ConversationModel
            @ObservedObject var messageActions: MessageActionsModel
            let prefs: ComposerPreferences
            let ui: MessageUI
            let app: AppModel
            let state: DragState

            var body: some View {
                let actions = VitruvianCourier.MessageActions(
                    select: { id in
                        conversation.selectedMessageID = id
                        state.selected = id
                    },
                    deselect: {
                        conversation.deselectMessage()
                        state.selected = nil
                    },
                    now: { Fixture.now }
                )
                TimelineTableView(
                    conversation: conversation,
                    messageActions: messageActions,
                    preferences: prefs,
                    ui: ui,
                    appModel: app,
                    actions: actions,
                    effectiveHeaderInset: 0,
                    bottomSafeAreaInset: 0,
                    bottomBarSignature: [],
                    resolvedAppearance: nil,
                    redact: false,
                    themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
                    drawsLiquidGlass: false,
                    timelineCovered: false
                )
                .onReceive(conversation.$selectedMessageID) { id in
                    if state.selected != id { state.selected = id }
                }
                .environment(\.conversationLayoutProbe) { name, frame in
                    if name.hasPrefix("item/") {
                        state.frames[String(name.dropFirst(5))] = frame
                    }
                }
                .frame(width: 600, height: 340)
            }
        }

        let size = NSSize(width: 600, height: 340)
        let host = NSHostingView(rootView: DragHarness(
            conversation: conversation, messageActions: messageActions, prefs: prefs, ui: ui, app: app, state: state
        ))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        pump(host, for: 0.4) { state.frames["$code"] != nil && state.frames["$wide"] != nil }
        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)

        func sendClick(at topOriginPoint: CGPoint) throws {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: NSEvent.doubleClickInterval + 0.08))
            let ts = ProcessInfo.processInfo.systemUptime
            let winPoint = NSPoint(x: topOriginPoint.x, y: host.bounds.height - topOriginPoint.y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let ev = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: winPoint, modifierFlags: [], timestamp: ts,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                ))
                NSApp.sendEvent(ev)
            }
            pump(host, for: 0.15)
        }

        // Select $wide first so an overhanging bar exists below $code.
        let wideFrame = try XCTUnwrap(state.frames["$wide"])
        try sendClick(at: CGPoint(x: wideFrame.midX, y: wideFrame.midY))
        try XCTSkipIf(state.selected == nil, "the window got no clicks (no window server for it here)")
        XCTAssertEqual(state.selected, "$wide")

        // Verify hitTest inside $code lands inside $code's row view, not $wide's row view.
        let codeFrame = try XCTUnwrap(state.frames["$code"])
        let codeRowIdx = try XCTUnwrap(coordinator.entries.firstIndex { $0.id == "$code" })
        let codeRowView = try XCTUnwrap(tableView.rowView(atRow: codeRowIdx, makeIfNecessary: false))
        let codeTablePoint = tableView.convert(
            NSPoint(x: 90, y: host.bounds.height - codeFrame.midY),
            from: nil
        )
        let hitInCode = try XCTUnwrap(tableView.hitTest(NSPoint(x: codeTablePoint.x, y: codeTablePoint.y)))
        XCTAssertTrue(hitInCode.isDescendant(of: codeRowView), "hitTest on code block row must resolve inside $code's row view")

        // Perform a mouse drag across the code block text (leftMouseDown -> leftMouseDragged -> leftMouseUp).
        RunLoop.main.run(until: Date(timeIntervalSinceNow: NSEvent.doubleClickInterval + 0.08))
        let ts = ProcessInfo.processInfo.systemUptime
        let startWin = NSPoint(x: 70, y: host.bounds.height - codeFrame.midY)
        let midWin = NSPoint(x: 150, y: host.bounds.height - codeFrame.midY)
        let endWin = NSPoint(x: 230, y: host.bounds.height - codeFrame.midY)

        NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: startWin, modifierFlags: [], timestamp: ts,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        )))
        NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDragged, location: midWin, modifierFlags: [], timestamp: ts + 0.02,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        )))
        NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDragged, location: endWin, modifierFlags: [], timestamp: ts + 0.04,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        )))
        NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp, location: endWin, modifierFlags: [], timestamp: ts + 0.06,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        )))
        pump(host, for: 0.15)

        // Subsequent normal clicks on empty space and rows must continue to work cleanly.
        let emptyAfterDragY = codeFrame.minY - 45
        XCTAssertGreaterThan(emptyAfterDragY, 0)
        try sendClick(at: CGPoint(x: 300, y: emptyAfterDragY))
        XCTAssertNil(state.selected, "empty-space click after drag must deselect")
        try sendClick(at: CGPoint(x: wideFrame.midX, y: wideFrame.midY))
        XCTAssertEqual(state.selected, "$wide", "row click after drag must still select $wide")
    }
}
