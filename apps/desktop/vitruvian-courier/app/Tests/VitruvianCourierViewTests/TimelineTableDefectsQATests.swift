// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// Targeted QA tests reproducing defects found during review of `TimelineTableView`.
@MainActor
final class TimelineTableDefectsQATests: XCTestCase {
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
        let name = "courier.tabledefects.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-table-defects-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: Defect 1 — Overhanging hover action bar clicks on wide bubbles miss the bar and select the row above

    func testOverhangingActionBarClickOnWideBubbleHitsReplyInsteadOfSelectingRowAbove() throws {
        _ = NSApplication.shared
        final class ClickState: ObservableObject {
            @Published var selected: String?
            @Published var repliedTo: String?
            var frames: [String: CGRect] = [:]
        }

        let state = ClickState()
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

        // Two consecutive incoming messages from the same sender: $m2 has startsGroup == false and a wide bubble,
        // so MessageActionBarPlacement places its action bar over its top corner overhanging into $m1's row.
        let items = Fixture.items([
            Fixture.text("$m1", "Short message above.", mine: false, ts: 10, sender: "@ann:courier.local", name: "Ann Example"),
            Fixture.text(
                "$m2",
                "Second message from Ann that spans across the width of the chat column so its action bar overhangs above the bubble.",
                mine: false, ts: 10, sender: "@ann:courier.local", name: "Ann Example"
            ),
        ], isDirect: false)
        conversation.setSnapshotStateForTesting(
            roomID: "!overhang",
            items: items,
            row: Fixture.row("!overhang", "Overhang", network: "slack", direct: false, ts: 10, preview: "hi"),
            features: Fixture.features
        )

        struct OverhangHarness: View {
            @ObservedObject var conversation: ConversationModel
            @ObservedObject var messageActions: MessageActionsModel
            let prefs: ComposerPreferences
            let ui: MessageUI
            let app: AppModel
            let state: ClickState

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
                        state.repliedTo = id
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
                .environment(\.conversationLayoutProbe) { name, frame in
                    if name.hasPrefix("item/") {
                        state.frames[String(name.dropFirst(5))] = frame
                    }
                }
                .environment(\.clickTargetProbe) { name, frame in
                    state.frames[name] = frame
                }
                .frame(width: 600, height: 300)
            }
        }

