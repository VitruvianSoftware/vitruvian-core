// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import XCTest

@testable import Courier

/// How the chat pane lays out as the window is resized with a picture as its wallpaper (Settings ▸ Appearance). A
/// picture of a different shape from the pane must fill the pane and never size it: a wide picture once made the pane
/// as wide as the picture's shape asked for at the window's height, so a taller window grew wider, the messages were
/// cut off at both edges, and the window could not be made narrow.
@MainActor
final class WindowLayoutTests: XCTestCase {
    private var files: [URL] = []

    override func tearDown() async throws {
        for file in files { try? FileManager.default.removeItem(at: file) }
        files = []
        WallpaperImageCache.shared.removeAll()
    }

    /// A plain picture of the given size in pixels, written to a temporary PNG: no person's photo.
    private func picture(width: Int, height: Int) throws -> String {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let gradient = NSGradient(colors: [.systemTeal, .systemIndigo, .systemPink])
        gradient?.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 0)
        NSColor.white.withAlphaComponent(0.5).setStroke()
        for index in stride(from: 0, to: width, by: max(1, width / 12)) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: index, y: 0))
            path.line(to: NSPoint(x: index + height / 2, y: height))
            path.lineWidth = 6
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("courier-wallpaper-\(UUID().uuidString).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        files.append(url)
        return url.path
    }

    /// The size the wallpaper asks for when offered `proposal`: never more than it was offered, whatever the
    /// picture's shape, so it can't widen or heighten the pane.
    func testPictureWallpaperTakesTheSizeItIsOffered() throws {
        for (width, height) in [(3000, 600), (600, 3000), (1600, 1000)] {
            let path = try picture(width: width, height: height)
            for blur in [false, true] {
                let host = NSHostingController(rootView: ChatWallpaperCanvasView(
                    preset: .none, customImagePath: path, opacity: 0.6, blur: blur))
                for proposal in [CGSize(width: 420, height: 760), CGSize(width: 1280, height: 480),
                                 CGSize(width: 0, height: 800), CGSize(width: 900, height: 0)] {
                    let size = host.sizeThatFits(in: proposal)
                    XCTAssertLessThanOrEqual(size.width, proposal.width + 0.5,
                                             "a \(width)x\(height) picture offered \(proposal) asked for \(size)")
                    XCTAssertLessThanOrEqual(size.height, proposal.height + 0.5,
                                             "a \(width)x\(height) picture offered \(proposal) asked for \(size)")
                }
            }
        }
    }

    /// The picture is read from disk once, not on every redraw: a live resize redraws the pane every frame.
    func testPictureWallpaperIsReadOnce() throws {
        let path = try picture(width: 1200, height: 800)
        WallpaperImageCache.shared.removeAll()
        let first = WallpaperImageCache.shared.image(atPath: path)
        let second = WallpaperImageCache.shared.image(atPath: path)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second, "the second read must come from the cache")
        XCTAssertEqual(WallpaperImageCache.shared.diskReads, 1)
        // A picture larger than any screen is kept at a size a window can show, not at full size.
        let huge = try picture(width: 9000, height: 3000)
        let image = try XCTUnwrap(WallpaperImageCache.shared.image(atPath: huge))
        XCTAssertLessThanOrEqual(max(image.width, image.height), WallpaperImageCache.maxPixelSize)
        XCTAssertNil(WallpaperImageCache.shared.image(atPath: "/nonexistent/wallpaper.png"))
    }

    /// The chat pane at three window sizes, a wide picture as its wallpaper. Look at chat-pane-wallpaper-*: the
    /// picture fills the pane, the messages stay inside it, and the composer stays at the bottom.
    func testChatPaneWithPictureWallpaperSnapshots() throws {
        let path = try picture(width: 3000, height: 700)
        let ui = MessageUI()
        let actions = MessageActions()
        let messages = [
            Fixture.text("$w1", "Are we still on for the hike on Saturday?", mine: false, ts: 5,
                         sender: "@alice:courier.local", name: "Alice Example"),
            Fixture.text("$w2", "Yes. I'll bring coffee and the trail map.", mine: true, ts: 6),
            Fixture.text("$w3", "Great, see you at the trailhead at eight.", mine: false, ts: 7,
                         sender: "@alice:courier.local", name: "Alice Example"),
        ]
        for (name, width, height) in [("narrow", 420.0, 760.0), ("wide", 1100.0, 460.0), ("large", 1400.0, 900.0)] {
            let sizes = try Snapshot.render("chat-pane-wallpaper-\(name)", width: width, height: height) {
                VStack(spacing: 0) {
                    Text("Weekend Trail Crew")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Divider()
                    ZStack {
                        ChatWallpaperCanvasView(preset: .none, customImagePath: path, opacity: 0.7, blur: false)
                        VStack(alignment: .leading, spacing: 8) {
                            Spacer(minLength: 0)
                            ForEach(Fixture.items(messages, isDirect: false)) { item in
                                TimelineItemView(item: item, isSelected: false, showsSent: true, actions: actions,
                                                 ui: ui)
                            }
                        }
                        .padding(14)
                    }
                    Divider()
                    Text("Message")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            XCTAssertEqual(sizes.count, 2)
        }
    }

    /// Settings ▸ Appearance ▸ Use Liquid Glass: the surfaces that change, with it on and off, over a colourful window
    /// so the glass shows. Look at liquid-glass-on and liquid-glass-off: off is the look before the option.
    func testLiquidGlassSurfacesSnapshots() throws {
        func surfaces(glass: Bool) -> some View {
            ZStack {
                LinearGradient(colors: [.teal, .indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 10) {
                        ForEach(0 ..< 5) { index in
                            RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.2 + 0.15 * Double(index)))
                                .frame(width: 40, height: 40)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .frame(width: SpaceBar.width)
                    .frame(maxHeight: .infinity)
                    .courierSurface(.sidebarStrip)
                    VStack(spacing: 16) {
                        Text("Search chats and messages")
                            .padding(14)
                            .frame(width: 300, alignment: .leading)
                            .courierSurface(.floatingPanel(cornerRadius: 12, opaque: false))
                        Text("Command Bar")
                            .padding(14)
                            .frame(width: 300, alignment: .leading)
                            .courierSurface(.floatingPanel(cornerRadius: 12, opaque: true))
                        Spacer()
                        Text("Message")
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .courierSurface(.composerBar)
                    }
                    .padding(.vertical, 16)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chat Info").font(.headline)
                        Text("Members, media and links").foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                    .frame(width: 200)
                    .frame(maxHeight: .infinity)
                    .courierSurface(.sidePane)
                }
            }
            .environment(\.liquidGlass, glass)
        }
        for (name, glass) in [("liquid-glass-on", true), ("liquid-glass-off", false)] {
            let sizes = try Snapshot.render(name, width: 760, height: 420) { surfaces(glass: glass) }
            XCTAssertEqual(sizes.count, 2)
        }
        if AppearancePreferences.systemSupportsLiquidGlass {
            let on = try Data(contentsOf: Snapshot.directory.appendingPathComponent("liquid-glass-on-light.png"))
            let off = try Data(contentsOf: Snapshot.directory.appendingPathComponent("liquid-glass-off-light.png"))
            XCTAssertNotEqual(on, off, "with the option on, the surfaces draw differently from the plain look")
        }
    }
}
