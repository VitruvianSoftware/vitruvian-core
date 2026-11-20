// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

@MainActor
final class Batch6PolishViewTests: XCTestCase {
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

    private func makeDefaults(_ suffix: String = UUID().uuidString) -> UserDefaults {
        let name = "courier.batch6polish.\(suffix)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-batch6-\(UUID().uuidString)", isDirectory: true)
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

    func testD1DateDividerAppearsAboveFirstMessageInTimelineTable() throws {
        _ = NSApplication.shared
        let store = makeDefaults()
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: try makeTempDir(),
            environment: [:],
            launcher: FoundationProcessLauncher()
        ))
        let prefs = ComposerPreferences(defaults: store)
        prefs.timelineEngine = .table
        let conversation = ConversationModel(appModel: app, preferences: prefs)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: app,
            preferences: prefs,
            pasteboard: NoPasteboard()
        )
        let ui = MessageUI()

        let items = Fixture.items([
            Fixture.text("$m1", "First message of a loaded history", mine: false, ts: 10),
        ], isDirect: false)
        conversation.setSnapshotStateForTesting(
            roomID: "!d1-room",
            items: items,
            row: Fixture.row("!d1-room", "D1 Room", network: "signal", direct: false, ts: 10, preview: "hi"),
            features: Fixture.features,
            hasOlder: false
        )

        struct Root: View {
            @ObservedObject var conversation: ConversationModel
            @ObservedObject var messageActions: MessageActionsModel
            let prefs: ComposerPreferences
            let ui: MessageUI
            let app: AppModel

            var body: some View {
                let actions = VitruvianCourier.MessageActions(
                    select: { conversation.selectedMessageID = $0 },
                    deselect: { conversation.deselectMessage() },
                    reply: { _ in },
                    now: { Fixture.now }
                )
                TimelineTableView(
                    conversation: conversation,
                    messageActions: messageActions,
                    preferences: prefs,
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
        }

        let size = NSSize(width: 640, height: 320)
        let host = NSHostingView(rootView: Root(
            conversation: conversation,
            messageActions: messageActions,
            prefs: prefs,
            ui: ui,
            app: app
        ))
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
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        pump(host, for: 0.4) { host.first(TimelineNSTableView.self) != nil }
        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        pump(host, for: 0.25) { coordinator.entries.count == 3 && tableView.numberOfRows == 3 }

        XCTAssertEqual(coordinator.entries.count, 3)
        XCTAssertEqual(coordinator.entries[0].kind, .topControl)
        XCTAssertTrue(coordinator.entries[1].id.hasPrefix("day-"))
        XCTAssertEqual(coordinator.entries[2].id, "$m1")
        XCTAssertEqual(tableView.numberOfRows, 3)

        let dayRect = tableView.rect(ofRow: 1)
        let msgRect = tableView.rect(ofRow: 2)
        XCTAssertGreaterThan(dayRect.height, 10)
        XCTAssertLessThanOrEqual(dayRect.maxY, msgRect.minY + 1)
    }

    func testD2PhotoViewerOverlayAndMediaViewerShowReactionsAndSenderDateHeader() throws {
        let item = CarouselItem(
            eventID: "$photo-1",
            roomID: Fixture.room,
            kind: .image,
            mediaPath: "",
            fileName: "1000068615.jpeg",
            sender: "@ann:courier.local",
            senderName: "Ann Example (Signal)",
            mine: false,
            ts: Fixture.millis(30),
            caption: "Sunset over the ridge",
            reactions: [
                ReactionChip(
                    key: "❤️",
                    count: 2,
                    mine: true,
                    reactors: [
                        Reactor(userID: Timeline.meUserID, name: "You", isMe: true),
                        Reactor(userID: "@ann:courier.local", name: "Ann Example", isMe: false),
                    ],
                    myEventID: "$myHeart"
                ),
                ReactionChip(key: "🔥", count: 1, mine: false),
            ]
        )

        let header = PhotoViewerPresentation.headerText(for: item, redacted: false)
        XCTAssertTrue(header.hasPrefix("Ann Example · "))
        XCTAssertFalse(header.contains("1000068615.jpeg"))
        XCTAssertEqual(PhotoViewerPresentation.displayCaption(caption: item.caption, fileName: item.fileName), "Sunset over the ridge")

        let carouselModel = AttachmentCarouselModel()
        carouselModel.open(items: [item], selectedEventID: "$photo-1")
        XCTAssertEqual(carouselModel.currentItem?.fileName, "1000068615.jpeg")

        let overlaySizes = try Snapshot.render("photo-viewer-polish", width: 820, height: 560) {
            AttachmentCarouselOverlay(
                model: carouselModel,
                now: { Fixture.now },
                onGoToMessage: { _ in },
                onReact: { _, _ in },
                onReply: { _ in },
                onCopyImage: { _ in },
                onQuickLook: { _ in },
                onDownload: { _ in },
                onClose: {}
            )
        }
        XCTAssertEqual(overlaySizes.count, 2)

        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: try makeTempDir(),
            environment: [:],
            launcher: FoundationProcessLauncher()
        ))
        let hit = MediaHit(
            eventID: "$mv-p1",
            roomID: Fixture.room,
            roomName: "Weekend Trail Crew",
            network: "signal",
            isDirect: false,
            place: .inbox,
            sender: "@ann:courier.local",
            senderName: "Ann Example",
            mine: false,
            ts: Fixture.millis(25),
            seq: 1,
            kind: .image,
            snippet: "1000068615.jpeg",
            mediaPath: ""
        )
        let viewerModel = MediaViewerModel(appModel: app, roomID: Fixture.room, initialItems: [hit])
        let gridSizes = try Snapshot.render("media-viewer-polish", width: 760, height: 520) {
            MediaViewerView(
                model: viewerModel,
                chatTitle: "Weekend Trail Crew",
                now: { Fixture.now },
                reactionsForEvent: { id in
                    id == "$mv-p1" ? [ReactionChip(key: "❤️", count: 2, mine: true, myEventID: "$myHeart")] : []
                },
                onOpenLightbox: { _ in },
                onGoToMessage: { _ in },
                onDownloadSelected: {},
                onDeleteSelected: { _ in }
            )
        }
        XCTAssertEqual(gridSizes.count, 2)
    }

    func testD3AboutSettingsPaneCopyVersionNoteActionsAndHotkeys() throws {
        XCTAssertEqual(AboutSettingsPane.versionLine(appVersion: "0.3.31"), "Version 0.3.31")
        XCTAssertFalse(AboutSettingsPane.versionLine(appVersion: "0.3.31").contains("Protocol"))
        XCTAssertFalse(AboutSettingsPane.versionLine(appVersion: "0.3.31").contains("Build"))

        XCTAssertEqual(AboutSettingsPane.reportProblemRowTitle, "Report a Problem")
        XCTAssertEqual(AboutSettingsPane.reportProblemButtonTitle, "Send Report…")
        XCTAssertEqual(AboutSettingsPane.keyboardShortcutsButtonTitle, "Show")
        XCTAssertEqual(
            UpdatesSection.updatePolicyNote,
            "Courier checks for updates when it opens and once a day, and only installs updates signed by Vitruvian Software."
        )

        let hotkeys = HotkeyRegistry(defaults: makeDefaults())
        let reportChord = try XCTUnwrap(hotkeys.primaryChord(for: "Report a Problem"))
        XCTAssertEqual(reportChord.key, "p")
        XCTAssertTrue(reportChord.command)
        XCTAssertTrue(reportChord.shift)

        let shortcutsChord = try XCTUnwrap(hotkeys.primaryChord(for: "Keyboard Shortcuts"))
        XCTAssertEqual(shortcutsChord.key, "/")
        XCTAssertTrue(shortcutsChord.command)
        XCTAssertFalse(shortcutsChord.shift)

        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: makeDefaults()
        )
        struct NoopUpdateEnv: UpdateEnvironment {
            func send(_: URLRequest) async throws -> UpdateReply { UpdateReply(status: 200, body: Data()) }
            func download(_: URL, to _: URL, progress _: @escaping @Sendable (Double) -> Void) async throws {}
            func sha256(of _: URL) throws -> String { "" }
            func satisfies(_: URL, requirement _: String) -> Bool { false }
            func passesGatekeeper(_: URL) -> Bool { false }
            func mount(_: URL) throws -> URL { URL(fileURLWithPath: "/nonexistent") }
            func unmount(_: URL) {}
            func bundleVersion(of _: URL) -> String? { nil }
            func copy(_: URL, to _: URL) throws {}
            func isWritableDirectory(_: URL) -> Bool { false }
            func remove(_: URL) {}
            func launchInstaller(script _: String, arguments _: [String]) throws {}
        }
        let updateModel = UpdateModel(
            currentVersion: "0.3.31",
            appURL: URL(fileURLWithPath: "/Applications/Vitruvian Courier.app"),
            environment: NoopUpdateEnv(),
            defaults: makeDefaults(),
            now: { Fixture.now },
            quit: {}
        )
        let sizes = try Snapshot.render("settings-about-polish", width: 640, height: 640) {
            AboutSettingsPane(lifecycle: lifecycle, appVersion: "0.3.31", buildNumber: "123", updates: updateModel)
        }
        XCTAssertEqual(sizes.count, 2)
    }
}
