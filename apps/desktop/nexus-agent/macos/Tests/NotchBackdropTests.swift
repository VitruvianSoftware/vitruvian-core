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

/// The popped-out chat keeps the notch's look: the same black surface the
/// island draws behind the docked chat, not a frosted material that greys
/// the bubbles. Also writes a picture of it, to look at before a release.
final class NotchBackdropTests: XCTestCase {
    private static let size = CGSize(width: 520, height: 300)

    @MainActor
    func testThePoppedOutChatSitsOnTheNotchBlack() throws {
        let messages = [
            NexusAgentChatMessage(role: .user, text: "Why does the release build fail on Intel Macs?"),
            NexusAgentChatMessage(role: .agent, text: "The universal build links an **arm64-only** copy of `libsqlite`."),
        ]
        let view = ZStack(alignment: .top) {
            NexusAgentNotchBackdrop()
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
        let url = URL(fileURLWithPath: folder).appendingPathComponent("notch-backdrop-dark.png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        print("notch backdrop snapshot: \(url.path)")

        // Below the bubbles, away from the hairline: the surface itself.
        let surface = try XCTUnwrap(bitmap.colorAt(x: image.width / 2, y: image.height - 60)?.usingColorSpace(.sRGB))
        XCTAssertEqual(surface.alphaComponent, 1, accuracy: 0.01, "an opaque surface, not see-through glass")
        XCTAssertLessThan(max(surface.redComponent, surface.greenComponent, surface.blueComponent), 0.02,
                          "the island's black")
    }
}
