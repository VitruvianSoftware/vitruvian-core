// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Darwin
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

// MARK: - Lightweight Unix-socket JSON-RPC engine stand-in for table view integration tests

private final class QAMockEngineServer: @unchecked Sendable {
    typealias Handler = @Sendable (_ method: String, _ params: [String: Any]?) -> Any

    let socketPath = "/tmp/courier-qa-\(UUID().uuidString.prefix(8)).sock"
    private let listener: Int32
    private let lock = NSLock()
    private let handler: Handler
    private var connections: [Int32] = []
    private var requests: [(method: String, params: [String: Any]?)] = []
    private var stopped = false

    init(handler: @escaping Handler) throws {
        self.handler = handler
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.init(rawValue: errno)!) }
        unlink(socketPath)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let utf8 = Array(socketPath.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (idx, byte) in utf8.enumerated() {
                raw[idx] = UInt8(bitPattern: byte)
            }
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listener, 8) == 0 else {
            let err = errno
            close(listener)
            throw POSIXError(.init(rawValue: err)!)
        }
        Thread { [weak self] in self?.acceptLoop() }.start()
    }

    deinit { stop() }

    func recordedParams(for method: String) -> [[String: Any]] {
        lock.withLock {
            requests.filter { $0.method == method }.compactMap(\.params)
        }
    }

    func stop() {
        let wasStopped = lock.withLock { () -> Bool in
            defer { stopped = true }
            return stopped
        }
        guard !wasStopped else { return }
        let conns = lock.withLock { () -> [Int32] in
            defer { connections = [] }
            return connections
        }
        for fd in conns { shutdown(fd, SHUT_RDWR) }
        close(listener)
        unlink(socketPath)
    }

    private func acceptLoop() {
        while true {
            var pfd = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, 50)
            if lock.withLock({ stopped }) { return }
            guard ready > 0 else { continue }
            let conn = accept(listener, nil, nil)
            guard conn >= 0 else { continue }
            var one: Int32 = 1
            setsockopt(conn, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            lock.withLock { connections.append(conn) }
            Thread { [weak self] in self?.serve(conn) }.start()
        }
    }

    private func serve(_ conn: Int32) {
        defer { close(conn) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(conn, &chunk, chunk.count)
            guard n > 0 else { return }
            buffer.append(contentsOf: chunk[0 ..< n])
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex ..< nl])
                buffer = Data(buffer[buffer.index(after: nl)...])
                guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let method = obj["method"] as? String,
                      let id = obj["id"]
                else { continue }
                let params = obj["params"] as? [String: Any]
                lock.withLock { requests.append((method, params)) }
                let result = handler(method, params)
                guard var out = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result]) else { continue }
                out.append(0x0A)
                out.withUnsafeBytes { raw in
                    var off = 0
                    while off < raw.count {
                        let w = Darwin.write(conn, raw.baseAddress! + off, raw.count - off)
                        if w <= 0 { break }
                        off += w
                    }
                }
            }
        }
    }
}

private final class QAMockLaunchedProcess: LaunchedProcess, @unchecked Sendable {
    let standardOutputLines: AsyncStream<String>
    let standardErrorLines: AsyncStream<String>
    private let outCont: AsyncStream<String>.Continuation
    private let errCont: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var exitCode: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []

    init(socketPath: String) {
        let (outStream, outContinuation) = AsyncStream.makeStream(of: String.self)
        let (errStream, errContinuation) = AsyncStream.makeStream(of: String.self)
        standardOutputLines = outStream
        standardErrorLines = errStream
        outCont = outContinuation
        errCont = errContinuation
        outCont.yield("{\"ready\":true,\"socket\":\"\(socketPath)\"}")
    }

    func waitForExit() async -> Int32 {
        await withCheckedContinuation { cont in
            let existing = lock.withLock { () -> Int32? in
                if let exitCode { return exitCode }
                waiters.append(cont)
                return nil
            }
            if let existing { cont.resume(returning: existing) }
        }
    }

    func terminate() { finish(0) }
    func kill() { finish(137) }
    func closeParentPipe() { finish(0) }