        let size = NSSize(width: 600, height: 300)
        let host = NSHostingView(rootView: OverhangHarness(
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

        pump(host, for: 0.4) { state.frames["$m1"] != nil && state.frames["$m2"] != nil }

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

        let m2Frame = try XCTUnwrap(state.frames["$m2"])
        try sendClick(at: CGPoint(x: m2Frame.midX, y: m2Frame.midY))
        try XCTSkipIf(state.selected == nil, "the window got no clicks (no window server for it here)")
        XCTAssertEqual(state.selected, "$m2")

        let replyBarFrame = try XCTUnwrap(state.frames["bar/Reply"], "action bar Reply button must be laid out")
        XCTAssertLessThan(replyBarFrame.midY, m2Frame.minY, "wide continuation bubble's Reply button overhangs above $m2's row")

        try sendClick(at: CGPoint(x: replyBarFrame.midX, y: replyBarFrame.midY))
        XCTAssertEqual(state.selected, "$m2", "clicking $m2's overhanging Reply button must keep $m2 selected, not select $m1")
        XCTAssertEqual(state.repliedTo, "$m2", "clicking $m2's overhanging Reply button must invoke Reply on $m2")
    }

    // MARK: Defect 2 — Width resize leaves conversation.isAtBottom and layout probes stale

    func testWideningWindowUpdatesBottomStateAndLayoutProbes() throws {
        _ = NSApplication.shared
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

        let events = (1 ... 10).map { idx in
            Fixture.text(
                "$w\(idx)",
                "Message #\(idx) with enough words that at 360pt width it wraps across multiple lines, making the chat taller than 320pt, whereas at 1000pt width all ten fit near the bottom.",
                mine: idx % 2 == 0,
                ts: 30 - idx
            )
        }
        conversation.setSnapshotStateForTesting(
            roomID: "!resize",
            items: Fixture.items(events, isDirect: false),
            row: Fixture.row("!resize", "Resize", network: "slack", direct: false, ts: 1, preview: "hi"),
            features: Fixture.features
        )

        var probeFrames: [String: CGRect] = [:]
        struct ResizeRoot: View {
            @ObservedObject var conversation: ConversationModel
            @ObservedObject var messageActions: MessageActionsModel
            let prefs: ComposerPreferences
            let ui: MessageUI
            let app: AppModel

            var body: some View {
                let actions = MessageRowActions.make(
                    conversation: conversation, messageActions: messageActions,
                    preferences: prefs, composer: conversation.composer, ui: ui, source: .chat,
                    deselect: { conversation.deselectMessage() },
                    select: { conversation.selectedMessageID = $0 }
                )
                TimelineTableView(
                    conversation: conversation, messageActions: messageActions,
                    preferences: prefs, ui: ui, appModel: app, actions: actions,
                    effectiveHeaderInset: 0, bottomSafeAreaInset: 0, bottomBarSignature: [],
                    resolvedAppearance: nil, redact: false,
                    themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
                    drawsLiquidGlass: false, timelineCovered: false
                )
            }
        }

        let narrow = NSSize(width: 360, height: 360)
        let host = NSHostingView(rootView: ResizeRoot(
            conversation: conversation, messageActions: messageActions, prefs: prefs, ui: ui, app: app
        ).environment(\.conversationLayoutProbe) { name, rect in probeFrames[name] = rect })
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: narrow), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: narrow)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        pump(host, for: 0.35) { host.first(TimelineNSTableView.self) != nil }
        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let scrollView = try XCTUnwrap(host.first(NSScrollView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        pump(host, for: 0.2)

        // Scroll slightly up at 360pt width so conversation.isAtBottom flips to false.
        coordinator.noteUserScrollForTesting()
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: max(0, clip.bounds.origin.y - 80)))
        scrollView.reflectScrolledClipView(clip)
        pump(host, for: 0.25)
        XCTAssertFalse(conversation.isAtBottom, "scrolling up 80pt at narrow width leaves bottom")

        // Widen window to 1100pt x 360pt (pure horizontal width resize) so unwrapped rows shrink and bring bottom into view.
        let wide = NSSize(width: 1100, height: 360)
        window.setContentSize(wide)
        host.frame = NSRect(origin: .zero, size: wide)
        host.layoutSubtreeIfNeeded()
        pump(host, for: 0.35) // > 100ms resize debounce

