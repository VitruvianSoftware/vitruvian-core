// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// A repeatable scroll benchmark for the conversation timeline. Skipped unless `COURIER_SCROLL_BENCH=1`, so it adds
/// nothing to the normal run. It hosts a real ConversationView in a real window with a made-up chat (2,000 messages
/// of mixed length, replies, reactions, link cards, and 100 photos that are real JPEGs of a few MB), then drives the
/// real NSScrollView in fixed steps (300 up, then 300 down, 120 pt each), laying out and displaying after every
/// step, and times each step on the main thread. It prints one JSON line.
///
/// Run: `bazel test --config=macos-app --nocache_test_results --test_env=COURIER_SCROLL_BENCH=1
///   --test_filter=ScrollBenchmarkTests --test_output=all //apps/desktop/vitruvian-courier/app:VitruvianCourierViewTests`
/// `COURIER_SCROLL_BENCH_RENDER=1` also software-renders the view each step (`cacheDisplay`), which charges the
/// drawing (including any image decoding) to the main thread the way a slow frame would.
///
/// A headless benchmark is not a trackpad: it measures the main thread's work per step, not the GPU or the display.
@MainActor
final class ScrollBenchmarkTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        for name in suites { ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name) }
        suites = []
    }

    private func defaults() -> UserDefaults {
        let name = "courier.scrollbench.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func offlineApp() -> AppModel {
        AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-snapshots"),
            environment: [:], launcher: FoundationProcessLauncher()))
    }

    // MARK: Fixture chat

    /// A deterministic noisy JPEG, a few MB.
    private func writeNoisyJPEG(to url: URL, width: Int, height: Int, seed: UInt64) throws {
        var state = seed | 1
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let r = UInt8(truncatingIfNeeded: state)
            bytes[i] = r
            bytes[i + 1] = UInt8(truncatingIfNeeded: state >> 8) / 2 + UInt8(i % 97)
            bytes[i + 2] = UInt8(truncatingIfNeeded: state >> 16) / 3
            bytes[i + 3] = 255
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private static let paragraph = "This is a longer message that wraps over several lines in the bubble, the way a real "
        + "paragraph does when somebody explains a thing in detail and keeps going for a while so that layout has "
        + "real text to measure and the rows come out at many different heights."

    private func makeEvents(photoPaths: [String]) -> (events: [Event], photoCount: Int) {
        var events: [Event] = []
        var photos = 0
        let total = 2000
        for i in 0 ..< total {
            let id = "$b\(i)"
            let ts = (total - i) * 3
            let mine = i % 3 == 0
            let sender = mine ? nil : (i % 2 == 0 ? "@kent:courier.local" : "@ann:courier.local")
            let name = i % 2 == 0 ? "Kent Hua" : "Ann Example"
            if i % 20 == 7 {
                var event = Fixture.mediaEvent(id, msgtype: "m.image", body: "photo\(i).jpg", ts: ts)
                event.mediaPath = photoPaths[photos % photoPaths.count]
                if photos % 2 == 0 {
                    // Half the photos say how big they are; the rest (bridged ones) are sized from the file.
                    event = Fixture.event(id, mine: mine, ts: ts, content: [
                        "msgtype": .string("m.image"), "body": .string("photo\(i).jpg"),
                        "info": .object(["w": .int(2400), "h": .int(1600), "mimetype": .string("image/jpeg")]),
                    ], sender: sender, name: name)
                    event.mediaPath = photoPaths[photos % photoPaths.count]
                }
                events.append(event)
                photos += 1
                continue
            }
            let body: String
            switch i % 4 {
            case 0: body = "ok"
            case 1: body = "Sounds good, see you at the usual place tomorrow morning #\(i)"
            case 2: body = Self.paragraph
            default: body = Self.paragraph + " " + Self.paragraph
            }
            if i % 13 == 5, i > 3 {
                events.append(Fixture.event(id, mine: mine, ts: ts, content: [
                    "msgtype": .string("m.text"), "body": .string(body),
                    "m.relates_to": .object(["m.in_reply_to": .object(["event_id": .string("$b\(i - 3)")])]),
                ], sender: sender, name: name))
            } else if i % 17 == 11 {
                let url = "https://example.org/article-\(i)"
                var event = Fixture.text(id, "Have a look at \(url)", mine: mine, ts: ts, sender: sender, name: name)
                event.linkPreviews = [LinkPreviewItem(matchedURL: url, url: url,
                                                      title: "An article about the thing, number \(i)",
                                                      siteName: "example.org")]
                events.append(event)
            } else {
                events.append(Fixture.text(id, body, mine: mine, ts: ts, sender: sender, name: name))
            }
            if i % 9 == 3 {
                events.append(Fixture.event("$r\(i)", type: "m.reaction", mine: false, ts: max(1, ts - 1), content: [
                    "m.relates_to": .object([
                        "rel_type": .string("m.annotation"), "event_id": .string(id), "key": .string("👍"),
                    ]),
                ]))
            }
        }
        return (events, photos)
    }

    // MARK: Statistics

    private struct Stats {
        let steps: Int
        var photoHeightChanges = 0
        /// Which step was slowest (0-based), to look at what the content there was.
        let slowestStep: Int
        let medianMS, p95MS, maxMS: Double
        let over8: Int, over16: Int
        let rowBodiesPerStep, geometryPerStep: Double

        init(_ times: [Double], rowBodies: Int, geometry: Int) {
            let sorted = times.sorted()
            steps = times.count
            slowestStep = times.firstIndex(of: sorted.last ?? 0) ?? 0
            medianMS = sorted[sorted.count / 2]
            p95MS = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            maxMS = sorted.last ?? 0
            over8 = times.filter { $0 > 8.3 }.count
            over16 = times.filter { $0 > 16.7 }.count
            rowBodiesPerStep = Double(rowBodies) / Double(max(1, times.count))
            geometryPerStep = Double(geometry) / Double(max(1, times.count))
        }

        var json: String {
            func f(_ v: Double) -> String { String(format: "%.2f", v) }
            return "{\"steps\":\(steps),\"median_ms\":\(f(medianMS)),\"p95_ms\":\(f(p95MS)),\"max_ms\":\(f(maxMS)),\"slowest_step\":\(slowestStep),"
                + "\"photo_height_changes\":\(photoHeightChanges),\"over_8_3ms\":\(over8),\"over_16_7ms\":\(over16),\"row_bodies_per_step\":\(f(rowBodiesPerStep)),"
                + "\"geometry_callbacks_per_step\":\(f(geometryPerStep))}"
        }
    }

    // MARK: The benchmark

    func testTimelineScrollBenchmark() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["COURIER_SCROLL_BENCH"] == "1", "set COURIER_SCROLL_BENCH=1 to run")
        let renders = environment["COURIER_SCROLL_BENCH_RENDER"] == "1"

        // Photos: 4 distinct JPEGs, hard-linked to 100 paths so each is its own file to the loader and its cache.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("courier-scroll-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var bases: [URL] = []
        for index in 0 ..< 4 {
            let url = directory.appendingPathComponent("base\(index).jpg")
            try writeNoisyJPEG(to: url, width: 2400, height: 1600, seed: UInt64(0x9E37_79B9) &* UInt64(index + 1))
            bases.append(url)
        }
        let jpegBytes = try bases.map { try XCTUnwrap(FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) }
        var photoPaths: [String] = []
        for index in 0 ..< 100 {
            let link = directory.appendingPathComponent("photo\(index).jpg")
            try FileManager.default.linkItem(at: bases[index % bases.count], to: link)
            photoPaths.append(link.path)
        }

        let (events, photoCount) = makeEvents(photoPaths: photoPaths)
        // Photo rows that change height after they are first laid out: a picture's space not reserved before it loads.
        let photoRows = Set(stride(from: 7, to: 2000, by: 20).map { "item/$b\($0)" })
        var photoHeights: [String: CGFloat] = [:]
        var photoHeightChanges = 0
        let items = Fixture.items(events, isDirect: false)

        let store = defaults()
        let app = offlineApp()
        let composerPreferences = ComposerPreferences(defaults: store)
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: store))
        let conversation = ConversationModel(appModel: app, preferences: composerPreferences)
        final class NoPasteboard: TextPasteboard {
            func setString(_: String) {}
        }
        let messageActions = MessageActionsModel(
            conversation: conversation, appModel: app, preferences: composerPreferences, pasteboard: NoPasteboard())
        conversation.setSnapshotStateForTesting(
            roomID: "!bench", items: items,
            row: Fixture.row("!bench", "Bench group", network: "slack", direct: false, ts: 1, preview: "ok"))

        let rootView = ConversationView(
            conversation: conversation, composer: conversation.composer, inbox: inbox, messageActions: messageActions,
            scheduled: ScheduledModel(appModel: app), preferences: composerPreferences, thread: conversation.thread,
            focus: MessageFocus(), appModel: app)
            .environment(\.liquidGlass, false)
            .environment(\.conversationLayoutProbe) { name, frame in
                guard photoRows.contains(name) else { return }
                if let last = photoHeights[name], abs(last - frame.height) > 0.5 { photoHeightChanges += 1 }
                photoHeights[name] = frame.height
            }

        let size = NSSize(width: 900, height: 700)
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

        func pump(for interval: TimeInterval) {
            let deadline = Date().addingTimeInterval(interval)
            while Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                host.layoutSubtreeIfNeeded()
            }
        }
        // Past the 1.5 s the view spends pinning to the newest message.
        pump(for: 1.8)
        let scrollView = try XCTUnwrap(host.first(NSScrollView.self), "ConversationView must host an NSScrollView")
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))

        func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }

        /// One step: move the clip view by `delta` (negative = up the chat), then do the work a frame would.
        func step(_ delta: CGFloat) -> Double {
            // The view treats a scroll that wasn't the person's (nobody has used the wheel for 0.6 s) as content
            // growing under it, and follows the bottom; so each step is announced as a wheel event the app's
            // monitors see (it reaches no window, so it moves nothing itself). Not timed.
            if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                wheel1: Int32(-delta), wheel2: 0, wheel3: 0),
               let wheel = NSEvent(cgEvent: cg)
            {
                NSApplication.shared.sendEvent(wheel)
            }
            let start = now()
            if let doc = scrollView.documentView {
                let clip = scrollView.contentView
                let sign: CGFloat = doc.isFlipped ? 1 : -1
                let minY = doc.bounds.minY
                let maxY = max(minY, doc.bounds.maxY - clip.bounds.height)
                let target = min(maxY, max(minY, clip.bounds.origin.y + sign * delta))
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: target))
                scrollView.reflectScrolledClipView(clip)
            }
            RunLoop.main.run(mode: .default, before: Date())
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            if renders { host.cacheDisplay(in: host.bounds, to: rep) }
            CATransaction.flush()
            return now() - start
        }

        ScrollPerfCounters.enabled = true
        defer { ScrollPerfCounters.enabled = false }

        // Warm-up (not measured): a few steps so first-use costs of the window don't land in step 1.
        for _ in 0 ..< 5 { _ = step(-120) }
        for _ in 0 ..< 5 { _ = step(120) }
        pump(for: 0.3)

        func phase(_ delta: CGFloat) -> Stats {
            ScrollPerfCounters.reset()
            photoHeightChanges = 0
            var times: [Double] = []
            for _ in 0 ..< 300 { times.append(step(delta)) }
            var stats = Stats(times, rowBodies: ScrollPerfCounters.rowBodies, geometry: ScrollPerfCounters.geometryCallbacks)
            stats.photoHeightChanges = photoHeightChanges
            return stats
        }
        let up = phase(-120)
        let down = phase(120)
        // The floor: the same step without moving (the cost of the harness and an idle layout pass).
        let idle = phase(0)

        // A conversation-level change (the bottom flag flipping: the person leaves the newest message, or comes
        // back), with the timeline in view: what does each one cost, and how many rows' bodies does it evaluate?
        let toggles = 20
        var toggleTimes: [Double] = []
        ScrollPerfCounters.reset()
        for index in 0 ..< toggles {
            let start = now()
            conversation.scrolled(toBottom: index % 2 == 1)
            RunLoop.main.run(mode: .default, before: Date())
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            CATransaction.flush()
            toggleTimes.append(now() - start)
        }
        let rowsPerToggle = Double(ScrollPerfCounters.rowBodies) / Double(toggles)
        let toggleMedian = toggleTimes.sorted()[toggles / 2]

        let jpegMB = jpegBytes.map { String(format: "%.1f", Double($0) / 1_048_576) }.joined(separator: "/")
        let line = "COURIER_SCROLL_BENCH_RESULT {\"mode\":\"\(renders ? "render" : "layout")\",\"messages\":\(events.count),"
            + "\"photos\":\(photoCount),\"jpeg_mb\":\"\(jpegMB)\","
            + "\"up\":\(up.json),\"down\":\(down.json),\"idle\":\(idle.json),"
            + "\"conversation_change\":{\"median_ms\":\(String(format: "%.2f", toggleMedian)),"
            + "\"row_bodies\":\(String(format: "%.1f", rowsPerToggle))}}"
        print(line)
        XCTAssertGreaterThan(up.steps, 0)
    }
}