    private func finish(_ code: Int32) {
        let pending = lock.withLock { () -> [CheckedContinuation<Int32, Never>] in
            guard exitCode == nil else { return [] }
            exitCode = code
            defer { waiters = [] }
            return waiters
        }
        outCont.finish()
        errCont.finish()
        for waiter in pending { waiter.resume(returning: code) }
    }
}

private struct QAMockLauncher: ProcessLaunching {
    let socketPath: String
    func launch(_: LaunchSpec) throws -> any LaunchedProcess {
        QAMockLaunchedProcess(socketPath: socketPath)
    }
}

private final class QASleepGate: @unchecked Sendable {
    private let targetDuration: Duration
    private let lock = NSLock()
    private var highlightContinuations: [CheckedContinuation<Void, Error>] = []

    init(targetDuration: Duration) {
        self.targetDuration = targetDuration
    }

    var pendingCount: Int {
        lock.withLock { highlightContinuations.count }
    }

    func sleep(for duration: Duration) async throws {
        if duration == targetDuration {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    lock.withLock { highlightContinuations.append(cont) }
                }
            } onCancel: {
                let cancelled = self.lock.withLock { () -> [CheckedContinuation<Void, Error>] in
                    defer { self.highlightContinuations = [] }
                    return self.highlightContinuations
                }
                for cont in cancelled { cont.resume(throwing: CancellationError()) }
            }
        } else {
            try await Task.sleep(for: duration)
        }
    }

    func releaseHighlights() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            defer { highlightContinuations = [] }
            return highlightContinuations
        }
        for cont in pending { cont.resume() }
    }
}

// MARK: - QA Behavior Coverage Tests

@MainActor
final class TimelineTableBehaviorQATests: XCTestCase {
    private var suites: [String] = []
    private var tempDirs: [URL] = []
    private var servers: [QAMockEngineServer] = []
    private var apps: [AppModel] = []

    override func tearDown() async throws {
        for app in apps { await app.stop() }
        apps = []
        for server in servers { server.stop() }
        servers = []
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
        let name = "courier.tableqa.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-table-qa-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirs.append(url)
        return url
    }

    private func writePNG(to url: URL, width: Int, height: Int) throws {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = try XCTUnwrap(ctx.makeImage())
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    private static func makeWireEvent(index: Int, roomID: String) -> [String: Any] {
        let baseTS: Int64 = 1_792_500_000_000 + Int64(index) * 60_000
        let mine = index % 2 == 0
        return [
            "event_id": "$\(index)",
            "room_id": roomID,
            "sender": mine ? Timeline.meUserID : "@ann:courier.local",
            "sender_name": mine ? "me" : "Ann Example",
            "sender_avatar_path": "",
            "mine": mine,
            "type": "m.room.message",
            "content": [
                "msgtype": "m.text",
                "body": "Message number \(index)",
            ],
            "ts": baseTS,
            "seq": Int64(index),
            "status": "sent",
            "status_reason": "",
            "media_path": "",
            "bookmarked": false,
            "poll": NSNull(),
            "thread": NSNull(),
            "expires_at": 0,
            "delivered": false,
            "read_by": [[String: Any]](),
        ]
    }

    private func pump(_ host: NSView, for interval: TimeInterval, until condition: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded()
            if condition?() == true { break }
        }
    }