        let lastRowMaxY = tableView.rect(ofRow: coordinator.entries.count - 1).maxY
        XCTAssertGreaterThanOrEqual(
            clip.bounds.maxY - scrollView.contentInsets.bottom, lastRowMaxY - 2,
            "widening the window brings the last row completely into view at the bottom"
        )
        XCTAssertTrue(
            conversation.isAtBottom,
            "when width resize brings the newest message back into view at the bottom, conversation.isAtBottom must update to true"
        )
        let probedWidth = try XCTUnwrap(probeFrames["item/$w10"]?.width)
        XCTAssertEqual(probedWidth, 1100, accuracy: 30, "layout probe must report post-resize row width")
    }

    // MARK: Defect 3 — Prepend anchor clamping jumps viewport when explicit anchor is off-screen above

    func testLateEarlierPrependWhileScrolledDownKeepsCurrentViewportWithoutJumpingToTop() throws {
        _ = NSApplication.shared
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

        let currentEvents = (1 ... 30).map { idx in
            Fixture.text("$c\(idx)", "Current message #\(idx) in the middle/bottom of the chat", mine: idx % 2 == 0, ts: 60 - idx)
        }
        conversation.setSnapshotStateForTesting(
            roomID: "!prepend-jump",
            items: Fixture.items(currentEvents, isDirect: false),
            row: Fixture.row("!prepend-jump", "Prepend Jump", network: "whatsapp", direct: false, ts: 1, preview: "hi"),
            features: Fixture.features,
            hasOlder: false
        )

        struct PrependRoot: View {
            @ObservedObject var conversation: ConversationModel
            @ObservedObject var messageActions: MessageActionsModel
            let prefs: ComposerPreferences
            let ui: MessageUI
            let app: AppModel

            var body: some View {
                let actions = MessageRowActions.make(
                    conversation: conversation, messageActions: messageActions,
                    preferences: prefs, composer: conversation.composer, ui: ui, source: .chat,
                    deselect: { conversation.deselectMessage() },
                    select: { conversation.selectedMessageID = $0 }
                )
                TimelineTableView(
                    conversation: conversation, messageActions: messageActions,
                    preferences: prefs, ui: ui, appModel: app, actions: actions,
                    effectiveHeaderInset: 48, bottomSafeAreaInset: 0, bottomBarSignature: [],
                    resolvedAppearance: nil, redact: false,
                    themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
                    drawsLiquidGlass: false, timelineCovered: false
                )
            }
        }

        let size = NSSize(width: 640, height: 320)
        let host = NSHostingView(rootView: PrependRoot(
            conversation: conversation, messageActions: messageActions, prefs: prefs, ui: ui, app: app
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

        pump(host, for: 0.35) { host.first(TimelineNSTableView.self) != nil }
        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let scrollView = try XCTUnwrap(host.first(NSScrollView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        pump(host, for: 0.25)

        // Scroll to the middle of the chat so $c1 is far above the viewport (screenMinY << 0) and $c20 is visible.
        coordinator.noteUserScrollForTesting()
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: max(0, clip.bounds.origin.y - 260)))
        scrollView.reflectScrolledClipView(clip)
        pump(host, for: 0.25)

        let visible = tableView.rows(in: tableView.visibleRect)
        let watchedID = coordinator.entries[visible.location + visible.length / 2].id
        func watchedScreenMinY() throws -> CGFloat {
            let row = try XCTUnwrap(coordinator.entries.firstIndex { $0.id == watchedID })
            return host.convert(tableView.rect(ofRow: row), from: tableView).minY
        }
        let beforeMinY = try watchedScreenMinY()

        // Simulate ConversationModel.readEarlier() delivering a late network page: earlierAnchorID = firstMessageID ($c1).
        let earlierEvents = (1 ... 10).map { idx in
            Fixture.text("$e\(idx)", "Earlier synced message #\(idx)", mine: false, ts: 200 - idx)
        }
        conversation.setEarlierAnchorForTesting("$c1")
        conversation.setSnapshotItemsForTesting(Fixture.items(earlierEvents + currentEvents, isDirect: false), hasOlder: false)
        pump(host, for: 0.25)

        XCTAssertEqual(
            try watchedScreenMinY(),
            beforeMinY,
            accuracy: 1.0,
            "late earlier-history prepend while scrolled down must keep visible rows in place rather than clamping off-screen $c1 to topInset"
        )
    }

    // MARK: Defect 4 — Stale lastReportedProbeRects suppresses probe when row scrolls out and returns to same rect

    func testLayoutProbeReportsRowAgainAfterScrollingOffscreenAndReturningToSameRect() throws {
        _ = NSApplication.shared
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

        let events = (1 ... 35).map { idx in
            Fixture.text("$p\(idx)", "Probe test message #\(idx)", mine: idx % 2 == 0, ts: 70 - idx)
        }
        conversation.setSnapshotStateForTesting(
            roomID: "!probe-stale",
            items: Fixture.items(events, isDirect: false),
            row: Fixture.row("!probe-stale", "Probe Stale", network: "slack", direct: false, ts: 1, preview: "hi"),
            features: Fixture.features
        )

        var frames: [String: CGRect] = [:]
        let root = TimelineTableView(
            conversation: conversation,
            messageActions: messageActions,
            preferences: prefs,
            ui: ui,
            appModel: app,
            actions: MessageActions(),
            effectiveHeaderInset: 48,
            bottomSafeAreaInset: 0,
            bottomBarSignature: [],
            resolvedAppearance: nil,
            redact: false,
            themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
            drawsLiquidGlass: false,
            timelineCovered: false
        )
        .environment(\.conversationLayoutProbe) { name, rect in
            frames[name] = rect
        }

        let size = NSSize(width: 640, height: 320)
        let host = NSHostingView(rootView: root)
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

        pump(host, for: 0.35) { host.first(TimelineNSTableView.self) != nil }
        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let scrollView = try XCTUnwrap(host.first(NSScrollView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        pump(host, for: 0.2)

        // Scroll to exact top -> $p1 is reported at its top rect.
        let clip = scrollView.contentView
        let topY = tableView.bounds.minY - scrollView.contentInsets.top
        coordinator.noteUserScrollForTesting()
        clip.scroll(to: NSPoint(x: 0, y: topY))
        scrollView.reflectScrolledClipView(clip)
        pump(host, for: 0.15)
        XCTAssertNotNil(frames["item/$p1"])

        // Scroll to bottom so $p1 leaves visibleRange completely, clear recorded frames, then scroll back to topY.
        let maxY = max(topY, tableView.bounds.maxY + scrollView.contentInsets.bottom - clip.bounds.height)
        coordinator.noteUserScrollForTesting()
        clip.scroll(to: NSPoint(x: 0, y: maxY))
        scrollView.reflectScrolledClipView(clip)
        pump(host, for: 0.15)
        frames.removeAll()

        coordinator.noteUserScrollForTesting()
        clip.scroll(to: NSPoint(x: 0, y: topY))
        scrollView.reflectScrolledClipView(clip)
        pump(host, for: 0.15)

        XCTAssertNotNil(
            frames["item/$p1"],
            "re-entering viewport at topY after scrolling off-screen must report item/$p1 again"
        )
    }

    // MARK: Defect 5 — Bridged GIF without metadata dimensions stays clipped at 180pt fallback height in table row

    func testBridgedGIFWithoutDimensionsUpdatesTableRowHeightAfterLoad() throws {
        _ = NSApplication.shared
        let dir = try makeTempDir()
        let gifURL = dir.appendingPathComponent("square.gif")

        // Write a 400x400 GIF file on disk.
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        let cg = try XCTUnwrap(ctx.makeImage())
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        // Bridged GIF event missing w/h in info (common for bridged media).
        var gifEvent = Fixture.event("$gif1", mine: false, ts: 10, content: [
            "msgtype": .string("m.image"),
            "body": .string("square.gif"),
            "filename": .string("square.gif"),
            "url": .string("mxc://courier.local/fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"),
            "info": .object([
                "mimetype": .string("image/gif"),
                "is_animated": .bool(true),
                "fi.mau.gif": .bool(true),
            ]),
        ])
        gifEvent.mediaPath = gifURL.path
        gifEvent.isGIF = true
        gifEvent.isAnimated = true

        let items = Fixture.items([
            gifEvent,
            Fixture.text("$after", "Message below the GIF", mine: true, ts: 5),
        ], isDirect: false)

        let store = makeDefaults()
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: dir, environment: [:], launcher: FoundationProcessLauncher()
        ))
        let prefs = ComposerPreferences(defaults: store)
        prefs.timelineEngine = .table
        let conversation = ConversationModel(appModel: app, preferences: prefs)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(
            conversation: conversation, appModel: app, preferences: prefs, pasteboard: NoPasteboard()
        )
        let ui = MessageUI()
        conversation.setSnapshotStateForTesting(
            roomID: "!gif-row",
            items: items,
            row: Fixture.row("!gif-row", "GIF Row", network: "whatsapp", direct: false, ts: 5, preview: "gif"),
            features: Fixture.features
        )

        let root = TimelineTableView(
            conversation: conversation, messageActions: messageActions,
            preferences: prefs, ui: ui, appModel: app, actions: MessageActions(),
            effectiveHeaderInset: 0, bottomSafeAreaInset: 0, bottomBarSignature: [],
            resolvedAppearance: nil, redact: false,
            themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
            drawsLiquidGlass: false, timelineCovered: false
        )

        let size = NSSize(width: 640, height: 600)
        let host = NSHostingView(rootView: root)
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

        pump(host, for: 0.4) { host.first(TimelineNSTableView.self) != nil }
        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        // Allow GIFAttachmentView's detached NSImage decode task to complete.
        pump(host, for: 0.5)

        let gifRow = try XCTUnwrap(coordinator.entries.firstIndex { $0.id == "$gif1" })
        let gifRowHeight = tableView.rect(ofRow: gifRow).height
        XCTAssertGreaterThanOrEqual(
            gifRowHeight, 400,
            "400x400 bridged GIF without metadata dimensions must expand its table row height (>= 400pt), got \(gifRowHeight)"
        )
    }
}
