// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

@MainActor
final class ScrollAndPhotoSizingQATests: XCTestCase {
    private var directory: URL!
    private var suites: [String] = []

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-qa-photos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for name in suites { ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name) }
        suites = []
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "courier.qa.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func writeImage(
        named name: String,
        type: UTType,
        width: Int,
        height: Int,
        orientation: Int? = nil
    ) throws -> String {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.25, green: 0.55, blue: 0.75, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = try XCTUnwrap(ctx.makeImage())
        let url = directory.appendingPathComponent(name)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        var props: [CFString: Any] = [:]
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url.path
    }

    private func imageMessage(id: String, path: String, fileName: String, mime: String = "image/jpeg") throws -> TimelineMessage {
        var event = Fixture.event(id, mine: false, ts: 10, content: [
            "msgtype": .string("m.image"),
            "body": .string(fileName),
            "info": .object(["mimetype": .string(mime)]),
        ])
        event.mediaPath = path
        return try XCTUnwrap(Fixture.items([event], isDirect: true).compactMap {
            if case let .message(m) = $0 { return m } else { return nil }
        }.first)
    }

    func testFirstFrameReservesHeaderSizeForEXIFFormatsAndBrokenFiles() async throws {
        // EXIF orientations 5-8 swap landscape (1200x800) to portrait (800x1200 -> 266.67x400) before async load.
        for tag in 5 ... 8 {
            let path = try writeImage(named: "exif-\(tag).jpg", type: .jpeg, width: 1200, height: 800, orientation: tag)
            XCTAssertEqual(ImagePixelSizeReader.read(path), CGSize(width: 800, height: 1200))
            let msg = try imageMessage(id: "$exif\(tag)", path: path, fileName: "exif-\(tag).jpg")
            let reserved = EnhancedImageView(message: msg).size
            XCTAssertEqual(reserved.width, 800.0 * (400.0 / 1200.0), accuracy: 0.5)
            XCTAssertEqual(reserved.height, 400, accuracy: 0.5)
        }

        // EXIF orientations 1 and 3 keep landscape (1200x800 -> 400x266.67).
        for tag in [1, 3] {
            let path = try writeImage(named: "exif-\(tag).jpg", type: .jpeg, width: 1200, height: 800, orientation: tag)
            XCTAssertEqual(ImagePixelSizeReader.read(path), CGSize(width: 1200, height: 800))
            let msg = try imageMessage(id: "$exif\(tag)", path: path, fileName: "exif-\(tag).jpg")
            let reserved = EnhancedImageView(message: msg).size
            XCTAssertEqual(reserved.width, 400, accuracy: 0.5)
            XCTAssertEqual(reserved.height, 800.0 * (400.0 / 1200.0), accuracy: 0.5)
        }

        // HEIC portrait with EXIF orientation 6, PNG, and GIF all reserve exact proportions in frame 1.
        let heic = try writeImage(named: "photo.heic", type: .heic, width: 1200, height: 800, orientation: 6)
        let heicMsg = try imageMessage(id: "$heic", path: heic, fileName: "photo.heic", mime: "image/heic")
        XCTAssertEqual(EnhancedImageView(message: heicMsg).size.height, 400, accuracy: 0.5)
        XCTAssertEqual(EnhancedImageView(message: heicMsg).size.width, 800.0 * (400.0 / 1200.0), accuracy: 0.5)

        let png = try writeImage(named: "wide.png", type: .png, width: 1200, height: 600)
        let pngMsg = try imageMessage(id: "$png", path: png, fileName: "wide.png", mime: "image/png")
        XCTAssertEqual(EnhancedImageView(message: pngMsg).size, CGSize(width: 400, height: 200))

        let gif = try writeImage(named: "clip.gif", type: .gif, width: 800, height: 400)
        let gifMsg = try imageMessage(id: "$gif", path: gif, fileName: "clip.gif", mime: "image/gif")
        XCTAssertTrue(gifMsg.isGIF)
        XCTAssertEqual(EnhancedImageView(message: gifMsg).size, CGSize(width: 400, height: 200))

        // Corrupt, empty, and missing files do not crash and reserve the 300x225 fallback box.
        let corruptURL = directory.appendingPathComponent("corrupt.jpg")
        try Data("not-an-image".utf8).write(to: corruptURL)
        let emptyURL = directory.appendingPathComponent("empty.png")
        try Data().write(to: emptyURL)
        let missingPath = directory.appendingPathComponent("missing.jpg").path

        for (index, badPath) in [corruptURL.path, emptyURL.path, missingPath].enumerated() {
            XCTAssertNil(ImagePixelSizeReader.read(badPath))
            let badMsg = try imageMessage(id: "$bad\(index)", path: badPath, fileName: "bad.jpg")
            XCTAssertEqual(EnhancedImageView(message: badMsg).size, CGSize(width: 300, height: 225))
        }

        // Pre-warmed cached photo draws and lays out at its final height on frame 1 with zero height jump.
        _ = await ThumbnailLoader.shared.thumbnail(atPath: png)
        let host = NSHostingView(rootView: EnhancedImageView(message: pngMsg).frame(width: 500))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        host.layoutSubtreeIfNeeded()
        let firstHeight = host.fittingSize.height
        try await Task.sleep(nanoseconds: 150_000_000)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(firstHeight, 200, accuracy: 1.0)
        XCTAssertEqual(host.fittingSize.height, firstHeight, accuracy: 0.5)
    }

    func testBottomFlipUpdatesJumpStateWithoutEvaluatingTimelineRows() throws {
        for engine in [TimelineEngine.table, .swiftui] {
            let store = makeDefaults()
            let app = AppModel(supervisor: EngineSupervisor(
                enginePath: "/nonexistent/vitruvian-courier-engine",
                dataDir: directory.appendingPathComponent("data-\(engine.rawValue)"),
                environment: [:], launcher: FoundationProcessLauncher()))
            let composerPrefs = ComposerPreferences(defaults: store)
            composerPrefs.timelineEngine = engine
            let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: store))
            let conversation = ConversationModel(appModel: app, preferences: composerPrefs)
            final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
            let messageActions = MessageActionsModel(
                conversation: conversation, appModel: app, preferences: composerPrefs, pasteboard: NoPasteboard())

            let events = (0 ..< 25).map { i in
                Fixture.text("$m\(i)", "Message row \(i) https://example.com/\(i)", mine: i % 2 == 0, ts: i + 1)
            }
            conversation.setSnapshotStateForTesting(
                roomID: "!qa-\(engine.rawValue)", items: Fixture.items(events, isDirect: true),
                row: Fixture.row("!qa-\(engine.rawValue)", "QA Chat", network: "signal", direct: true, ts: 25, preview: "hi"))

            let view = ConversationView(
                conversation: conversation, composer: conversation.composer, inbox: inbox, messageActions: messageActions,
                scheduled: ScheduledModel(appModel: app), preferences: composerPrefs, thread: conversation.thread,
                focus: MessageFocus(), appModel: app)
                .environment(\.liquidGlass, false)

            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 800, height: 600),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFrontRegardless()
            defer {
                window.orderOut(nil)
                window.contentView = nil
            }

            let warmup = Date().addingTimeInterval(0.15)
            while Date() < warmup {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                host.layoutSubtreeIfNeeded()
            }

            var conversationChanges = 0
            let sub = conversation.objectWillChange.sink { conversationChanges += 1 }
            defer { sub.cancel() }

            ScrollPerfCounters.enabled = true
            ScrollPerfCounters.reset()
            defer { ScrollPerfCounters.enabled = false }

            conversation.scrolled(toBottom: false)
            RunLoop.main.run(mode: .default, before: Date())
            host.layoutSubtreeIfNeeded()
            XCTAssertFalse(conversation.isAtBottom, "engine=\(engine.rawValue)")

            conversation.scrolled(toBottom: true)
            RunLoop.main.run(mode: .default, before: Date())
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(conversation.isAtBottom, "engine=\(engine.rawValue)")

            XCTAssertEqual(conversationChanges, 0, "flipping at-bottom must not emit ConversationModel.objectWillChange (\(engine.rawValue))")
            XCTAssertEqual(ScrollPerfCounters.rowBodies, 0, "flipping at-bottom must not re-evaluate visible timeline rows (\(engine.rawValue))")
        }
    }

    func testSizeIsLearnedWhenTheFileAppearsAfterAFailedRead() throws {
        let path = directory.appendingPathComponent("late.png").path
        XCTAssertNil(ImagePixelSizeReader.sizeNow(ofFirstReadable: [path]))
        let written = try writeImage(named: "late.png", type: .png, width: 1200, height: 600)
        XCTAssertEqual(written, path)
        XCTAssertEqual(ImagePixelSizeReader.sizeNow(ofFirstReadable: [path]), CGSize(width: 1200, height: 600))
    }
}