    private func asyncPump(_ host: NSView, for interval: TimeInterval, until condition: (() -> Bool)? = nil) async {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
            pump(host, for: 0.005)
            if condition?() == true { break }
        }
    }

    // MARK: 1. Highlight fade on the table engine

    func testHighlightFadeOnTableEngineClearsWithoutReMeasuringRowHeight() async throws {
        _ = NSApplication.shared
        let roomID = "!hl"
        let allEvents = (1 ... 60).map { Self.makeWireEvent(index: $0, roomID: roomID) }
        let server = try QAMockEngineServer { method, params in
            if method == "hello" {
                return ["protocol": CourierProtocol.version, "engine": "qa", "networks": ["slack"]]
            }
            if method == "room.events" {
                if let around = params?["around"] as? String, around == "$30" {
                    let slice = Array(allEvents[4 ..< 54].reversed()) // $5 .. $54, newest-first wire order
                    return [
                        "events": slice,
                        "before": ["ts": 1_792_500_000_000 + 5 * 60_000, "seq": 5],
                        "after": ["ts": 1_792_500_000_000 + 54 * 60_000, "seq": 54],
                    ]
                }
                let slice = Array(allEvents.suffix(50).reversed())
                return ["events": slice, "before": NSNull(), "after": NSNull()]
            }
            if method == "thread.unread" {
                return ["threads": [[String: Any]]()]
            }
            return [String: Any]()
        }
        servers.append(server)

        let dir = try makeTempDir()
        let supervisor = EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: dir,
            environment: [:],
            launcher: QAMockLauncher(socketPath: server.socketPath)
        )
        let app = AppModel(supervisor: supervisor)
        apps.append(app)
        let store = makeDefaults()
        let prefs = ComposerPreferences(defaults: store)
        prefs.timelineEngine = .table
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: store))
        let sleepGate = QASleepGate(targetDuration: ConversationModel.highlightDuration)
        let conversation = ConversationModel(
            appModel: app,
            preferences: prefs,
            sleep: { try await sleepGate.sleep(for: $0) }
        )
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(
            conversation: conversation, appModel: app, preferences: prefs, pasteboard: NoPasteboard()
        )

        var connectedCount = 0
        app.onConnect { _ in connectedCount += 1 }
        app.start()
        let connectDeadline = Date().addingTimeInterval(3.0)
        while (app.client == nil || connectedCount == 0), Date() < connectDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(app.client)

        let rootView = ConversationView(
            conversation: conversation,
            composer: conversation.composer,
            inbox: inbox,
            messageActions: messageActions,
            scheduled: ScheduledModel(appModel: app),
            preferences: prefs,
            thread: conversation.thread,
            focus: MessageFocus(),
            appModel: app
        )
        .environment(\.liquidGlass, false)
        .environment(\.colorScheme, .light)

        let size = NSSize(width: 720, height: 420)
        let host = NSHostingView(rootView: rootView)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        app.open(.message(roomID: roomID, eventID: "$30"))
        await asyncPump(host, for: 2.0) {
            conversation.isLoaded
                && conversation.highlightedMessageID == "$30"
                && sleepGate.pendingCount == 1
                && host.first(TimelineNSTableView.self) != nil
        }

        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        await asyncPump(host, for: 0.15)

        let targetRow = try XCTUnwrap(coordinator.entries.firstIndex { $0.id == "$30" })
        let neighborRow = try XCTUnwrap(coordinator.entries.firstIndex { $0.id == "$29" })
        XCTAssertTrue(coordinator.entries[targetRow].isHighlighted, "$30 entry must carry isHighlighted == true")
        XCTAssertFalse(coordinator.entries[neighborRow].isHighlighted, "neighbor $29 must not be highlighted")

        // Let the background measuring of rows off screen finish first (on a slow machine it is still running here),
        // so what is counted below is only what clearing the highlight does.
        var lastMisses = -1
        var quietSince = Date()
        let quietDeadline = Date().addingTimeInterval(5)
        while Date() < quietDeadline {
            await asyncPump(host, for: 0.05)
            if coordinator.heightCache.misses != lastMisses {
                lastMisses = coordinator.heightCache.misses
                quietSince = Date()
            } else if Date().timeIntervalSince(quietSince) >= 0.3 {
                break
            }
        }

        // Release the 3s highlight timer and verify only a targeted visual update runs (zero height cache misses).
        coordinator.heightCache.resetCounters()
        sleepGate.releaseHighlights()
        await asyncPump(host, for: 1.0) { conversation.highlightedMessageID == nil }
        await asyncPump(host, for: 0.15)

        XCTAssertNil(conversation.highlightedMessageID)
        let updatedTargetRow = try XCTUnwrap(coordinator.entries.firstIndex { $0.id == "$30" })
        XCTAssertFalse(coordinator.entries[updatedTargetRow].isHighlighted, "$30 entry must clear isHighlighted after highlightDuration")
        XCTAssertEqual(coordinator.heightCache.misses, 0, "clearing highlight fade must not invalidate or re-measure row heights")
    }

    // MARK: 2. readNewerIfAtBottom on the table engine

    func testReadNewerIfAtBottomLoadsNewerPagesUntilReachingLatestOnTableEngine() async throws {
        _ = NSApplication.shared
        let roomID = "!newer"
        let allEvents = (1 ... 90).map { Self.makeWireEvent(index: $0, roomID: roomID) }
        let server = try QAMockEngineServer { method, params in
            if method == "hello" {
                return ["protocol": CourierProtocol.version, "engine": "qa", "networks": ["slack"]]
            }
            if method == "room.events" {
                if let around = params?["around"] as? String, around == "$25" {
                    let slice = Array(allEvents[0 ..< 50].reversed()) // $1 .. $50
                    return [
                        "events": slice,
                        "before": NSNull(),
                        "after": ["ts": 1_792_500_000_000 + 50 * 60_000, "seq": 50],
                    ]
                }
                if let after = params?["after"] as? [String: Any], (after["seq"] as? Int) == 50 {
                    let slice = Array(allEvents[50 ..< 90].reversed()) // $51 .. $90, reaches latest
                    return [
                        "events": slice,
                        "before": ["ts": 1_792_500_000_000 + 51 * 60_000, "seq": 51],
                        "after": NSNull(),
                    ]
                }
                let slice = Array(allEvents.suffix(50).reversed())
                return ["events": slice, "before": NSNull(), "after": NSNull()]
            }
            if method == "thread.unread" {
                return ["threads": [[String: Any]]()]
            }
            return [String: Any]()
        }
        servers.append(server)

        let dir = try makeTempDir()
        let supervisor = EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: dir,
            environment: [:],
            launcher: QAMockLauncher(socketPath: server.socketPath)
        )
        let app = AppModel(supervisor: supervisor)
        apps.append(app)
        let store = makeDefaults()
        let prefs = ComposerPreferences(defaults: store)
        prefs.timelineEngine = .table
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: store))
        let conversation = ConversationModel(appModel: app, preferences: prefs)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(
            conversation: conversation, appModel: app, preferences: prefs, pasteboard: NoPasteboard()
        )

        var connectedCount = 0
        app.onConnect { _ in connectedCount += 1 }
        app.start()
        let connectDeadline = Date().addingTimeInterval(3.0)
        while (app.client == nil || connectedCount == 0), Date() < connectDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(app.client)

        let rootView = ConversationView(
            conversation: conversation,
            composer: conversation.composer,
            inbox: inbox,
            messageActions: messageActions,
            scheduled: ScheduledModel(appModel: app),
            preferences: prefs,
            thread: conversation.thread,
            focus: MessageFocus(),
            appModel: app
        )
        .environment(\.liquidGlass, false)

        let size = NSSize(width: 720, height: 360)
        let host = NSHostingView(rootView: rootView)
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

        app.open(.message(roomID: roomID, eventID: "$25"))
        // Wait past scrollToMessage's 0.05s + 0.30s serial confirmation delay.
        await asyncPump(host, for: 2.0) { conversation.isLoaded && host.first(TimelineNSTableView.self) != nil }
        await asyncPump(host, for: 0.5)

        XCTAssertTrue(conversation.isAwayFromLatest, "window around $25 starts away from latest")
        XCTAssertEqual(
            server.recordedParams(for: "room.events").filter { $0["after"] != nil }.count, 0,
            "while centered on $25 away from bottom, readNewerIfAtBottom must not fire loadNewer()"
        )

        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let scrollView = try XCTUnwrap(host.first(NSScrollView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)

        // Scroll down to the bottom of the around-window ($50) to trigger readNewerIfAtBottom -> loadNewer().
        coordinator.noteUserScrollForTesting()
        let clip = scrollView.contentView
        let bottomOriginY = max(
            -scrollView.contentInsets.top,
            tableView.bounds.maxY + scrollView.contentInsets.bottom - clip.bounds.height
        )
        clip.scroll(to: NSPoint(x: 0, y: bottomOriginY))
        scrollView.reflectScrolledClipView(clip)

        await asyncPump(host, for: 2.0) {
            !conversation.isAwayFromLatest && conversation.items.contains { $0.id == "$90" }
        }

        XCTAssertGreaterThanOrEqual(
            server.recordedParams(for: "room.events").filter { $0["after"] != nil }.count, 1,
            "reaching the bottom while away must trigger loadNewer() via readNewerIfAtBottom"
        )
        XCTAssertFalse(conversation.isAwayFromLatest, "final newer page reaches latest and exits away mode")
        XCTAssertTrue(coordinator.entries.contains { $0.id == "$90" }, "table entries must include newly paged $90")
    }

    // MARK: 3. Context menu & attachment clicks target the right row (including after reuse)

    func testContextMenuAndImageLightboxTargetExactRowAcrossCellReuse() throws {
        _ = NSApplication.shared
        let dir = try makeTempDir()
        let img1URL = dir.appendingPathComponent("photo1.png")
        let img2URL = dir.appendingPathComponent("photo2.png")
        try writePNG(to: img1URL, width: 320, height: 240)
        try writePNG(to: img2URL, width: 320, height: 240)

        var events: [Event] = []
        for idx in 1 ... 45 {
            let ts = 100 - idx
            if idx == 43 {
                var img1 = Fixture.event("$img1", mine: false, ts: ts, content: [
                    "msgtype": .string("m.image"), "body": .string("photo1.png"),
                    "info": .object(["w": .int(320), "h": .int(240), "mimetype": .string("image/png")]),
                ])
                img1.mediaPath = img1URL.path
                events.append(img1)
            } else if idx == 44 {
                var img2 = Fixture.event("$img2", mine: true, ts: ts, content: [
                    "msgtype": .string("m.image"), "body": .string("photo2.png"),
                    "info": .object(["w": .int(320), "h": .int(240), "mimetype": .string("image/png")]),
                ])
                img2.mediaPath = img2URL.path
                events.append(img2)
            } else {
                events.append(Fixture.text("$m\(idx)", "Row message #\(idx) for menu & reuse test", mine: idx % 2 == 0, ts: ts))
            }
        }
        let items = Fixture.items(events, isDirect: false)

        let store = makeDefaults()
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: dir, environment: [:], launcher: FoundationProcessLauncher()
        ))
        let prefs = ComposerPreferences(defaults: store)
        prefs.timelineEngine = .table
        let conversation = ConversationModel(appModel: app, preferences: prefs)
        final class CapturingPasteboard: TextPasteboard {
            var copied: [String] = []
            func setString(_ s: String) { copied.append(s) }
        }
        let pasteboard = CapturingPasteboard()
        let messageActions = MessageActionsModel(
            conversation: conversation, appModel: app, preferences: prefs, pasteboard: pasteboard
        )
        let ui = MessageUI()
        conversation.setSnapshotStateForTesting(
            roomID: "!menu-qa",
            items: items,
            row: Fixture.row("!menu-qa", "Menu QA", network: "slack", direct: false, ts: 1, preview: "hi"),
            features: Fixture.features
        )

        var performedCommands: [(MessageMenuItem.Command, String)] = []
        struct HostView: View {
            @ObservedObject var conversation: ConversationModel
            @ObservedObject var messageActions: MessageActionsModel
            let prefs: ComposerPreferences
            let ui: MessageUI
            let app: AppModel
            let onPerform: (MessageMenuItem.Command, String) -> Void

            var body: some View {
                var actions = MessageRowActions.make(
                    conversation: conversation, messageActions: messageActions,
                    preferences: prefs, composer: conversation.composer, ui: ui, source: .chat,
                    deselect: { conversation.deselectMessage() },
                    select: { conversation.selectedMessageID = $0 }
                )
                let origPerform = actions.perform
                actions.perform = { cmd, id in
                    onPerform(cmd, id)
                    origPerform(cmd, id)
                }
                return TimelineTableView(
                    conversation: conversation, messageActions: messageActions,
                    preferences: prefs, ui: ui, appModel: app, actions: actions,
                    effectiveHeaderInset: 0, bottomSafeAreaInset: 0, bottomBarSignature: [],
                    resolvedAppearance: nil, redact: false,
                    themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
                    drawsLiquidGlass: false, timelineCovered: false
                )
                .environment(\.liquidGlass, false)
            }
        }

        let size = NSSize(width: 680, height: 520)
        let host = NSHostingView(rootView: HostView(
            conversation: conversation, messageActions: messageActions, prefs: prefs, ui: ui, app: app,
            onPerform: { cmd, id in performedCommands.append((cmd, id)) }
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

        pump(host, for: 0.4) { host.first(TimelineNSTableView.self) != nil }
        let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
        let scrollView = try XCTUnwrap(host.first(NSScrollView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        pump(host, for: 0.25)

        // 1. Context menu at bottom row ($m45) acts on $m45.
        func invokeCopyFromContextMenu(for messageID: String) throws {
            let row = try XCTUnwrap(coordinator.entries.firstIndex { $0.id == messageID })
            let cell = try XCTUnwrap(tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TimelineCell)
            let winPoint = cell.hostingView.convert(NSPoint(x: cell.hostingView.bounds.midX, y: cell.hostingView.bounds.midY), to: nil)
            let rightClick = try XCTUnwrap(NSEvent.mouseEvent(
                with: .rightMouseDown, location: winPoint, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            let menu = try XCTUnwrap(cell.hostingView.menu(for: rightClick), "row \(messageID) must expose its SwiftUI context menu")
            let copyItem = try XCTUnwrap(menu.items.first { $0.isEnabled && $0.action != nil && $0.submenu == nil })
            _ = copyItem.target?.perform(copyItem.action, with: copyItem)
            pump(host, for: 0.1)
        }

        try invokeCopyFromContextMenu(for: "$m45")
        XCTAssertEqual(performedCommands.last?.1, "$m45", "context menu on $m45 must dispatch $m45")

        // 2. Click on image rows $img1 and $img2 opens each image in lightbox for the exact clicked row.
        for imgID in ["$img1", "$img2"] {
            let row = try XCTUnwrap(coordinator.entries.firstIndex { $0.id == imgID })
            tableView.scrollRowToVisible(row)
            pump(host, for: 0.15)
            let rowRect = tableView.rect(ofRow: row)
            // Click near bubble image center (incoming left side vs outgoing right side).
            let localX: CGFloat = imgID == "$img1" ? 160 : (rowRect.width - 160)
            let winPoint = tableView.convert(NSPoint(x: localX, y: rowRect.midY), to: nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: NSEvent.doubleClickInterval + 0.08))
            let ts = ProcessInfo.processInfo.systemUptime
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let ev = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: winPoint, modifierFlags: [], timestamp: ts,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                ))
                NSApp.sendEvent(ev)
            }
            pump(host, for: NSEvent.doubleClickInterval + 0.15) {
                conversation.activeLightboxMessageID != nil
            }
            if conversation.activeLightboxMessageID != nil {
                XCTAssertEqual(conversation.activeLightboxMessageID, imgID, "clicking \(imgID) must open \(imgID) in lightbox")
                conversation.closeLightbox()
            }
        }

        // 3. Scroll up to reuse cells, then verify context menu on $m2 targets $m2 (not a previously displayed row).
        for _ in 0 ..< 25 {
            coordinator.noteUserScrollForTesting()
            let clip = scrollView.contentView
            let minY = tableView.bounds.minY - scrollView.contentInsets.top
            clip.scroll(to: NSPoint(x: 0, y: max(minY, clip.bounds.origin.y - 180)))
            scrollView.reflectScrolledClipView(clip)
            pump(host, for: 0.02)
        }
        XCTAssertGreaterThan(coordinator.reusedCellCount, 0, "scrolling to top must reuse cells")
        performedCommands.removeAll()
        try invokeCopyFromContextMenu(for: "$m2")
        XCTAssertEqual(performedCommands.last?.1, "$m2", "reused cell context menu must dispatch new row $m2, not stale row")
    }

    // MARK: 4. Single-row re-measure, SwiftUI fallback live switch, and zero retain cycles

    func testSingleRowRemeasureSwiftUIFallbackAndZeroRetainCycles() throws {
        _ = NSApplication.shared
        let dir = try makeTempDir()
        let store = makeDefaults()
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: dir, environment: [:], launcher: FoundationProcessLauncher()
        ))
        let prefs = ComposerPreferences(defaults: store)
        prefs.timelineEngine = .table
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: store))
        let conversation = ConversationModel(appModel: app, preferences: prefs)
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let messageActions = MessageActionsModel(
            conversation: conversation, appModel: app, preferences: prefs, pasteboard: NoPasteboard()
        )
        let baseEvents = (1 ... 20).map { idx in
            Fixture.text("$m\(idx)", "Message #\(idx)", mine: idx % 2 == 0, ts: 40 - idx)
        }
        conversation.setSnapshotStateForTesting(
            roomID: "!lifecycle",
            items: Fixture.items(baseEvents, isDirect: false),
            row: Fixture.row("!lifecycle", "Lifecycle", network: "slack", direct: false, ts: 1, preview: "hi"),
            features: Fixture.features
        )

        weak var weakCoordinator: TimelineTableView.Coordinator?
        weak var weakTableView: TimelineNSTableView?
        weak var weakCellHostingView: NSView?

        try autoreleasepool {
            let rootView = ConversationView(
                conversation: conversation,
                composer: conversation.composer,
                inbox: inbox,
                messageActions: messageActions,
                scheduled: ScheduledModel(appModel: app),
                preferences: prefs,
                thread: conversation.thread,
                focus: MessageFocus(),
                appModel: app
            )
            .environment(\.liquidGlass, false)

            let size = NSSize(width: 700, height: 400)
            let host = NSHostingView(rootView: rootView)
            var window: NSWindow? = NSWindow(
                contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                backing: .buffered, defer: false
            )
            window?.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            window?.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window?.orderFrontRegardless()

            pump(host, for: 0.4) { host.first(TimelineNSTableView.self) != nil }
            let tableView = try XCTUnwrap(host.first(TimelineNSTableView.self))
            let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
            pump(host, for: 0.3)

            weakCoordinator = coordinator
            weakTableView = tableView
            if let cell = tableView.view(atColumn: 0, row: coordinator.entries.count - 1, makeIfNecessary: false) as? TimelineCell {
                weakCellHostingView = cell.hostingView
            }
            XCTAssertNotNil(weakCellHostingView)

            // 1. Editing one message re-measures ONLY that one row (misses == 1 across 20 messages + date separator).
            coordinator.heightCache.resetCounters()
            var edited = baseEvents
            edited[19] = Fixture.text("$m20", "Edited message #20 with enough text to wrap onto another line cleanly.", mine: true, ts: 20)
            conversation.setSnapshotItemsForTesting(Fixture.items(edited, isDirect: false))
            pump(host, for: 0.2)
            XCTAssertEqual(coordinator.heightCache.misses, 1, "editing a single message must re-measure only that 1 row")
            XCTAssertGreaterThan(coordinator.heightCache.hits, 0)

            // 2. Adding a reaction to one message re-measures ONLY that one row (misses == 1).
            coordinator.heightCache.resetCounters()
            let withReaction = edited + [
                Fixture.event("$rx20", type: "m.reaction", mine: false, ts: 19, content: [
                    "m.relates_to": .object([
                        "rel_type": .string("m.annotation"), "event_id": .string("$m20"), "key": .string("🔥"),
                    ]),
                ]),
            ]
            conversation.setSnapshotItemsForTesting(Fixture.items(withReaction, isDirect: false))
            pump(host, for: 0.2)
            XCTAssertEqual(coordinator.heightCache.misses, 1, "reacting to a single message must re-measure only that 1 row")

            // 3. Switching hidden timelineEngine to .swiftui unmounts the table and keeps working on LazyVStack.
            prefs.timelineEngine = .swiftui
            pump(host, for: 0.3) { host.first(TimelineNSTableView.self) == nil }
            XCTAssertNil(host.first(TimelineNSTableView.self), "swiftui engine must unmount TimelineNSTableView")
            XCTAssertNotNil(host.first(NSScrollView.self), "swiftui fallback engine must still render its ScrollView")

            // Tear down window and pump runloop so autoreleased AppKit views drain.
            window?.orderOut(nil)
            window?.contentView = nil
            window = nil
        }

        for _ in 0 ..< 25 {
            _ = autoreleasepool {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        }
        XCTAssertNil(weakCoordinator, "Coordinator must deallocate with no retain cycle")
        XCTAssertNil(weakTableView, "TimelineNSTableView must deallocate with no retain cycle")
        XCTAssertNil(weakCellHostingView, "Cell NSHostingView must deallocate with no retain cycle")
    }
}
