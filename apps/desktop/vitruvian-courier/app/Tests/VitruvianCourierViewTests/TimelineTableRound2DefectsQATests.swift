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

/// QA Round 2 defect reproduction tests (expected to fail against f89c025ef; left uncommitted per QA rules).
@MainActor
final class TimelineTableRound2DefectsQATests: XCTestCase {
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
        let name = "courier.tableround2defects.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-table-r2-defects-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirs.append(url)
        return url
    }

    private func pump(_ host: NSView? = nil, for interval: TimeInterval, until condition: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            host?.layoutSubtreeIfNeeded()
            if condition?() == true { break }
        }
    }

    private func writePNG(to url: URL, width: Int, height: Int) throws {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: 0.25, green: 0.55, blue: 0.85, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = try XCTUnwrap(ctx.makeImage())
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    private func makeGIFData(width: Int, height: Int, red: CGFloat) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: red, green: 0.3, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = try XCTUnwrap(ctx.makeImage())
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    private func writeTwoPagePDF(to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 360, height: 240)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        for page in 1 ... 2 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 0.2 * CGFloat(page), green: 0.4, blue: 0.8, alpha: 1))
            context.fill(mediaBox)
            context.endPDFPage()
        }
        context.closePDF()
    }

    // MARK: Defect 1 — LinkPreviewCardView sizes its picture from the picture's proportions (up to 200 pt), not one fixed height

    func testWideLinkPreviewBannerKeepsImageProportionalHeightUpTo200() throws {
        _ = NSApplication.shared
        let dir = try makeTempDir()
        let bannerURL = dir.appendingPathComponent("banner-640x240.png")
        let tallURL = dir.appendingPathComponent("tall-640x480.png")
        try writePNG(to: bannerURL, width: 640, height: 240) // 320 * 240 / 640 = 120 pt
        try writePNG(to: tallURL, width: 640, height: 480)   // min(200, 320 * 480 / 640) = 200 pt

        LocalFileFacts.warm(paths: [bannerURL.path, tallURL.path])
        _ = ImagePixelSizeReader.sizeNow(ofFirstReadable: [bannerURL.path])
        _ = ImagePixelSizeReader.sizeNow(ofFirstReadable: [tallURL.path])

        let bannerPreview = LinkPreviewItem(
            matchedURL: "https://example.com/banner",
            url: "https://example.com/banner",
            title: "Same single-line title",
            siteName: "example.com",
            imagePath: bannerURL.path,
            imageWidth: 640,
            imageHeight: 240
        )
        let tallPreview = LinkPreviewItem(
            matchedURL: "https://example.com/tall",
            url: "https://example.com/tall",
            title: "Same single-line title",
            siteName: "example.com",
            imagePath: tallURL.path,
            imageWidth: 640,
            imageHeight: 480
        )

        let bannerHost = NSHostingView(rootView: LinkPreviewCardView(preview: bannerPreview).frame(width: 320))
        let tallHost = NSHostingView(rootView: LinkPreviewCardView(preview: tallPreview).frame(width: 320))
        let bannerHeight = bannerHost.fittingSize.height
        let tallHeight = tallHost.fittingSize.height

        XCTAssertGreaterThanOrEqual(
            tallHeight - bannerHeight,
            70,
            "640x240 banner link preview (120pt picture) must be ~80pt shorter than 640x480 preview (200pt picture), got banner=\(bannerHeight) tall=\(tallHeight)"
        )
    }

    // MARK: Defect 2 — Cold PDF snapshot renders chip, extensionless media-store PDFs never warm, and InlinePDFView outside table never updates to card

    func testColdPDFSnapshotAndExtensionlessMediaStorePDFRenderCardInsteadOfChip() throws {
        _ = NSApplication.shared
        let dir = try makeTempDir()

        // (a) Exact ViewSnapshotTests pattern (cold Snapshot.render on a fresh PDF path): must render the >250pt PDF card, not 80pt chip.
        InlinePDFDocumentCache.shared.resetForTests()
        InlinePDFDocumentCache.installWarmer()
        let snapshotPDFURL = dir.appendingPathComponent("Trail-Permit-2026.pdf")
        try writeTwoPagePDF(to: snapshotPDFURL)
        var snapshotEvent = Fixture.event("$pdf-snap", mine: false, ts: 10, content: [
            "msgtype": .string("m.file"),
            "body": .string("Trail-Permit-2026.pdf"),
            "filename": .string("Trail-Permit-2026.pdf"),
            "info": .object(["mimetype": .string("application/pdf"), "size": .int(12_345)]),
        ])
        snapshotEvent.mediaPath = snapshotPDFURL.path
        let snapshotMsg = try XCTUnwrap(Fixture.messages([snapshotEvent]).first)
        let renderedSizes = try Snapshot.render("qa-r2-pdf-card-page-1", width: 420) {
            InlinePDFView(message: snapshotMsg, initialPageIndex: 0).padding(14)
        }
        XCTAssertGreaterThan(
            renderedSizes[0].height,
            250,
            "Snapshot.render of InlinePDFView (page 1) must render the ~326pt PDF card, not the 80pt FileAttachmentChip (got \(renderedSizes[0].height))"
        )

        // (b) Real content-addressed media store path (<dataDir>/media/ab/<64-hex> — NO .pdf suffix on disk):
        //     warming events must pre-parse the PDF, and standalone/SwiftUI/ThreadPane InlinePDFView must render the card.
        let sha = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
        let mediaSubdir = dir.appendingPathComponent("media/ab", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaSubdir, withIntermediateDirectories: true)
        let blobURL = mediaSubdir.appendingPathComponent(sha)
        try writeTwoPagePDF(to: blobURL)

        var blobEvent = Fixture.event("$pdf-blob", mine: false, ts: 8, content: [
            "msgtype": .string("m.file"),
            "body": .string("Spec.pdf"),
            "filename": .string("Spec.pdf"),
            "info": .object(["mimetype": .string("application/pdf"), "size": .int(12_345)]),
        ])
        blobEvent.mediaPath = blobURL.path

        LocalFileFacts.warm(paths: LocalFileFacts.paths(in: [blobEvent]))
        XCTAssertTrue(
            InlinePDFDocumentCache.shared.hasDocument(atPath: blobURL.path),
            "extensionless media-store PDF blob must be warmed into InlinePDFDocumentCache"
        )
    }

    // MARK: Defect 3 — LocalFileFacts.warm drops false->true notification and visible table row stays stuck when missing file appears

    func testMountedTableRowUpdatesHeightWhenInitiallyMissingFileAppearsOnDisk() throws {
        _ = NSApplication.shared
        let dir = try makeTempDir()
        let lateImageURL = dir.appendingPathComponent("finishing-download.png")

        var linkEvent = Fixture.text("$link-dl", "See https://example.com/dl", mine: false, ts: 5)
        linkEvent.linkPreviews = [
            LinkPreviewItem(
                matchedURL: "https://example.com/dl",
                url: "https://example.com/dl",
                title: "Downloaded Preview",
                imagePath: lateImageURL.path
            ),
        ]
        let items = Fixture.items([linkEvent], isDirect: false)

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
            roomID: "!late-appear",
            items: items,
            row: Fixture.row("!late-appear", "Late Appear", network: "slack", direct: false, ts: 5, preview: "dl"),
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
        let size = NSSize(width: 640, height: 360)
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
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        pump(host, for: 0.2) { LocalFileFacts.cachedExists(lateImageURL.path) == false }

        let rowIdx = try XCTUnwrap(coordinator.entries.firstIndex { $0.id == "$link-dl" })
        let heightWhileMissing = tableView.rect(ofRow: rowIdx).height

        // Wait past missingLifetime (0.5 s), write the image to disk, and run warm(paths:) as a page refresh does.
        pump(host, for: LocalFileFacts.missingLifetime + 0.08)
        try writePNG(to: lateImageURL, width: 640, height: 360)
        LocalFileFacts.warm(paths: [lateImageURL.path])
        pump(host, for: 0.4)

        let heightAfterFileAppeared = tableView.rect(ofRow: rowIdx).height
        XCTAssertGreaterThan(
            heightAfterFileAppeared,
            heightWhileMissing + 100,
            "mounted row must re-measure once initially missing local file appears on disk (before=\(heightWhileMissing), after=\(heightAfterFileAppeared))"
        )
    }

    // MARK: Defect 4 — SwiftUI fallback engine and ThreadPane never upgrade extensionless media-store PDF rows from chip to card

    func testSwiftUILazyVStackNeverRendersExtensionlessMediaStorePDFCard() throws {
        _ = NSApplication.shared
        let dir = try makeTempDir()
        InlinePDFDocumentCache.shared.resetForTests()
        InlinePDFDocumentCache.installWarmer()

        let sha = "11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff"
        let mediaSubdir = dir.appendingPathComponent("media/11", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaSubdir, withIntermediateDirectories: true)
        let blobURL = mediaSubdir.appendingPathComponent(sha)
        try writeTwoPagePDF(to: blobURL)

        var pdfEvent = Fixture.event("$pdf-swiftui", mine: false, ts: 6, content: [
            "msgtype": .string("m.file"),
            "body": .string("thread-reply.pdf"),
            "filename": .string("thread-reply.pdf"),
            "info": .object(["mimetype": .string("application/pdf"), "size": .int(8_192)]),
        ])
        pdfEvent.mediaPath = blobURL.path
        let item = try XCTUnwrap(Fixture.items([pdfEvent], isDirect: false).first { $0.id == "$pdf-swiftui" })

        var renderedRowHeight: CGFloat = 0
        let ui = MessageUI()
        let root = ScrollView {
            LazyVStack(spacing: 0) {
                TimelineItemView(
                    item: item, isSelected: false, isHighlighted: false, showsSent: false,
                    actions: MessageActions(), ui: ui
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { renderedRowHeight = $0 }
            }
        }
        .frame(width: 480, height: 400)

        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 400)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        pump(host, for: 0.8) { renderedRowHeight > 240 }
        XCTAssertGreaterThan(
            renderedRowHeight,
            240,
            "LazyVStack row (SwiftUI fallback / ThreadPane) with extensionless media-store PDF must render the ~326pt PDF card, not stay stuck on FileAttachmentChip (got \(renderedRowHeight))"
        )
    }
}
