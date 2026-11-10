// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import AppKit
import NexusAgentCore
import SwiftUI
import XCTest

@testable import NexusAgentUI

/// The popped-out chat keeps the notch's look: the island's dark glass, a
/// black shade over Liquid Glass that lets a little of the desktop through
/// toward the bottom, and plain black when Reduce Transparency is on. Also
/// writes pictures of it, to look at before a release.
final class NotchBackdropTests: XCTestCase {
    private static let size = CGSize(width: 520, height: 300)

    func testTheShadeIsTheIslandsNearSolidAtTheTopAndThinnerAtTheLip() {
        XCTAssertEqual(NexusAgentNotchBackdrop.shadeOpacity(at: 0, increasedContrast: false), 1, accuracy: 0.001)
        XCTAssertEqual(NexusAgentNotchBackdrop.shadeOpacity(at: 1, increasedContrast: false), 0.55, accuracy: 0.001,
                       "the glass shows through at the bottom, as under the island's lip")
        XCTAssertGreaterThan(NexusAgentNotchBackdrop.shadeOpacity(at: 0.5, increasedContrast: false), 0.9,
                             "the middle, where the messages are, stays dark")
        XCTAssertGreaterThanOrEqual(NexusAgentNotchBackdrop.shadeOpacity(at: 1, increasedContrast: true), 0.9,
                                    "increased contrast keeps the surface almost solid")
    }

    @MainActor
    func testReduceTransparencyLeavesThePlainIslandBlack() throws {
        let bitmap = try render(reduceTransparency: true, name: "notch-backdrop-reduce-transparency.png")
        let surface = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 60)?.usingColorSpace(.sRGB))
        XCTAssertEqual(surface.alphaComponent, 1, accuracy: 0.01, "opaque, nothing shows through")
        XCTAssertLessThan(max(surface.redComponent, surface.greenComponent, surface.blueComponent), 0.02)
    }

    func testTheTintOverTheGlassThinsTowardTheBottom() {
        // The glass itself only draws on screen; what is checked here is the
        // shade laid over it, which is the same everywhere.
        let stops = NexusAgentNotchBackdrop.shade(increasedContrast: false)
        XCTAssertEqual(stops.first?.location, 0)
        XCTAssertEqual(stops.last?.location, 1)
        let opacities = stops.map { NexusAgentNotchBackdrop.shadeOpacity(at: $0.location, increasedContrast: false) }
        XCTAssertEqual(opacities, opacities.sorted(by: >), "never darker further down")
        XCTAssertLessThan(opacities.last ?? 1, 0.8, "not an opaque slab: the glass shows through at the bottom")
    }

    @MainActor
    func testTheGlassViewRenders() throws {
        // A picture to look at before a release. Off screen the glass has no
        // desktop behind it, and how it draws then depends on the machine.
        _ = try render(reduceTransparency: false, name: "notch-backdrop-glass.png")
    }

    @MainActor
    private func render(reduceTransparency: Bool, name: String) throws -> NSBitmapImageRep {
        let messages = [
            NexusAgentChatMessage(role: .user, text: "Why does the release build fail on Intel Macs?"),
            NexusAgentChatMessage(role: .agent, text: "The universal build links an **arm64-only** copy of `libsqlite`."),
        ]
        let view = ZStack(alignment: .top) {
            NexusAgentNotchBackdrop(reduceTransparencyOverride: reduceTransparency)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(messages) { message in
                    NexusAgentMessageBubble(message: message, strings: NexusAgentChatStrings(), errorScheme: "x-test")
                }
            }
            .padding(14)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw XCTSkip("ImageRenderer drew nothing here") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        let folder = ProcessInfo.processInfo.environment["TEST_UNDECLARED_OUTPUTS_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
        let png: Data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
        print("notch backdrop snapshot: \(url.path)")
        return bitmap
    }
}
