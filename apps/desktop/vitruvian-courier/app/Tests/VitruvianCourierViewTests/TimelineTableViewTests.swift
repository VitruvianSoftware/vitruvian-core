// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

@MainActor
final class TimelineTableViewTests: XCTestCase {
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
        let name = "courier.tabletests.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-table-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirs.append(url)
        return url
    }

    private func offlineApp(dataDir: URL? = nil) -> AppModel {
        let dir = dataDir ?? FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-table-tests")
        return AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: dir,
            environment: [:],
            launcher: FoundationProcessLauncher()
        ))
    }

    /// Re-renders its content whenever the conversation (or the message actions) publishes, as `ConversationView` does.
    private struct ObservingTimeline<Content: View>: View {
        @ObservedObject var conversation: ConversationModel
        @ObservedObject var messageActions: MessageActionsModel
        @ViewBuilder let content: () -> Content

        var body: some View { content() }
    }

    @MainActor private struct TableHarness {
        let conversation: ConversationModel
        let preferences: ComposerPreferences
        let messageActions: MessageActionsModel
        let ui: MessageUI
        let window: NSWindow
        let host: NSView
        let tableView: TimelineNSTableView
        let scrollView: NSScrollView
        let coordinator: TimelineTableView.Coordinator

        func pump(for interval: TimeInterval, until condition: (() -> Bool)? = nil) {
            let deadline = Date().addingTimeInterval(interval)
            while Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                host.layoutSubtreeIfNeeded()
                if condition?() == true { break }
            }
        }

        func scrollBy(_ deltaY: CGFloat) {
            coordinator.noteUserScrollForTesting()
            let clip = scrollView.contentView
            let minY = tableView.bounds.minY - scrollView.contentInsets.top
            let maxY = max(minY, tableView.bounds.maxY + scrollView.contentInsets.bottom - clip.bounds.height)
            let target = min(maxY, max(minY, clip.bounds.origin.y + deltaY))
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: target))
            scrollView.reflectScrolledClipView(clip)
            RunLoop.main.run(mode: .default, before: Date())
            host.layoutSubtreeIfNeeded()
        }

        func scrollToTop() {
            coordinator.noteUserScrollForTesting()
            let clip = scrollView.contentView
            let topY = tableView.bounds.minY - scrollView.contentInsets.top
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: topY))
            scrollView.reflectScrolledClipView(clip)
            RunLoop.main.run(mode: .default, before: Date())
            host.layoutSubtreeIfNeeded()
        }

        func tearDown() {
            window.orderOut(nil)
            window.contentView = nil
        }
    }

    private func mountTable(
        items: [TimelineItem],
        isDirect: Bool = false,
        hasOlder: Bool = false,
        olderFailed: Bool = false,
        size: NSSize = NSSize(width: 640, height: 320),
        probe: ((String, CGRect) -> Void)? = nil
    ) throws -> TableHarness {
        _ = NSApplication.shared
        let store = makeDefaults()
        let app = offlineApp()
        let preferences = ComposerPreferences(defaults: store)
        preferences.timelineEngine = .table
        let conversation = ConversationModel(appModel: app, preferences: preferences)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: app,
            preferences: preferences,
            pasteboard: NoPasteboard()
        )
        let ui = MessageUI()
        let row = Fixture.row("!table-test", "Table Test", network: "slack", direct: isDirect, ts: 1, preview: "hi")
        conversation.setSnapshotStateForTesting(
            roomID: "!table-test",
            items: items,
            row: row,
            features: Fixture.features,
            hasOlder: hasOlder
        )
        if olderFailed {
            conversation.setOlderFailedForTesting(true)
        }

        // ConversationView observes the model and re-renders the table's representable when it changes; so does this.
        // The closures in `actions` are new on each pass, so SwiftUI always updates the table, as it does in the app.
        let rootView = ObservingTimeline(conversation: conversation, messageActions: messageActions) {
            let actions = MessageRowActions.make(
                conversation: conversation,
                messageActions: messageActions,
                preferences: preferences,
                composer: conversation.composer,
                ui: ui,
                source: .chat,
                deselect: { conversation.deselectMessage() },
                select: { conversation.selectedMessageID = $0 }
            )
            TimelineTableView(
                conversation: conversation,
                messageActions: messageActions,
                preferences: preferences,
                ui: ui,
                appModel: app,
                actions: actions,
                effectiveHeaderInset: 48,
                bottomSafeAreaInset: 0,
                bottomBarSignature: [],
                resolvedAppearance: nil,
                redact: false,
                themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
                drawsLiquidGlass: false,
                timelineCovered: false
            )
        }
        .environment(\.liquidGlass, false)
        .environment(\.conversationLayoutProbe, probe)

        let host = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()

        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded()
            if host.first(TimelineNSTableView.self) != nil { break }
        }

        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let scrollView = try XCTUnwrap(host.first(NSScrollView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        let harness = TableHarness(
            conversation: conversation,
            preferences: preferences,
            messageActions: messageActions,
            ui: ui,
            window: window,
            host: host,
            tableView: tableView,
            scrollView: scrollView,
            coordinator: coordinator
        )
        harness.pump(for: 0.2)
        return harness
    }

    private func writePNG(to url: URL, width: Int, height: Int) throws {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = try XCTUnwrap(ctx.makeImage())
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    // MARK: 1. Height cache & content revision

    func testRowHeightCacheKeyingAndContentRevision() throws {
        let cache = RowHeightCache()
        XCTAssertNil(cache.height(for: "$m1", contentRevision: 10, width: 500.0))
        XCTAssertEqual(cache.misses, 1)

        cache.insert(72.5, for: "$m1", contentRevision: 10, width: 500.2)
        // Quantized to 0.5 pt Retina grid: 500.0 and 500.2 both quantize to 1000.
        XCTAssertEqual(cache.height(for: "$m1", contentRevision: 10, width: 500.0), 72.5)
        XCTAssertEqual(cache.hits, 1)
        XCTAssertNil(cache.height(for: "$m1", contentRevision: 11, width: 500.0))
        XCTAssertNil(cache.height(for: "$m1", contentRevision: 10, width: 600.0))

        cache.insert(60.0, for: "$m2", contentRevision: 5, width: 600.0)
        cache.invalidateWidth(keeping: 600.0)
        XCTAssertNil(cache.height(for: "$m1", contentRevision: 10, width: 500.0))
        XCTAssertEqual(cache.height(for: "$m2", contentRevision: 5, width: 600.0), 60.0)

        cache.invalidateItem(id: "$m2")
        XCTAssertNil(cache.height(for: "$m2", contentRevision: 5, width: 600.0))

        let dir = try makeTempDir()
        let imgURL = dir.appendingPathComponent("late-photo.png")
        let store = makeDefaults()
        let app = offlineApp(dataDir: dir)
        let prefs = ComposerPreferences(defaults: store)
        let conv = ConversationModel(appModel: app, preferences: prefs)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let msgActions = MessageActionsModel(conversation: conv, appModel: app, preferences: prefs, pasteboard: NoPasteboard())
        let ui = MessageUI()
        let actions = MessageRowActions.make(
            conversation: conv,
            messageActions: msgActions,
            preferences: prefs,
            composer: conv.composer,
            ui: ui,
            source: .chat,
            select: { _ in }
        )
        let env = TimelineRowEnvironment(
            appearance: nil,
            themeRoomID: nil,
            themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
            redactNamesAndPictures: false,
            liquidGlass: false,
            timelineCovered: false,
            timelineSelectionMode: false,
            messagePointSize: 13,
            zoomMultiplier: 1.0,
            colorScheme: .light,
            reactionCardOverride: nil,
            clickTargetProbe: nil
        )

        var photoEvent = Fixture.mediaEvent("$img", msgtype: "m.image", body: "late-photo.png", ts: 5)
        photoEvent.mediaPath = imgURL.path
        let baseItems = Fixture.items([
            Fixture.text("$t1", "Original body", mine: true, ts: 10, status: .sent),
            photoEvent,
        ])
        let msgItem = try XCTUnwrap(baseItems.first { $0.id == "$t1" })
        let photoItem = try XCTUnwrap(baseItems.first { $0.id == "$img" })

        let unselectedEntry = TimelineRowEntry.item(
            msgItem, isSelected: false, isHighlighted: false, showsSent: false,
            actions: actions, ui: ui, messageActions: msgActions,
            voiceNoteTranscripts: conv.voiceNoteTranscripts, timerChoicesCount: 0,
            env: env, isPickingReaction: false
        )
        let selectedEntry = TimelineRowEntry.item(
            msgItem, isSelected: true, isHighlighted: true, showsSent: false,
            actions: actions, ui: ui, messageActions: msgActions,
            voiceNoteTranscripts: conv.voiceNoteTranscripts, timerChoicesCount: 0,
            env: env, isPickingReaction: false
        )
        XCTAssertEqual(
            unselectedEntry.contentRevision, selectedEntry.contentRevision,
            "selection and highlight must not alter contentRevision"
        )
        XCTAssertNotEqual(unselectedEntry.visualHash, selectedEntry.visualHash)

        let showsSentEntry = TimelineRowEntry.item(
            msgItem, isSelected: false, isHighlighted: false, showsSent: true,
            actions: actions, ui: ui, messageActions: msgActions,
            voiceNoteTranscripts: conv.voiceNoteTranscripts, timerChoicesCount: 0,
            env: env, isPickingReaction: false
        )
        XCTAssertNotEqual(unselectedEntry.contentRevision, showsSentEntry.contentRevision)

        let editedItems = Fixture.items([
            Fixture.text("$t1", "Edited body that wraps onto more lines", mine: true, ts: 10, status: .sent),
        ])
        let editedEntry = TimelineRowEntry.item(
            try XCTUnwrap(editedItems.first { $0.id == "$t1" }),
            isSelected: false, isHighlighted: false, showsSent: false,
            actions: actions, ui: ui, messageActions: msgActions,
            voiceNoteTranscripts: conv.voiceNoteTranscripts, timerChoicesCount: 0,
            env: env, isPickingReaction: false
        )
        XCTAssertNotEqual(unselectedEntry.contentRevision, editedEntry.contentRevision)

        let reactedItems = Fixture.items([
            Fixture.text("$t1", "Original body", mine: true, ts: 10, status: .sent),
            Fixture.event("$rx", type: "m.reaction", mine: false, ts: 9, content: [
                "m.relates_to": .object([
                    "rel_type": .string("m.annotation"), "event_id": .string("$t1"), "key": .string("👍"),
                ]),
            ]),
        ])
        let reactedEntry = TimelineRowEntry.item(
            try XCTUnwrap(reactedItems.first { $0.id == "$t1" }),
            isSelected: false, isHighlighted: false, showsSent: false,
            actions: actions, ui: ui, messageActions: msgActions,
            voiceNoteTranscripts: conv.voiceNoteTranscripts, timerChoicesCount: 0,
            env: env, isPickingReaction: false
        )
        XCTAssertNotEqual(unselectedEntry.contentRevision, reactedEntry.contentRevision)

        let beforePhotoRev = TimelineContentRevision.compute(
            item: photoItem, showsSent: false, actions: actions, ui: ui,
            messageActions: msgActions, voiceNoteTranscripts: conv.voiceNoteTranscripts,
            timerChoicesCount: 0, envHeightSignature: env.heightSignature
        )
        try writePNG(to: imgURL, width: 1200, height: 600)
        _ = ImagePixelSizeReader.sizeNow(ofFirstReadable: [imgURL.path])
        let afterPhotoRev = TimelineContentRevision.compute(
            item: photoItem, showsSent: false, actions: actions, ui: ui,
            messageActions: msgActions, voiceNoteTranscripts: conv.voiceNoteTranscripts,
            timerChoicesCount: 0, envHeightSignature: env.heightSignature
        )
        XCTAssertNotEqual(beforePhotoRev, afterPhotoRev, "learned image pixel size must invalidate row contentRevision")
    }

    // MARK: 2. Cell & NSHostingView reuse per row kind

    func testCellReuseAndPerKindIdentifiersAcrossScrolling() throws {
        var events: [Event] = []
        for idx in 0 ..< 90 {
            let ts = 200 - idx
            if idx == 15 {
                events.append(Fixture.timerNote("$timer", mine: false, ts: ts, timerMS: 86_400_000))
            } else if idx == 45 {
                events.append(Fixture.callNote("$call", mine: false, ts: ts, body: "Audio call", state: "ended", media: "audio"))
            } else {
                events.append(Fixture.text(
                    "$m\(idx)",
                    "Message #\(idx): scrolling test content for cell reuse verification.",
                    mine: idx % 2 == 0,
                    ts: ts,
                    sender: idx % 2 == 0 ? nil : "@ann:courier.local",
                    name: "Ann Example"
                ))
            }
        }
        var items = Fixture.items(events, isDirect: false)
        items.insert(.newDivider, at: items.count / 2)
        items.insert(.membershipRun(id: "mem-1", events: [], summary: "Ann joined the group"), at: 2)

        XCTAssertEqual(TimelineRowKind(item: .dateSeparator(Fixture.now)).identifier.rawValue, "timeline.divider")
        XCTAssertEqual(TimelineRowKind(item: .newDivider).identifier.rawValue, "timeline.divider")
        XCTAssertEqual(TimelineRowKind(item: .membershipRun(id: "m", events: [], summary: "s")).identifier.rawValue, "timeline.notice")
        let timerItem = try XCTUnwrap(items.first { $0.id == "$timer" })
        XCTAssertEqual(TimelineRowKind(item: timerItem).identifier.rawValue, "timeline.notice")

        let harness = try mountTable(items: items)
        defer { harness.tearDown() }
        harness.pump(for: 0.35)

        var hostingIDs = Set<ObjectIdentifier>()
        func captureHostingIDs() {
            harness.tableView.enumerateAvailableRowViews { rowView, _ in
                for subview in rowView.subviews {
                    if let cell = subview as? TimelineCell {
                        hostingIDs.insert(ObjectIdentifier(cell.hostingView))
                    }
                }
            }
        }
        captureHostingIDs()

        for _ in 0 ..< 25 {
            harness.scrollBy(-140)
            captureHostingIDs()
        }
        for _ in 0 ..< 15 {
            harness.scrollBy(140)
            captureHostingIDs()
        }

        XCTAssertGreaterThan(harness.coordinator.reusedCellCount, 0, "scrolling must reuse existing TimelineCell instances")
        XCTAssertLessThan(harness.coordinator.createdCellCount, 45, "created cells must remain bounded to the viewport pool")
        XCTAssertLessThanOrEqual(
            hostingIDs.count,
            harness.coordinator.createdCellCount,
            "reused cells must keep their existing NSHostingView without allocating new ones"
        )
    }

    // MARK: 3. Diffed updates & debounced width resize

    func testAppendPinnedAndAwayEditDeleteAndDebouncedWidthResize() throws {
        var frames: [String: CGRect] = [:]
        let initialEvents = (1 ... 30).map { idx in
            Fixture.text("$m\(idx)", "Message #\(idx)", mine: idx % 2 == 0, ts: 60 - idx)
        }
        let harness = try mountTable(items: Fixture.items(initialEvents, isDirect: false)) { name, rect in
            frames[name] = rect
        }
        defer { harness.tearDown() }
        harness.pump(for: 0.4)
        XCTAssertTrue(harness.conversation.isAtBottom)

        // Append while at bottom -> scrolls to the new message and stays at bottom.
        let appendedEvent = Fixture.text("$m31", "Newest appended message", mine: false, ts: 5)
        harness.conversation.setSnapshotItemsForTesting(Fixture.items(initialEvents + [appendedEvent], isDirect: false))
        harness.pump(for: 0.2)
        XCTAssertTrue(harness.conversation.isAtBottom, "appending while at bottom keeps timeline pinned to bottom")
        XCTAssertNotNil(frames["item/$m31"], "appended message must be visible at bottom")

        // Scroll away from bottom (toward middle/top) and verify append does not jump back to bottom.
        for _ in 0 ..< 8 {
            harness.scrollBy(-120)
        }
        harness.pump(for: 0.25) // > 150ms leavingBottom confirm delay
        XCTAssertFalse(harness.conversation.isAtBottom)
        // A message in the middle of what is on screen now (the probe's `frames` also hold rows scrolled away since).
        let visible = harness.tableView.rows(in: harness.tableView.visibleRect)
        let watchedRow = visible.location + visible.length / 2
        let watchedID = harness.coordinator.entries[watchedRow].id
        func watchedRect() throws -> CGRect {
            let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == watchedID })
            return harness.host.convert(harness.tableView.rect(ofRow: row), from: harness.tableView)
        }
        let rectBeforeAppend = try watchedRect()
        let secondAppend = Fixture.text("$m32", "Second appended while away", mine: false, ts: 1)
        harness.conversation.setSnapshotItemsForTesting(
            Fixture.items(initialEvents + [appendedEvent, secondAppend], isDirect: false)
        )
        harness.pump(for: 0.15)
        XCTAssertFalse(harness.conversation.isAtBottom, "appending while scrolled up must not yank user to bottom")
        XCTAssertEqual(try watchedRect().minY, rectBeforeAppend.minY, accuracy: 1.0, "the rows on screen did not move")

        // Edit the visible message in-place (changes height) and delete an offscreen message.
        let editedID = watchedID
        var modifiedEvents = initialEvents + [appendedEvent, secondAppend]
        if let idx = modifiedEvents.firstIndex(where: { $0.eventID == editedID }) {
            modifiedEvents[idx] = Fixture.text(
                editedID,
                "Edited longer text that wraps across several lines so the row height updates cleanly in place.",
                mine: modifiedEvents[idx].mine,
                ts: 60 - (Int(editedID.dropFirst(2)) ?? 0) // the same place in the timeline: only its height changes
            )
        }
        modifiedEvents.removeAll { $0.eventID == "$m32" }
        harness.conversation.setSnapshotItemsForTesting(Fixture.items(modifiedEvents, isDirect: false))
        harness.pump(for: 0.15)
        XCTAssertGreaterThan(try watchedRect().height, rectBeforeAppend.height, "the edit made the row taller")

        // Debounced width resize (~100ms) invalidates old width and re-measures rows.
        harness.coordinator.heightCache.resetCounters()
        let resized = NSSize(width: 420, height: 320)
        harness.window.setContentSize(resized)
        harness.host.frame = NSRect(origin: .zero, size: resized)
        harness.host.layoutSubtreeIfNeeded()
        harness.pump(for: 0.28)
        XCTAssertGreaterThan(harness.coordinator.heightCache.misses, 0, "width resize must invalidate cached heights and re-measure")
    }

    // MARK: 4. Raised row layering

    func testSelectedRowIsRaisedAboveNeighbors() throws {
        let events = [
            Fixture.text("$r1", "First message", mine: false, ts: 10),
            Fixture.text("$r2", "Second message", mine: true, ts: 5),
        ]
        let harness = try mountTable(items: Fixture.items(events, isDirect: false))
        defer { harness.tearDown() }

        harness.conversation.selectedMessageID = "$r1"
        harness.pump(for: 0.15)

        let row1 = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == "$r1" })
        let row2 = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == "$r2" })
        let rowView1 = try XCTUnwrap(harness.tableView.rowView(atRow: row1, makeIfNecessary: false) as? TimelineTableRowView)
        let rowView2 = try XCTUnwrap(harness.tableView.rowView(atRow: row2, makeIfNecessary: false) as? TimelineTableRowView)

        XCTAssertTrue(rowView1.isRaisedRow)
        XCTAssertFalse(rowView2.isRaisedRow)
        XCTAssertEqual(rowView1.layer?.zPosition, 10)
        XCTAssertEqual(rowView2.layer?.zPosition, 0)
    }

    // MARK: 5. Sender card popover

    func testSenderCardPopoverOpensAndDismissesOnDismissAndLock() throws {
        let events = [
            Fixture.text("$s1", "Hover card target", mine: false, ts: 10, sender: "@ann:courier.local", name: "Ann Example"),
        ]
        let harness = try mountTable(items: Fixture.items(events, isDirect: false))
        defer { harness.tearDown() }

        harness.conversation.activeSenderCard = SenderHoverCardState(
            messageID: "$s1",
            userID: "@ann:courier.local",
            member: Member(userID: "@ann:courier.local", name: "Ann Example"),
            network: "slack"
        )
        harness.pump(for: 0.15)
        XCTAssertTrue(harness.coordinator.isSenderPopoverShownForTesting)

        harness.conversation.dismissSenderCard()
        harness.pump(for: 0.1)
        XCTAssertFalse(harness.coordinator.isSenderPopoverShownForTesting)

        harness.conversation.activeSenderCard = SenderHoverCardState(
            messageID: "$s1",
            userID: "@ann:courier.local",
            member: Member(userID: "@ann:courier.local", name: "Ann Example"),
            network: "slack"
        )
        harness.pump(for: 0.15)
        XCTAssertTrue(harness.coordinator.isSenderPopoverShownForTesting)

        NotificationCenter.default.post(name: SystemLifecycleModel.didLockNotification, object: nil)
        harness.pump(for: 0.1)
        XCTAssertFalse(harness.coordinator.isSenderPopoverShownForTesting)
    }

    // MARK: 6. Top pagination rules

    func testTopPaginationRetryRowAndNoUnpromptedLoadEarlier() throws {
        let events = [
            Fixture.text("$p1", "First message", mine: false, ts: 10),
            Fixture.text("$p2", "Second message", mine: true, ts: 5),
        ]
        let failedHarness = try mountTable(
            items: Fixture.items(events, isDirect: false),
            hasOlder: true,
            olderFailed: true
        )
        defer { failedHarness.tearDown() }
        XCTAssertEqual(failedHarness.coordinator.entries.first?.kind, .topControl)
        XCTAssertEqual(failedHarness.coordinator.entries.first?.topControl, .olderRetry)

        let shortHarness = try mountTable(
            items: Fixture.items(events, isDirect: false),
            hasOlder: false,
            olderFailed: false
        )
        defer { shortHarness.tearDown() }
        shortHarness.scrollToTop()
        shortHarness.pump(for: 0.1)
        XCTAssertFalse(
            shortHarness.conversation.isLoadingEarlier,
            "opening a short chat at top without user scroll must not call loadEarlier"
        )
        XCTAssertEqual(shortHarness.coordinator.entries.first?.topControl, .earlierSentinel)
    }

    // MARK: 7. Accessibility ordering

    func testAccessibilityExposesSwiftUIContentInTopToBottomOrder() throws {
        let events = (1 ... 5).map { idx in
            Fixture.text("$a\(idx)", "Accessible line \(idx)", mine: idx % 2 == 0, ts: 20 - idx)
        }
        let harness = try mountTable(items: Fixture.items(events, isDirect: false))
        defer { harness.tearDown() }

        let dummyCell = TimelineCell(
            identifier: TimelineRowKind.message.identifier,
            rootView: TimelineHostedRow(
                item: .newDivider,
                isSelected: false,
                isHighlighted: false,
                showsSent: false,
                actions: MessageActions(),
                ui: harness.ui,
                env: TimelineRowEnvironment(
                    appearance: nil,
                    themeRoomID: nil,
                    themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
                    redactNamesAndPictures: false,
                    liquidGlass: false,
                    timelineCovered: false,
                    timelineSelectionMode: false,
                    messagePointSize: 13,
                    zoomMultiplier: 1,
                    colorScheme: .light,
                    reactionCardOverride: nil,
                    clickTargetProbe: nil
                ),
                onEmptyClick: {}
            )
        )
        XCTAssertFalse(dummyCell.isAccessibilityElement())

        var previousMinY = -CGFloat.greatestFiniteMagnitude
        for row in 0 ..< harness.coordinator.entries.count {
            let rect = harness.tableView.rect(ofRow: row)
            XCTAssertGreaterThan(rect.minY, previousMinY, "row \(row) must lie below row \(row - 1) top-to-bottom")
            previousMinY = rect.minY
        }
    }

    // MARK: 8. Header inset, scroll-to-message, prepending older messages

    func testHeaderInsetIsTheScrollViewsTopInset() throws {
        let events = (1 ... 5).map { Fixture.text("$h\($0)", "Line \($0)", mine: false, ts: 20 - $0) }
        let harness = try mountTable(items: Fixture.items(events, isDirect: false))
        defer { harness.tearDown() }
        let inset = 48 + ConversationView.timelineVerticalPadding
        XCTAssertEqual(harness.scrollView.contentInsets.top, inset, "the chat header's height plus the timeline's padding is the top inset")
        XCTAssertFalse(harness.scrollView.automaticallyAdjustsContentInsets)
        harness.scrollToTop()
        harness.pump(for: 0.1)
        let firstRowTop = harness.host.convert(harness.tableView.rect(ofRow: 0), from: harness.tableView).minY
        XCTAssertGreaterThanOrEqual(firstRowTop, inset - 0.5, "at the top the first row starts below the header")
    }

    func testScrollToMessageShowsItBelowTheHeader() throws {
        let events = (1 ... 40).map { Fixture.text("$j\($0)", "Message \($0)", mine: $0 % 2 == 0, ts: 80 - $0) }
        let harness = try mountTable(items: Fixture.items(events, isDirect: false))
        defer { harness.tearDown() }
        harness.pump(for: 0.3)
        harness.conversation.scrollToMessageForTesting("$j5")
        harness.pump(for: 0.9, until: nil)
        let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == "$j5" })
        let rect = harness.tableView.rect(ofRow: row)
        let clip = harness.scrollView.contentView.bounds
        XCTAssertGreaterThanOrEqual(rect.minY - clip.minY, 48 - 1, "the message is not under the header")
        XCTAssertLessThanOrEqual(rect.maxY, clip.maxY + 1, "the message is on screen")
    }

    func testPrependingOlderMessagesKeepsTheRowsOnScreenInPlace() throws {
        let newer = (1 ... 30).map { Fixture.text("$n\($0)", "Newer \($0)", mine: $0 % 2 == 0, ts: 60 - $0) }
        let harness = try mountTable(items: Fixture.items(newer, isDirect: false), hasOlder: true)
        defer { harness.tearDown() }
        harness.pump(for: 0.4)
        for _ in 0 ..< 5 { harness.scrollBy(-120) }
        harness.pump(for: 0.2)
        let visible = harness.tableView.rows(in: harness.tableView.visibleRect)
        let watchedID = harness.coordinator.entries[visible.location + visible.length / 2].id
        func watchedMinY() throws -> CGFloat {
            let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == watchedID })
            return harness.host.convert(harness.tableView.rect(ofRow: row), from: harness.tableView).minY
        }
        let before = try watchedMinY()
        let older = (1 ... 12).map { Fixture.text("$o\($0)", "Older \($0)", mine: false, ts: 200 - $0) }
        harness.conversation.setSnapshotItemsForTesting(Fixture.items(older + newer, isDirect: false), hasOlder: true)
        harness.pump(for: 0.3)
        XCTAssertEqual(try watchedMinY(), before, accuracy: 1.0, "an older page joining the top does not move what is on screen")
    }

    // MARK: 9. Sizing rows never waits on the disk

    private func writePDF(to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 360, height: 240)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.9, green: 0.95, blue: 1, alpha: 1))
        context.fill(mediaBox)
        context.endPDFPage()
        context.closePDF()
    }

    private func fileRows(dir: URL, tag: String) throws -> (items: [TimelineItem], paths: [String]) {
        let pdfURL = dir.appendingPathComponent("\(tag).pdf")
        try writePDF(to: pdfURL)
        let imageURL = dir.appendingPathComponent("\(tag).png")
        try writePNG(to: imageURL, width: 640, height: 360)
        var pdf = Fixture.event("$pdf-\(tag)", mine: false, ts: 10, content: [
            "msgtype": .string("m.file"), "body": .string("\(tag).pdf"), "filename": .string("\(tag).pdf"),
            "info": .object(["mimetype": .string("application/pdf"), "size": .int(1000)]),
        ])
        pdf.mediaPath = pdfURL.path
        var link = Fixture.text("$link-\(tag)", "See https://example.com/\(tag)", mine: false, ts: 8)
        link.linkPreviews = [LinkPreviewItem(matchedURL: "https://example.com/\(tag)", url: "https://example.com/\(tag)",
                                             title: "A page", imagePath: imageURL.path)]
        return (Fixture.items([pdf, link], isDirect: false), [pdfURL.path, imageURL.path])
    }

    func testLookupsNeverReadTheDiskOnTheCallingThread() throws {
        let dir = try makeTempDir()
        let rows = try fileRows(dir: dir, tag: "cold")
        InlinePDFDocumentCache.shared.resetForTests()
        let pdfPath = rows.paths[0]
        XCTAssertNil(LocalFileFacts.exists(pdfPath), "an unknown file is answered from memory: not known yet")
        XCTAssertNil(InlinePDFDocumentCache.shared.document(atPath: pdfPath), "a PDF not read yet is not parsed on the caller")
        XCTAssertEqual(InlinePDFDocumentCache.shared.parseCount, 0)
        let deadline = Date().addingTimeInterval(3)
        while LocalFileFacts.exists(pdfPath) == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(LocalFileFacts.exists(pdfPath), true, "the background lookup found it")
    }

    func testWarmedFilesKeepRowHeightsFromTheFirstFrame() throws {
        let dir = try makeTempDir()
        let rows = try fileRows(dir: dir, tag: "warm")
        InlinePDFDocumentCache.shared.resetForTests()
        InlinePDFDocumentCache.installWarmer()
        // What the model does as a page arrives (`ImagePixelSizeReader.warm`), here by hand.
        LocalFileFacts.warm(paths: rows.paths)
        let harness = try mountTable(items: rows.items)
        defer { harness.tearDown() }
        func heights() -> [CGFloat] {
            ["$pdf-warm", "$link-warm"].map { id in
                harness.tableView.rect(ofRow: harness.coordinator.entries.firstIndex { $0.id == id } ?? 0).height
            }
        }
        let first = heights()
        XCTAssertGreaterThan(first[0], 200, "the PDF card, not its file chip, from the first frame")
        harness.pump(for: 0.8)
        XCTAssertEqual(heights(), first, "nothing was learned late, so no row changed height")
    }

    func testRowsRemeasureWhenAFileIsLearnedLate() throws {
        let dir = try makeTempDir()
        let rows = try fileRows(dir: dir, tag: "late")
        InlinePDFDocumentCache.shared.resetForTests()
        InlinePDFDocumentCache.installWarmer()
        let harness = try mountTable(items: rows.items)
        defer { harness.tearDown() }
        func pdfHeight() -> CGFloat {
            harness.tableView.rect(ofRow: harness.coordinator.entries.firstIndex { $0.id == "$pdf-late" } ?? 0).height
        }
        harness.pump(for: 1.5, until: { pdfHeight() > 200 })
        XCTAssertGreaterThan(pdfHeight(), 200, "once the lookup and the read finished off the main thread, the row grew to the card")
    }

    // MARK: 10. Bounded caches and cancelled decodes

    func testFileFactsAreBounded() {
        LocalFileFacts.resetForTesting()
        LocalFileFacts.warm(paths: (0 ..< LocalFileFacts.maxFacts + 600).map { "/nonexistent-courier-facts/\($0)" })
        XCTAssertLessThanOrEqual(LocalFileFacts.countForTesting, LocalFileFacts.maxFacts)
        XCTAssertGreaterThan(LocalFileFacts.countForTesting, LocalFileFacts.maxFacts / 2, "it trims the oldest, not everything")
    }

    func testParsedPDFsAreBoundedAndTheMostRecentStay() throws {
        let dir = try makeTempDir()
        InlinePDFDocumentCache.shared.resetForTests()
        var paths: [String] = []
        for index in 0 ..< InlinePDFDocumentCache.maxDocuments + 4 {
            let url = dir.appendingPathComponent("d\(index).pdf")
            try writePDF(to: url)
            InlinePDFDocumentCache.shared.parse(path: url.path)
            paths.append(url.path)
        }
        XCTAssertLessThanOrEqual(InlinePDFDocumentCache.shared.cachedCountForTesting, InlinePDFDocumentCache.maxDocuments)
        XCTAssertTrue(InlinePDFDocumentCache.shared.hasDocument(atPath: paths.last!), "the newest is kept")
        XCTAssertFalse(InlinePDFDocumentCache.shared.hasDocument(atPath: paths.first!), "the oldest was let go")
    }

    func testAColdLookupAndAnExplicitParseReadAPDFOnce() throws {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("once.pdf")
        try writePDF(to: url)
        InlinePDFDocumentCache.shared.resetForTests()
        InlinePDFDocumentCache.installWarmer()
        _ = InlinePDFDocumentCache.shared.document(atPath: url.path) // starts the background lookup and read
        InlinePDFDocumentCache.shared.parse(path: url.path) // waits for it if it is under way
        let deadline = Date().addingTimeInterval(3)
        while !InlinePDFDocumentCache.shared.hasDocument(atPath: url.path), Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(InlinePDFDocumentCache.shared.parseCount, 1)
    }

    func testCancellingTheCallerCancelsADetachedDecode() async {
        let task = Task { () -> Bool? in
            await runDetachedCancellable { () -> Bool? in
                Thread.sleep(forTimeInterval: 0.3)
                return Task.isCancelled
            }
        }
        try? await Task.sleep(nanoseconds: 60_000_000)
        task.cancel()
        let sawCancellation = await task.value
        XCTAssertEqual(sawCancellation, true, "the work saw the cancellation, so it can stop early")

        let cancelledFirst = Task { () -> Bool? in
            await runDetachedCancellable { () -> Bool? in true }
        }
        cancelledFirst.cancel()
        let value = await cancelledFirst.value
        XCTAssertTrue(value == nil || value == true, "a task cancelled before it starts may skip the work")
    }

    // MARK: 11. A removed table stops its work

    /// A table timeline taken out of its window must not go on measuring rows (evaluating their bodies) on the main
    /// run loop afterwards: another timeline's counters, and its frames, would pay for it (CI saw a swiftui timeline's
    /// "no rows re-evaluated" check fail after a table one had been torn down).
    func testRemovedTableStopsEvaluatingRows() throws {
        let events = (0 ..< 400).map { Fixture.text("$z\($0)", "Message row \($0) with some more words in it", mine: $0 % 2 == 0, ts: $0 + 1) }
        var harness: TableHarness? = try mountTable(items: Fixture.items(events, isDirect: false))
        harness?.pump(for: 0.05)
        // Stop in the middle of its height pre-warm / resize work.
        harness?.window.setContentSize(NSSize(width: 420, height: 320))
        harness?.host.frame = NSRect(x: 0, y: 0, width: 420, height: 320)
        harness?.host.layoutSubtreeIfNeeded()
        harness?.tearDown()
        harness = nil
        ScrollPerfCounters.enabled = true
        ScrollPerfCounters.reset()
        defer { ScrollPerfCounters.enabled = false }
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(ScrollPerfCounters.rowBodies, 0, "a removed table timeline evaluated rows afterwards")
    }

    func testTableMovedBackIntoAWindowMeasuresAgain() throws {
        let events = (0 ..< 40).map { Fixture.text("$y\($0)", "Message row \($0) with a few more words to make it wrap onto a second line in a narrow chat", mine: $0 % 2 == 0, ts: $0 + 1) }
        let harness = try mountTable(items: Fixture.items(events, isDirect: false), size: NSSize(width: 300, height: 320))
        defer { harness.tearDown() }
        harness.pump(for: 0.3)
        let row = try XCTUnwrap(harness.coordinator.entries.firstIndex { $0.id == "$y3" })
        let before = harness.tableView.rect(ofRow: row).height
        XCTAssertGreaterThan(before, 44)
        harness.window.contentView = nil
        harness.pump(for: 0.1)
        XCTAssertTrue(harness.coordinator.isShutDown)
        harness.window.contentView = harness.host
        harness.host.frame = NSRect(x: 0, y: 0, width: 300, height: 320)
        harness.pump(for: 0.4)
        XCTAssertFalse(harness.coordinator.isShutDown)
        XCTAssertEqual(harness.tableView.rect(ofRow: row).height, before, "measured again, not left at the placeholder")
    }
}
